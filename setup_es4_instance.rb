#!/usr/bin/ruby -rubygems

require 'electro_aws'
require "optparse"

aws = ElectroAws::Controller.new

opts = OptionParser.new do |opts|
  opts.banner = "Usage:  #{File.basename($PROGRAM_NAME)} [options]"
  
  opts.separator ""
  opts.separator "Specific Options:"
  
  opts.on( "-a", "--access-key access_key", "Your AWS access key ID." ) do |opt|
    aws.access_key = opt
  end
  
  opts.on( "-s", "--secret-key secret_key", "Your AWS secret access key." ) do |opt|
    aws.secret_key = opt
  end
  
  opts.on( "-i", "--ami-id ami_id", "ID of the AMI to launch" ) do |opt|
    aws.ami_id = opt
  end

  opts.on( "-t", "--instance-type type_name", "The name of the instance type to launch ( Defaults to 'c1.medium' )" ) do |opt|
    aws.instance_type = opt
  end
  
  modes = [:StandAlone, :Distributed, :Cluster, :Jet, :LoadTester]
  opts.on( "-m", "--mode mode", modes, "Type of instance to setup mode to use (#{modes.join(', ')})" ) do |opt|
    aws.mode = opt
  end
  
  opts.on( "-g", "--groups x,y,z", Array, "Security groups for instances. Defaults to 'default'" ) do |groups|
    aws.groups = groups
  end
  
  opts.on( "-k", "--keyname name", String, "The key pair to make available to these instances at boot" ) do |keypair|
    aws.keypair = keypair
  end
  
  opts.on( "--gateways count", Integer, "Number of gateways to launch when in distributed mode. Defaults to 1" ) do |gateways|
    aws.gateways = gateways
  end
  
  opts.on( "-d", "--debug", String, "Option description." ) do |opt|
    aws.debug = true    
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

if aws.mode.nil?
  opts.abort "Must specify --mode"
elsif aws.access_key.nil? or aws.secret_key.nil?
  opts.abort "Must specify --access-key and --secret-key"
elsif aws.keypair.nil?
  opts.abort "Must specify -keyname"
end

aws.provision
