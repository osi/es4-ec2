class Dependencies
    def Dependencies.prepareServer
        puts "Preparing server"

        File.open("/etc/apt/sources.list.d/dev-ppa.list", 'w') do |run|
        run.puts <<-EOF
            deb http://ppa.launchpad.net/amoog/amoog-devel/ubuntu jaunty main
            deb-src http://ppa.launchpad.net/amoog/amoog-devel/ubuntu jaunty main
            EOF
        end

        # Inline the keyto avoid dependency upon the keyserver
        Shell.do( "Adding daemontools patch repo key", <<-EOF
echo "-----BEGIN PGP PUBLIC KEY BLOCK-----
Version: SKS 1.0.10

mI0ESXepTAEEAMOETtlE16QMbYNzkFZL1nE8sw+LCx0JRo5EHVrAK1tUBM9R//mantklg3a8
0upa0igNTJRqn5Tj7covMBO1yctYUdpm0QhJcg9i7CsT9S5XX1bdYMi75d357myh/F3BW57c
S8tM6pqoR8DkneefJTlQnGqZL00JGs1zvktRFzUHABEBAAG0HkxhdW5jaHBhZCBQUEEgZm9y
IEFuZHJlYXMgTW9vZ4i2BBMBAgAgBQJJd6lMAhsDBgsJCAcDAgQVAggDBBYCAwECHgECF4AA
CgkQJL3WCVr+gs6KJwP+Ow60GH4NHchdqu1bIY2RQ8+8mkqkEbEFOIyV6gU8gzX7Iq/uBww5
FHi/VL2lZIUU2ZnkB9xevI3HcfOrcRnmpYjQbZMg4MWlGiKO2kWmd4mEWacM7YoRmXN8K8Qx
wEwszH2eTP6jEagZVm8IsI0zfBsaVX4F8wefJi+5mGXdSMc=
=fKMI
-----END PGP PUBLIC KEY BLOCK-----
" | apt-key add -
EOF
        )
        # apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 5AFE82CE

        Shell.do( "Update apt-get libraries", "apt-get update" )
        # Shell.do( "Upgrade all installed libraries to the latest", "apt-get upgrade -y" )
        Shell.do( "Installing software", "apt-get install -y openjdk-6-jre-headless daemontools daemontools-run svtools" )

        FileUtils.ln_s "/etc/service", "/service"
    end
end

class Shell
  CURL_OPTS = "-s -S -f -L --retry 7"

  def Shell.do(name, command, test = nil )
    test = lambda { |result| result.success? } if test.nil?

    puts name
    system command
    raise "failed : #{command} : code #{$?.exitstatus}" unless test.call($?)
  end

  def Shell.prepare_tar_args(args)
    args.map do |name, values| 
      values = [values] if not values.kind_of? Array
      values.map { |value| "--#{name.to_s.gsub('_', '-')}=#{value}" } 
    end.flatten.join( ' ' )    
  end

  def Shell.download_and_extract(tarball, options)
    options = Hash.new if options.nil?
    test = options.delete :success_test
    to_extract = options.delete :to_extract

    Shell.do "Downloading and extracting #{tarball}", "curl #{Shell::CURL_OPTS} #{tarball} | tar #{Shell::prepare_tar_args(options)} -xzf - #{to_extract}", test
  end
end

class User
  attr_accessor :name, :home
  
  def initialize(name, home)
    @name = name
    @home = home

    Shell.do "Creating '#{@name}' user", "adduser --system --group --home #{@home} #{@name}"

    FileUtils.mkdir_p @home
    FileUtils.chown @name, @name, @home
    FileUtils.chmod 02775, @home
  end

  def update_permissions
    Shell.do "Fixing ownership", "chown -R #{@name}.#{@name} #{@home}"
    Shell.do "Fixing permissions", "find #{@home} -type f -exec chmod g+r,g+w {} \\;"
    Shell.do "Fixing permissions", "find #{@home} -type d -exec chmod 02775 {} \\;"
  end
end

class Service
  def initialize(name, user)
    @name = name
    @root = user.home
    @user = user
    
    FileUtils.cp_r "service", "#{@root}"
  end
  
  def run_script=(script)
    run_script = "#{@root}/service/run"
    File.open(run_script, 'w') do |run|
      run.puts script
    end
    FileUtils.chmod 0770, run_script 
  end

  def start
    puts "Starting #{@name} ..."

    @user.update_permissions

    FileUtils.ln_s "#{@root}/service", "/service/#{@name.downcase}"
    sleep 5

    @user.update_permissions
  end
  
end

module Terracotta
  INSTALL_ROOT = "/opt/terracotta"
  DISTRIBUTION = "http://s3.amazonaws.com/TCreleases/terracotta-3.1.0.tar.gz"

  class Installer

    def install
      puts "Installing Terracotta"
      
      @user = User.new "terracotta", INSTALL_ROOT
      
      Shell.download_and_extract DISTRIBUTION, { :directory => INSTALL_ROOT }

      FileUtils.ln_s "#{INSTALL_ROOT}/terracotta-3.1.0/", "#{INSTALL_ROOT}/terracotta"
    end
    
    def setup_client
      Shell.do "Creating boostrap jar", "export JAVA_HOME=/usr/lib/jvm/java-6-openjdk && #{INSTALL_ROOT}/terracotta/bin/make-boot-jar.sh"
      Shell.do "Installing concurrent collections TIM", "export JAVA_HOME=/usr/lib/jvm/java-6-openjdk && #{INSTALL_ROOT}/terracotta/bin/tim-get.sh install tim-concurrent-collections"
      # Shell.do "Fixing startup script", "sed -i -e 1i'#!/bin/bash' -e 1d /opt/terracotta/terracotta/bin/dso-java.sh"
    end
    
    def setup_server
      puts "Configuring Terracotta Server"
      
      configure
      
      service = Service.new "Terracotta", @user
      service.start
    end
    
    private 
    
    def configure
      Shell.do "Installing libxslt-ruby", "apt-get install -y libxslt-ruby"
      
      require 'xml/libxslt'
      
      xslt = XML::XSLT.new
      xslt.xml = "tc-config.xml"
      xslt.xsl = "configure.xslt"
      xslt.parameters = { "hostname" => EC2[:local_hostname], "id" => EC2[:instance_id] }
      
      xslt.save "#{INSTALL_ROOT}/tc-config.xml"
    end
  end
end
