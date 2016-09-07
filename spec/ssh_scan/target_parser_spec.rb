require 'rspec'
require 'ssh_scan/target_parser'
require 'set'

describe SSHScan::TargetParser do
  context "FQDN" do
    it "should return an array containing that URL" do
      target_parser = SSHScan::TargetParser.new()
      unsanitized = target_parser.enumerateIPRange("github.com")
      expect(target_parser.sanitizeIPRange(unsanitized)).to eq(["github.com:22"].to_set)
    end
  end

  context "IPv4" do
    it "should return an array containing that IPv4" do
      target_parser = SSHScan::TargetParser.new()
      unsanitized = target_parser.enumerateIPRange("192.168.1.1")
      expect(target_parser.sanitizeIPRange(unsanitized)).to eq(["192.168.1.1:22"].to_set)
    end
  end

  context "IPv4 Range seperated by '-'" do
    it "should return an array containing all the IPv4 in that range" do
      target_parser = SSHScan::TargetParser.new()
      unsanitized = target_parser.enumerateIPRange("192.168.1.1-2")
      expect(target_parser.sanitizeIPRange(unsanitized)).to eq(["192.168.1.1:22", "192.168.1.2:22"].to_set)
    end
  end

  context "IPv4 with subnet mask specified" do
    it "should return an array containing all the IPv4 in that range" do
      target_parser = SSHScan::TargetParser.new()
      unsanitized = target_parser.enumerateIPRange("192.168.1.0/30")
      expect(target_parser.sanitizeIPRange(unsanitized)).to eq(["192.168.1.1:22", "192.168.1.2:22"].to_set)
    end
  end
end
