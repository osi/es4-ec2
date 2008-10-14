#!/usr/bin/env ruby
#
# Script to setup ElectroServer 4 on Amazon's EC2
#
# by peter royal - peter@electrotank.com
#

require 'fileutils'
require "optparse"
require '/var/spool/ec2/meta-data'
require '../common'

class Derby
  TARBALL = 'http://archive.apache.org/dist/db/derby/db-derby-10.2.2.0/db-derby-10.2.2.0-bin.tar.gz'
  
  def Derby.open(database, &actions)
    dir = '/tmp/derby'
    FileUtils.mkdir dir

    Shell.download_and_extract TARBALL, { :strip_components => 1, :directory => dir }

    IO.popen("java -cp '#{dir}/lib/derbytools.jar:#{dir}/lib/derby.jar' org.apache.derby.tools.ij", "w") do |derby|
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
  PATCH = "http://dev.electrotank.com/ec2/patches/es-#{VERSION}.tar.gz"
  INSTALL_ROOT = "/opt/electroserver"
  TARBALL = "/tmp/es-#{VERSION}.tar.gz"
  MODES = [:StandAlone, :Registry, :Gateway]
  ES_ROOT = "#{INSTALL_ROOT}/server"
  PORTS = [9898, 9899, 1935, 8989]

  class Installer
    attr_accessor :mode, :passphrase, :gateways, :registry, :terracotta_servers

    def install
      puts "Setting up ElectroServer #{@mode} instance... "
      
      user = User.new 'electroserver', INSTALL_ROOT
      
      download
      
      case @mode
      when :Gateway
        File.open("#{ES_ROOT}/config/ES4Configuration.xml", 'w') do |run|
          run.puts <<-EOF
<?xml version="1.0" encoding="UTF-8"?>
<GatewayConfiguration>
  <Name>Gateway #{EC2[:ami_launch_index].to_i + 1}</Name>
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
          derby.puts "DELETE FROM GATEWAYLISTENERS;"
          derby.puts "DELETE FROM Gateways;"
          
          (1..@gateways).each do |gateway|
            derby.puts "INSERT INTO Gateways (gatewayName, passPhrase, registryConnections) VALUES ('Gateway #{gateway}', '#{@passphrase}', 100);"
            PORTS.each_with_index do |port, index|
              derby.puts "INSERT INTO GATEWAYLISTENERS (GATEWAYID, HOSTNAME, PORT, PROTOCOLID) VALUES(#{gateway + 2}, '0.0.0.0', #{port}, #{index + 1});"
            end
          end
        end
      when :StandAlone
        Derby.open("#{ES_ROOT}/db") { |derby| derby.puts "UPDATE GATEWAYLISTENERS SET HOSTNAME = '0.0.0.0';" }
      end
      
      service = setup_service(user)
      
      if not @terracotta_servers.nil?
        tc = Terracotta::Installer.new
        tc.install
        tc.setup_client
        
        File.open("#{user.home}/service/env/TC_CONFIG_PATH", 'w') do |run|
          run.puts(@terracotta_servers.map { |server| "#{server}:9510" }.join(","))
        end
      end
      
      service.start

      update_motd
    end
    
    def download
      Shell.download_and_extract DISTRIBUTION, { :strip_components => 1, :directory => INSTALL_ROOT, :to_extract => "#{NAMED_VERSION}/server"}
      
      Shell.download_and_extract PATCH, { :directory => "#{INSTALL_ROOT}/server/lib", :success_test => lambda { |result| result.success? or result.exitstatus == 22 } }
    end
    
    def setup_service(user)
      puts "Setting up service ..."

      FileUtils.cp 'bin/run.sh', ES_ROOT
      MODES.each { |mode| FileUtils.ln_s "#{ES_ROOT}/run.sh", "#{ES_ROOT}/#{mode}" }

      service = Service.new "ElectroServer", user
      service.run_script = <<-EOF
#!/bin/sh
dir=`pwd -P`
echo "*** starting electroserver"
exec 2>&1 envdir ./env setuidgid #{user.name} $dir/../server/#{@mode}
EOF
      service
    end

    def update_motd
      File.open("/etc/motd.tail", "a") do |motd|
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
  
  opts.on( "-t", "--terracotta-servers servers", Array, "List of Terracotta servers to address" ) do |terracotta_servers|
    installer.terracotta_servers = terracotta_servers
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
