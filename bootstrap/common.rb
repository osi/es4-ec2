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
  DISTRIBUTION = "http://s3.amazonaws.com/TCreleases/terracotta-generic-2.7.0.tar.gz"

  class Installer

    def install
      puts "Installing Terracotta"
      
      @user = User.new "terracotta", INSTALL_ROOT
      
      Shell.download_and_extract DISTRIBUTION, { :directory => INSTALL_ROOT }

      FileUtils.ln_s "#{INSTALL_ROOT}/terracotta-2.7.0/", "#{INSTALL_ROOT}/terracotta"
    end
    
    def setup_client
      Shell.do "Creating boostrap jar", "export JAVA_HOME=/usr/lib/jvm/java-6-sun && #{INSTALL_ROOT}/terracotta/bin/make-boot-jar.sh"
      Shell.do "Fixing startup script", "sed -i -e 1i'#!/bin/bash' -e 1d /opt/terracotta/terracotta/bin/dso-java.sh"
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
