#!/usr/bin/env ruby

require 'pp'
require 'rubygems'
require 'right_aws'

$access_key = '1V94TT6HNNEJX2FZ1ZG2'
$secret_key = 'I+S76whnjF+XmB5Lvu3g8FwuBO1yVc/kDi5VdGUw'

$ami_id = 'ami-4eda3e27'

# -------

$ec2 = RightAws::Ec2.new($access_key, $secret_key)

$instance = $ec2.run_instances($ami_id, 1, 1, ['default'], 'ec2-electrotank-peter', File.new('init.sh').read)[0]

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