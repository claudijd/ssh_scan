require 'sinatra/base'
require 'sinatra/namespace'
require 'ssh_scan/version'
require 'ssh_scan/policy'
require 'ssh_scan/job_queue'
require 'ssh_scan/database'
require 'ssh_scan/worker'
require 'json'
require 'haml'
require 'secure_headers'
require 'thin'
require 'securerandom'
require 'ssh_scan/authenticator'

module SSHScan
  class API < Sinatra::Base
    if ENV['RACK_ENV'] == 'test'
      configure do
        set :job_queue, JobQueue.new()
        set :authentication, false
      end
    end

    # Configure all the secure headers we want to use
    use SecureHeaders::Middleware
    SecureHeaders::Configuration.default do |config|
      config.cookies = {
        secure: true, # mark all cookies as "Secure"
        httponly: true, # mark all cookies as "HttpOnly"
      }
      config.hsts = "max-age=31536000; includeSubdomains; preload"
      config.x_frame_options = "DENY"
      config.x_content_type_options = "nosniff"
      config.x_xss_protection = "1; mode=block"
      config.x_download_options = "noopen"
      config.x_permitted_cross_domain_policies = "none"
      config.referrer_policy = "no-referrer"
      config.csp = {
        default_src: ["'none'"],
        frame_ancestors: ["'none'"],
        upgrade_insecure_requests: true, # see https://www.w3.org/TR/upgrade-insecure-requests/
      }
    end

    register Sinatra::Namespace

    before do
      headers "Server" => "ssh_scan_api"
      headers "Cache-control" => "no-store"
      headers "Pragma" => "no-cache"
    end

    # Custom 404 handling
    not_found do
      content_type "text/plain"
      "Invalid request, see API documentation here: \
https://github.com/mozilla/ssh_scan/wiki/ssh_scan-Web-API\n"
    end

    get '/' do
      content_type "text/plain"
      "See API documentation here: \
https://github.com/mozilla/ssh_scan/wiki/ssh_scan-Web-API\n"
    end

    get '/robots.txt' do
      content_type "text/plain"
      "User-agent: *\nDisallow: /\n"
    end

    get '/contribute.json' do
      content_type :json
      SSHScan::Constants::CONTRIBUTE_JSON.to_json
    end

    get '/__version__' do
      {
        :ssh_scan_version => SSHScan::VERSION,
        :api_version => SSHScan::API_VERSION,
      }.to_json
    end

    namespace "/api/v#{SSHScan::API_VERSION}" do
      before do
        content_type :json
        if settings.authentication == true
          token = request.env['HTTP_SSH_SCAN_AUTH_TOKEN']
          unless token && settings.authenticator.valid_token?(token)
            halt '{"error" : "authentication failure"}'
          end
        end
      end

      post '/scan' do
        options = {
          :sockets => [],
          :policy => File.join(Dir.pwd,
                               '/config/policies/mozilla_modern.yml'),
          :timeout => 2,
          :verbosity => nil,
          :fingerprint_database => "fingerprints.db",
        }
        options[:sockets] <<
          "#{params[:target]}:#{params[:port] ? params[:port] : "22"}"
        options[:policy_file] = options[:policy]
        options[:uuid] = SecureRandom.uuid
        settings.job_queue.add(options)
        {
          uuid: options[:uuid]
        }.to_json
      end

      get '/scan/results' do
        uuid = params[:uuid]

        return {"scan" => "not found"}.to_json if uuid.nil? || uuid.empty?

        settings.db.find_scan_result(uuid)
      end

      post '/scan/results/delete' do
        uuid = params[:uuid]

        if uuid.nil? || uuid.empty?
          return {"deleted" => "false"}.to_json
        else
          scan = settings.db.find_scan_result(uuid)
          if scan.empty?
            return {"deleted" => "false"}.to_json
          end
        end

        settings.db.delete_scan(uuid)
      end

      get '/scan/results/delete/all' do
        settings.db.delete_all
      end

      get '/work' do
        worker_id = params[:worker_id]
        logger.warn("Worker #{worker_id} polls for Job")
        job = settings.job_queue.next
        if job.nil?
          logger.warn("Worker #{worker_id} didn't get any work")
          {"work" => false}.to_json
        else
          logger.warn("Worker #{worker_id} got job #{job[:uuid]}")
          {"work" => job}.to_json
        end
      end

      post '/work/results/:worker_id/:uuid' do
        worker_id = params['worker_id']
        uuid = params['uuid']

        if worker_id.empty? || uuid.empty?
          return {"accepted" => "false"}.to_json
        end

        settings.db.add_scan(worker_id, uuid, JSON.parse(request.body.first).first)
      end

      get '/__lbheartbeat__' do
        {
          :status  => "OK",
          :message => "Keep sending requests. I am still alive."
        }.to_json
      end
    end

    def self.run!(options = {}, &block)
      set options

      configure do
        set :bind, options["bind"] || '127.0.0.1'
        set :server, "thin"
        set :logger, Logger.new(STDOUT)
        set :job_queue, JobQueue.new()
        set :db, SSHScan::DatabaseConfig.from_config_file
        set :results, {}
        set :authentication, options["authentication"]
        set :authenticator, SSHScan::Authenticator.from_config_file(
          options["config_file"]
        )
      end

      super do |server|
        # No SSL on app, SSL termination happens in nginx for a prod deployment
        server.ssl = false
      end
    end
  end
end
