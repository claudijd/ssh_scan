require 'sinatra/base'
require 'sinatra/namespace'
require 'ssh_scan/version'
require 'ssh_scan/policy'
require 'ssh_scan/job_queue'
require 'ssh_scan/worker'
require 'json'
require 'haml'
require 'secure_headers'
require 'thin'
require 'securerandom'

module SSHScan
  class API < Sinatra::Base
    configure do
      set :bind, '0.0.0.0'
      set :server, "thin"
      set :logger, Logger.new(STDOUT)
      set :job_queue, JobQueue.new()
      set :results, {}
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
      config.referrer_policy = "origin-when-cross-origin"
      config.csp = {
        default_src: %w('none'),
        frame_ancestors: %w('none'),
        upgrade_insecure_requests: true, # see https://www.w3.org/TR/upgrade-insecure-requests/
      }
    end

    register Sinatra::Namespace

    before do
      headers "Server" => "ssh_scan_api"
    end

    # Custom 404 handling
    not_found do
      content_type "text/plain"
      'Invalid request, see API documentation here: https://github.com/mozilla/ssh_scan/wiki/ssh_scan-Web-API'
    end

    get '/robots.txt' do
      content_type "text/plain"
      "User-agent: *\nDisallow: /\n"
    end

    get '/contribute.json' do
      content_type :json
      {
        :name => "ssh_scan api",
        :description => "An api for performing ssh compliance and policy scanning",
        :repository => {
          :url => "https://github.com/mozilla/ssh_scan",
          :tests => "https://travis-ci.org/mozilla/ssh_scan",
        },
        :participate => {
          :home => "https://github.com/mozilla/ssh_scan",
          :docs => "https://github.com/mozilla/ssh_scan",
          :irc => "irc://irc.mozilla.org/#infosec",
          :irc_contacts => [
            "claudijd",
            "pwnbus",
            "kang",
          ],
          :glitter => "https://gitter.im/mozilla-ssh_scan/Lobby",
          :glitter_contacts => [
            "claudijd",
            "pwnbus",
            "kang",
            "jinankjain",
            "agaurav77"
          ],
        },
        :bugs => {
          :list => "https://github.com/mozilla/ssh_scan/issues",
        },
        :keywords => [
          "ruby",
          "sinatra",
        ],
      }.to_json
    end

    namespace "/api/v#{SSHScan::API_VERSION}" do
      before do
        content_type :json
      end

      post '/scan' do
        options = {
          :sockets => [],
          :policy => File.expand_path("../../../policies/mozilla_modern.yml", __FILE__),
          :timeout => 2,
          :verbosity => nil,
          :fingerprint_database => "fingerprints.db",
        }
        options[:sockets] << "#{params[:target]}:#{params[:port] ? params[:port] : "22"}"
        options[:policy_file] = SSHScan::Policy.from_file(options[:policy])
        options[:uuid] = SecureRandom.uuid
        settings.job_queue.add(options)
        {
          uuid: options[:uuid]
        }.to_json
      end

      get '/scan/results' do
        #TODO: get a given scan result, by UUID and return it as JSON
        '{"I am not finished yet"}'
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

        if worker_id.empty? or uuid.empty?
          return {"accepted" => "false"}.to_json
        end

        # TODO: add work results to datastore, whatever that ends up being

        return {"accepted" => "true"}.to_json
      end

      get '/__version__' do
        {
          :ssh_scan_version => SSHScan::VERSION,
          :api_version => SSHScan::API_VERSION,
        }.to_json
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

      super do |server|
        server.ssl = true
        ssl_opts = {:verify_peer => false}
        ssl_opts[:cert_chain_file] = options[:crt] if options[:crt]
        ssl_opts[:private_key_file] = options[:key] if options[:key]
        server.ssl_options = ssl_opts
      end
    end
  end
end
