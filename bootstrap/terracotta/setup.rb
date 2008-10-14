#!/usr/bin/env ruby
#
# Script to setup Terracotta on Amazon's EC2
#
# by peter royal - peter@electrotank.com
#

require 'fileutils'
require '/var/spool/ec2/meta-data'
require '../common'

module Terracotta
  INSTALL_ROOT = "/opt/terracotta"
  DISTRIBUTION = "http://s3.amazonaws.com/TCreleases/terracotta-generic-2.7.0.tar.gz"

  class Installer

    def install
      puts "Installing Terracotta"
      
      user = User.new "terracotta", INSTALL_ROOT
      
      Shell.download_and_extract DISTRIBUTION, { :directory => INSTALL_ROOT }

      FileUtils.ln_s "#{INSTALL_ROOT}/terracotta-2.7.0/", "#{INSTALL_ROOT}/terracotta"
      
      FileUtils.cp "tc-config.xml", INSTALL_ROOT
      
      service = Service.new "Terracotta", user
      service.start
    end
  end

end

(Terracotta::Installer.new).install
