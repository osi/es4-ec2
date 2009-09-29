#!/usr/bin/env ruby -wKU

require 'fileutils'
require 'bootstrap/common'
 
tarball = 'setup.tar.gz'

args = Shell.prepare_tar_args( { :exclude => %w(.svn .DS_Store ._* .git *~),
                                 # :owner => %w(root),
                                 # :group => %w(wheel),
                                 :directory => %w(bootstrap) 
                               } )

Shell.do "Creating #{tarball}", "export COPYFILE_DISABLE=true && tar #{args} -czvf #{tarball} ."

Shell.do "Uploading #{tarball}", "scp #{tarball} scott@dev.electrotank.com:/opt/ec2"

FileUtils.rm tarball
