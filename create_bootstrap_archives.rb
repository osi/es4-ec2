#!/usr/bin/env ruby -wKU

require 'fileutils'
 
def upload(filename)
  system("scp #{filename} dev.electrotank.com:/opt/ec2")
  raise "unable to scp #{filename} - #{$?.exitstatus}" unless $?.success?

  FileUtils.rm filename
end

def append_args(args, options)
  options.each { |name,values| values.each { |value| args.push "--#{name}=#{value}" } }
end

def archive(source, dest, options = {})
  args = [ ]
  
  append_args args, :exclude  => %w(.svn .DS_Store ._),
                    :owner => %w(root),
                    :group => %w(wheel),
                    :directory => %w(bootstrap)
                    
  append_args args, options                    
  
  cmdline = "tar #{args.join(' ')} --numeric-owner -czvf #{dest} #{source}"
  
  system(cmdline)
  raise "unable to exec #{cmdline} - #{$?.exitstatus}" unless $?.success?
end
 
archive 'es4', 'es4.tar.gz'
upload 'es4.tar.gz' 

archive '.', 'setup.tar.gz', :exclude => 'es4' 
upload 'setup.tar.gz'
