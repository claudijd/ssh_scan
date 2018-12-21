require 'rspec'
require 'ssh_scan/version'

describe SSHScan::VERSION do
  it "SSHScan::VERSION should be a string" do
    expect(SSHScan::VERSION).to be_kind_of(::String)
  end

  it "SSHScan::VERSION should have 3 levels" do
    expect(SSHScan::VERSION.split('.').size).to eql(3)
  end

  it "SSHScan::VERSION should have a number between 1-20 for each octet" do
    SSHScan::VERSION.split('.').each do |octet|
      expect(octet.to_i).to be >= 0
      expect(octet.to_i).to be <= 20
    end
  end

  it "SSHScan::API_VERSION should be a string" do
    expect(SSHScan::API_VERSION).to be_kind_of(::String)
  end

  it "SSHScan::API_VERSION should have 3 levels" do
    expect(SSHScan::API_VERSION.split('.').size).to eql(3)
  end

  it "SSHScan::API_VERSION should have a number between 1-20 for each octet" do
    SSHScan::API_VERSION.split('.').each do |octet|
      expect(octet.to_i).to be >= 0
      expect(octet.to_i).to be <= 20
    end
  end

end
