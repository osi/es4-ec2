#!/usr/bin/env ruby
#
# Script to setup ElectroServer 4 on Amazon's EC2
#
# by peter royal - peter@electrotank.com
#
#

require 'fileutils'
require "optparse"
require '/var/spool/ec2/meta-data'

$electroserver_version = "4.0.5"

$funny_version = "ElectroServer_#{$electroserver_version.gsub('.','_')}"
$distribution = "http://www.electro-server.com/downloads/builds/#{$funny_version}_unix.tar.gz"

$electroserver_tarball = "/tmp/es-#{$electroserver_version}.tar.gz"
$install_root = "/opt/electroserver"
$user = 'electroserver'

$derby = 'http://archive.apache.org/dist/db/derby/db-derby-10.2.2.0/db-derby-10.2.2.0-bin.tar.gz';

def do_shell_command(name, command, error)
  puts name
  `#{command}`
  raise "#{error}: code #{$?.exitstatus}" unless $?.success?
end

def download(src, target)
  do_shell_command "Downloading #{src} ...",
                   "curl -s -S -f -L --retry 7 -o #{target} #{src}",
                   "Failed to download #{src}"
end

def extract
  do_shell_command "Extracting tarball ...",
                   "tar --strip-components 1 --directory #{$install_root} -xvf #{$electroserver_tarball} #{$funny_version}/server",
                   "Unable to expand #{$electroserver_tarball}"
end

def update_electroserver_configuration
  download $derby, '/tmp/derby.tar.gz'
  FileUtils.mkdir '/tmp/derby'
  do_shell_command "Extracting derby ...",
                   "tar --strip-components 1 --directory /tmp/derby -xvf /tmp/derby.tar.gz",
                   "Unable to expand /tmp/derby.tar.gz"

  puts "Updating ES4 Configuration"
  IO.popen("java -cp '/tmp/derby/lib/derbytools.jar:/tmp/derby/lib/derby.jar' org.apache.derby.tools.ij", "w") do |derby|
    derby.puts "CONNECT 'jdbc:derby:#{$install_root}/server/db';"

    derby.puts "UPDATE GATEWAYLISTENERS SET HOSTNAME = '0.0.0.0';"
    
    ports = [9898, 9899, 1935, 8989]
    
    (1..2).each do |gateway_id|
      (0..ports.length).each do |protocol|
        derby.puts "INSERT INTO GATEWAYLISTENERS (GATEWAYID, HOSTNAME, PORT, PROTOCOLID) VALUES(#{gateway_id}, '0.0.0.0', #{ports[protocol]}, #{protocol + 1});"
      end
    end
    
    # derby.puts "UPDATE REGISTRYSETTINGS SET LISTENERIP = '#{EC2[:local_ipv4]}';"
    # derby.puts "UPDATE GATEWAYS SET PASSPHRASE = '#{options[:passphrase]}' WHERE GATEWAYID = 2;"
    
    derby.close
  end
end

def create_electroserver_user
  do_shell_command "Creating '#{$user}' user",
                   "adduser --system --group --home #{$install_root} #{$user}",
                   "Unable to add '#{$user}' user"
                   
  FileUtils.mkdir_p $install_root
  FileUtils.chown $user, $user, $install_root
  FileUtils.chmod 02775, $install_root
end

def create_run_scripts
  FileUtils.cp 'bin/run.sh', "#{$install_root}/server"
  FileUtils.ln_s "#{$install_root}/server/run.sh", "#{$install_root}/server/StandAlone"
  FileUtils.ln_s "#{$install_root}/server/run.sh", "#{$install_root}/server/Registry"
  FileUtils.ln_s "#{$install_root}/server/run.sh", "#{$install_root}/server/Gateway"
end

def normalize_permissions
  do_shell_command "Fixing ownership",
                   "chown -R #{$user}.#{$user} #{$install_root}",
                   "Unable to fix ownership"
  do_shell_command "Fixing permissions",
                   "chmod -R g+w,g+s,g+r #{$install_root}",
                   "Unable to fix ownership"
end

def setup_service
  puts "Setting up service ..."
  FileUtils.cp_r "service", "#{$install_root}"
  File.open("#{$install_root}/service/run", 'w') do |run|
    run.puts <<EOF
#!/bin/sh
dir=`pwd -P`
echo "*** starting electroserver"
exec 2>&1 envdir ./env setuidgid #{$user} $dir/../server/#{$mode}
EOF
  end
  FileUtils.chmod 0770, "#{$install_root}/service/run" 
end

def start_service
  puts "Starting ElectroServer ..."
  FileUtils.ln_s "#{$install_root}/service", "/service/electroserver"
end

def update_motd
  File.open("/etc/motd.tail", "w") do |motd|
    motd.puts <<EOF
Electrotank setup is complete.

ElectroServer #{$electroserver_version} has been installed.

Enjoy!
    
EOF
  end
end

# ------

options = {}
opts = OptionParser.new do |opts|
  opts.banner = "Usage:  #{File.basename($PROGRAM_NAME)} [options]"
  
  opts.separator ""
  opts.separator "Specific Options:"
  
  opts.on( "-m", "--mode MODE", [:StandAlone, :Registry, :Gateway], "ElectroServer mode to use (StandAlone, Gateway, Registry)" ) do |opt|
    options[:mode] = opt
  end
  
  opts.on( "-p", "--passphrase PASSPHRASE", "Passphrase to use for gateway/registry communication" ) do |opt|
    options[:passphrase] = opt
  end
  
  opts.separator "Common Options:"
  
  opts.on( "-h", "--help", "Show this message." ) do
    puts opts
    exit
  end  
end

opts.parse!(ARGV)

if options[:mode].nil?
  opts.abort("Must specify --mode and --passphrase")
end

$mode = options[:mode]

puts "Setting up #{$mode} ElectroServer instance... "

create_electroserver_user
download $distribution, $electroserver_tarball
extract
update_electroserver_configuration
create_run_scripts
setup_service
normalize_permissions
start_service
sleep 5
normalize_permissions
update_motd
