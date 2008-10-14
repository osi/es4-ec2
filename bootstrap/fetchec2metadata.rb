#!/usr/bin/env ruby
# Copyright (c) 2007 by RightScale Inc., all rights reserved
#
# fetchec2metadata.rb: This script retrieves the EC2 Metadata and places
# it in /var/spool/ec2/meta-data/
#

require 'fileutils'
require 'common'

META_DIR   = "/var/spool/ec2/meta-data"
META_URL   = "http://169.254.169.254/latest/meta-data"

begin
  files = `curl #{Shell::CURL_OPTS} #{META_URL}/`
  raise "Failed to fetch directory: code #{$?.exitstatus} -- #{files}" unless $?.success?
  
  FileUtils.mkdir_p META_DIR
    
  File.open('/var/spool/ec2/meta-data.sh','w') do |bash|
  File.open('/var/spool/ec2/meta-data.rb','w') do |ruby|
    ruby.puts "EC2 = Hash.new"
    files.split.each do |file|
      if file =~ /\/$/
        # Ignore directories, currently only used for public_keys, which we get in a different way
      else
        url = "#{META_URL}/#{file}"
        data = `curl #{Shell::CURL_OPTS} --create-dirs #{url}`
        raise "Failed to fetch entry #{file}: code #{$?.exitstatus} -- #{data}" unless $?.success?
        
        File.open("#{META_DIR}/#{file}", "w") { |f| f.write data }
        
        env_name = 'EC2_' + file.gsub(/\W/, '_').upcase
        bash.puts "export #{env_name}='#{data}'"
        ruby.puts "EC2[:#{file.gsub(/\W/, '_').downcase}]='#{data}'"
      end
    end
  end
  end
  
  rescue Exception => e
  STDERR.puts "!!!!! FAILED TO FETCH EC2 META-DATA"
  STDERR.puts "!!!!! Error: #{e}"
  exit 1
end
