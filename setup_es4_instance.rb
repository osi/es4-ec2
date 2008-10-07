#!/usr/bin/env ruby


# (0...50).map{ ('a'..'z').to_a[rand(26)] }.join

require 'pp'
require 'electro_aws'
require "optparse"

aws = ElectroAws::Controller.new

opts = OptionParser.new do |opts|
  opts.banner = "Usage:  #{File.basename($PROGRAM_NAME)} [options]"
  
  opts.separator ""
  opts.separator "Specific Options:"
  
  opts.on( "-a", "--access-key ACCESS_KEY", "Your AWS access key ID." ) do |opt|
    aws.access_key = opt
  end
  
  opts.on( "-s", "--secret-key SECRET_KEY", "Your AWS secret access key." ) do |opt|
    aws.secret_key = opt
  end
  
  opts.on( "-i", "--ami-id AMI_ID", "ID of the AMI to launch" ) do |opt|
    aws.ami_id = opt
  end
  
  opts.on( "-m", "--mode MODE", [:StandAlone, :Distributed], "ElectroServer mode to use (StandAlone, Distributed)" ) do |opt|
    aws.mode = opt
  end
  
  opts.on( "-g", "--groups x,y,z", Array, "Security groups for instances. Defaults to 'default'" ) do |groups|
    aws.groups = groups
  end
  
  opts.on( "-k", "--keyname name", String, "The key pair to make available to these instances at boot" ) do |keypair|
    aws.keypair = keypair
  end
  
  opts.on( "--gateways count", Integer, "Number of gateways to launch when in distributed mode. Defaults to 1" ) do |opt|
    aws.gateways = gateways
  end
  
  opts.separator ""
  opts.separator "Common Options:"
  
  opts.on( "-h", "--help", "Show this message." ) do
    puts opts
    exit
  end  
end

opts.load
opts.parse!(ARGV)

if aws.access_key.nil? or aws.secret_key.nil?
  opts.abort "Must specify --access-key and --secret-key"
elsif aws.keypair.nil?
  opts.abort "Must specify -keyname"
end

aws.provision
