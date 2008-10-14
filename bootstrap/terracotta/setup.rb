#!/usr/bin/env ruby
#
# Script to setup Terracotta on Amazon's EC2
#
# by peter royal - peter@electrotank.com
#

require 'fileutils'
require '/var/spool/ec2/meta-data'
require '../common'

installer = Terracotta::Installer.new
installer.install
installer.setup_server
