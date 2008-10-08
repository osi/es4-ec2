#!/usr/bin/env ruby
#
# Script to setup ElectroServer 4 on Amazon's EC2
#
# by peter royal - peter@electrotank.com
#

require 'fileutils'
require "optparse"
require '/var/spool/ec2/meta-data'

class Shell
  CURL_OPTS = "-s -S -f -L --retry 7"
  
  def Shell.do(name, command)
    puts name
    system command
    raise "failed : #{command} : code #{$?.exitstatus}" unless $?.success?
  end

  def Shell.fetch(src, target)
    Shell.do "Downloading #{src} ...", "curl #{CURL_OPTS} -o #{target} #{src}"
  end
end

class Derby
  TARBALL = 'http://archive.apache.org/dist/db/derby/db-derby-10.2.2.0/db-derby-10.2.2.0-bin.tar.gz'
  
  def Derby.open(database, &actions)
    FileUtils.mkdir '/tmp/derby'

    Shell.do "Downloading and extracting #{TARBALL}", 
             "curl #{Shell::CURL_OPTS} #{TARBALL} | tar --strip-components 1 --directory /tmp/derby -xzf -"

    IO.popen("java -cp '/tmp/derby/lib/derbytools.jar:/tmp/derby/lib/derby.jar' org.apache.derby.tools.ij", "w") do |derby|
      derby.puts "CONNECT 'jdbc:derby:#{database}';"
      actions.call(derby)
      derby.close
    end
  end
end

module ElectroServer
  VERSION = "4.0.5"
  NAMED_VERSION = "ElectroServer_#{VERSION.gsub('.','_')}"
  DISTRIBUTION = "http://www.electro-server.com/downloads/builds/#{NAMED_VERSION}_unix.tar.gz"
  INSTALL_ROOT = "/opt/electroserver"
  TARBALL = "/tmp/es-#{VERSION}.tar.gz"
  MODES = [:StandAlone, :Registry, :Gateway]
  ES_ROOT = "#{INSTALL_ROOT}/server"
  PORTS = [9898, 9899, 1935, 8989]

  class User
    NAME = 'electroserver'
    
    def initialize
      Shell.do "Creating '#{NAME}' user", "adduser --system --group --home #{INSTALL_ROOT} #{NAME}"

      FileUtils.mkdir_p INSTALL_ROOT
      FileUtils.chown NAME, NAME, INSTALL_ROOT
      FileUtils.chmod 02775, INSTALL_ROOT
    end
  end

  class Permissions
    def Permissions.update
      Shell.do "Fixing ownership", "chown -R #{User::NAME}.#{User::NAME} #{INSTALL_ROOT}"
      Shell.do "Fixing permissions", "chmod -R g+w,g+s,g+r #{INSTALL_ROOT}"
    end
  end
  
  class Installer
    attr_accessor :mode, :passphrase, :gateways, :registry

    def install
      puts "Setting up ElectroServer #{@mode} instance... "
      
      User.new
      
      Shell.do "Downloading and extracting #{DISTRIBUTION}","curl #{Shell::CURL_OPTS} #{DISTRIBUTION} | tar --strip-components 1 --directory #{INSTALL_ROOT} -xzf - #{NAMED_VERSION}/server"
      
      case @mode
      when :Gateway
        File.open("#{ES_ROOT}/config/ES4Configuration.xml", 'w') do |run|
          run.puts <<-EOF
<?xml version="1.0" encoding="UTF-8"?>
<GatewayConfiguration>
  <Name>Gateway #{EC2[:ami_launch_index] + 1}</Name>
  <PassPhrase>#{@passphrase}</PassPhrase>
  <RegistryListener>
    <Host>#{@registry}</Host>
    <Port>9090</Port>
  </RegistryListener>
</GatewayConfiguration>
EOF
        end
      when :Registry
        Derby.open("#{ES_ROOT}/db") do |derby|
          derby.puts "UPDATE REGISTRYSETTINGS SET LISTENERIP = '#{EC2[:local_ipv4]}';"
          
          (1..@gateways).each do |gateway|
            derby.puts "INSERT INTO Gateways (gatewayName, passPhrase, registryConnections) VALUES ('Gateway #{gateway}', '#{@passphrase}', 100);"
            ports.each_with_index do |port, index|
              derby.puts "INSERT INTO GATEWAYLISTENERS (GATEWAYID, HOSTNAME, PORT, PROTOCOLID) VALUES(#{gateway + 2}, '0.0.0.0', #{port}, #{index + 1});"
            end
          end
        end
      when :StandAlone
        Derby.open("#{ES_ROOT}/db") { |derby| derby.puts "UPDATE GATEWAYLISTENERS SET HOSTNAME = '0.0.0.0';" }
      end
      
      setup_service

      Permissions.update

      start

      Permissions.update

      update_motd
    end
    
    def start
      puts "Starting ElectroServer ..."
      FileUtils.ln_s "#{INSTALL_ROOT}/service", "/service/electroserver"
      sleep 5
    end

    def setup_service
      puts "Setting up service ..."

      FileUtils.cp 'bin/run.sh', ES_ROOT
      MODES.each { |mode| FileUtils.ln_s "#{ES_ROOT}/run.sh", "#{ES_ROOT}/#{mode}" }

      run_script = "#{INSTALL_ROOT}/service/run"
      FileUtils.cp_r "service", "#{INSTALL_ROOT}"
      File.open(run_script, 'w') do |run|
        run.puts <<-EOF
#!/bin/sh
dir=`pwd -P`
echo "*** starting electroserver"
exec 2>&1 envdir ./env setuidgid #{User::NAME} $dir/../server/#{@mode}
EOF
      end
      FileUtils.chmod 0770, run_script 
    end

    def update_motd
      File.open("/etc/motd.tail", "w") do |motd|
        motd.puts <<-EOF
Electrotank setup is complete.

ElectroServer #{@mode} #{VERSION} has been installed.

Enjoy!
EOF
      end
    end

  end
end

# ------

installer = ElectroServer::Installer.new

opts = OptionParser.new do |opts|
  opts.banner = "Usage:  #{File.basename($PROGRAM_NAME)} [options]"
  
  opts.separator ""
  opts.separator "Specific Options:"

  opts.on( "-m", "--mode mode", ElectroServer::MODES, "ElectroServer mode to use (#{ElectroServer::MODES.join(', ')})" ) do |mode|
    installer.mode = mode
  end
  
  opts.on( "-p", "--passphrase passphrase", "Passphrase to use for distributed mode" ) do |passphrase|
    installer.passphrase = passphrase
  end
  
  opts.on( "-g", "--gateways gateways", Integer, "Number of gateways to initialize for distributed registry" ) do |gateways|
    installer.gateways = gateways
  end
  
  opts.on( "-r", "--registry registry", String, "DNS name of registry for distributed mode" ) do |registry|
    installer.registry = registry
  end
  
  opts.separator "Common Options:"
  
  opts.on( "-h", "--help", "Show this message." ) do
    puts opts
    exit
  end  
end

opts.parse!(ARGV)

opts.abort "Must specify --mode" if installer.mode.nil?

case installer.mode
when :Registry
  opts.abort "Must specify --gateways when mode is Registry" if installer.gateways.nil?
  opts.abort "Must specify --passphrase when mode is Registry" if installer.passphrase.nil?
when :Gateway
  opts.abort "Must specify --registry when mode is Gateway" if installer.registry.nil?
  opts.abort "Must specify --passphrase when mode is Gateway" if installer.passphrase.nil?
end

installer.install
