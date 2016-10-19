require 'ssh_scan/api'
require 'rack/test'
require 'json'

describe SSHScan::API do
  include Rack::Test::Methods

  def app
    SSHScan::API.new
  end

  it "should be able to GET __version__ correctly" do
    get "/api/v#{SSHScan::API_VERSION}/__version__"
    expect(last_response.status).to eql(200)
    expect(last_response.body).to eql({
      :ssh_scan_version => SSHScan::VERSION,
      :api_version => SSHScan::API_VERSION
    }.to_json)
  end

  it "should send a positive response on GET heartbeat if the API is reachable" do
    get "/api/v#{SSHScan::API_VERSION}/heartbeat"
    expect(last_response.status).to eql(200)
    expect(last_response.body).to eql({
      :status => "OK",
      :message => "Keep sending resquests. I am still alive."
    }.to_json)
  end

  it "should say ConnectTimeout for bad IP, and return valid JSON" do
    bad_ip = "192.168.255.255"
    port = "999"
    post "/api/v#{SSHScan::API_VERSION}/scan", {:target => bad_ip, :port => port}
    expect(last_response.status).to eql(200)
    expect(last_response.body).to eql([
    {
      :ssh_scan_version => SSHScan::VERSION,
      :ip => bad_ip,
      :port => port,
      :error => "ConnectTimeout: Connection timed out - user specified timeout",
      :hostname => ""
    }].to_json)
  end
end
