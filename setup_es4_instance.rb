#!/usr/bin/env ruby

require 'pp'
require 'rubygems'
require 'right_aws'
require "optparse"

options = {:ami_id => "ami-4eda3e27"}

opts = OptionParser.new do |opts|
  opts.banner = "Usage:  #{File.basename($PROGRAM_NAME)} [options]"
  
  opts.separator ""
  opts.separator "Specific Options:"
  
  opts.on( "-a", "--access-key ACCESS_KEY", "Your AWS access key ID." ) do |opt|
    options[:access_key] = opt
  end
  
  opts.on( "-s", "--secret-key SECRET_KEY", "Your AWS secret access key." ) do |opt|
    options[:secret_key] = opt
  end
  
  opts.on( "-m", "--ami-id AMI_ID", "ID of the AMI to launch" ) do |opt|
    options[:ami_id] = opt
  end
  
  opts.separator "Common Options:"
  
  opts.on( "-h", "--help", "Show this message." ) do
    puts opts
    exit
  end  
end

opts.load
opts.parse!(ARGV)

if options[:access_key].nil? or options[:secret_key].nil?
  opts.abort("Must specify --access-key and --secret-key")
end

# -------

$ec2 = RightAws::Ec2.new(options[:access_key], options[:secret_key])

$instance = $ec2.run_instances(options[:ami_id], 1, 1, ['default'], 'ec2-electrotank-peter', File.new('init.sh').read)[0]

# pp $instance

$instance_id = $instance[:aws_instance_id]
$state = nil
$dns_name = nil

while $state != 'running'
  descriptor = $ec2.describe_instances([$instance_id])[0]
  $state = descriptor[:aws_state]
  $dns_name = descriptor[:dns_name]
  puts " .. waiting for instance to start .. "
  sleep 5
end

puts "#{$dns_name} has been started. "

puts $ec2.get_console_output($instance_id)[:aws_output]