require 'socket'
require 'ssh_scan/constants'
require 'ssh_scan/protocol'
require 'ssh_scan/banner'
require 'ssh_scan/error'

module SSHScan
  class Client
    def initialize(target, port, timeout = 3)
      @target = target
      @timeout = timeout

      if @target.ip_addr?
        @ip = @target
      else
        @ip = @target.resolve_fqdn()
      end

      @port = port
      @client_banner = SSHScan::Constants::DEFAULT_CLIENT_BANNER
      @server_banner = nil
      @kex_init_raw = SSHScan::Constants::DEFAULT_KEY_INIT_RAW
    end

    def connect()
      begin
        @sock = Socket.tcp(@ip, @port, connect_timeout: @timeout)
      rescue Errno::ETIMEDOUT => e
        @error = SSHScan::Error::ConnectTimeout.new(e.message)
        @sock = nil
      else
        @raw_server_banner = @sock.gets.chomp
        @server_banner = SSHScan::Banner.read(@raw_server_banner)
        @sock.puts(@client_banner.to_s)
      end
    end

    def get_kex_result(kex_init_raw = @kex_init_raw)
      # Common options for all cases
      result = {}
      result[:ssh_scan_version] = SSHScan::VERSION
      result[:hostname] = @target.fqdn? ? @target : ""
      result[:ip] = @ip
      result[:port] = @port

      if !@sock
        result[:error] = @error
        return result
      end

      @sock.write(kex_init_raw)
      resp = @sock.read(4)
      resp += @sock.read(resp.unpack("N").first)
      @sock.close

      kex_exchange_init = SSHScan::KeyExchangeInit.read(resp)

      # Assemble and print results
      result[:server_banner] = @server_banner
      result[:ssh_version] = @server_banner.ssh_version
      result[:os] = @server_banner.os_guess.common
      result[:os_cpe] = @server_banner.os_guess.cpe
      result[:ssh_lib] = @server_banner.ssh_lib_guess.common
      result[:ssh_lib_cpe] = @server_banner.ssh_lib_guess.cpe
      result.merge!(kex_exchange_init.to_hash)

      return result
    end
  end
end
