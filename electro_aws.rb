# require 'rubygems'
require 'right_aws'

module ElectroAws

  class Controller
    attr_accessor :access_key, :secret_key, :ami_id, :mode, :groups, :gateways, :keypair, :debug
    attr_reader :ec2, :passphrase

    def initialize
      @ami_id = "ami-4eda3e27"
      @groups = []
      @gateways = 1
      @passphrase = (0...50).map{ ('a'..'z').to_a[rand(26)] }.join
    end

    def provision
      logger = Logger.new STDOUT
      logger.level = Logger::WARN unless @debug
      @ec2 = RightAws::Ec2.new @access_key, @secret_key, :logger => logger

      case @mode
      when :StandAlone
        instance = StandAlone.new self
      when :Jet
        instance = Jet.new self
      when :Distributed 
        instance = Distributed.new self
      when :Cluster
        instance = Cluster.new self
      when :LoadTester
        instance = LoadTester.new self
      else
        raise "Unknown mode: #{@mode}"
      end
      
      instance.provision
    end
    
    def run_instances(count, init_script)
      @ec2.run_instances @ami_id, count, count, @groups, @keypair, init_script, nil, 'c1.medium'
    end
  end
  
  class Instance
    def initialize(aws)
      @aws = aws
    end

    def wait_for_start(*instance_ids)
      descriptors = nil

      instance_ids.flatten!

      puts " - waiting for #{self.type} -> #{instance_ids.join(', ')} to start .. "

      loop do
        descriptors = @aws.ec2.describe_instances(instance_ids)
        break if descriptors.all? { |descriptor| 'running' == descriptor[:aws_state] }
        if descriptors.any? { |descriptor| 'terminated' == descriptor[:aws_state] }
          raise "INSTANCE FAILED TO START"
        end
        sleep 5
      end

      puts " - startup complete:"
      descriptors.each do |descriptor|
        puts "    - #{descriptor[:aws_instance_id]} - #{descriptor[:dns_name]}"
      end

      descriptors
    end

    def console_output(instance_id)
      @aws.ec2.get_console_output(instance_id)[:aws_output]
    end
    
    def es4_init_script(args = "")
      args << " -t #{@terracotta_servers.join(',')}" if not @terracotta_servers.nil?
      generate_init_script "cd es4 && ./setup.rb -m #{self.type} #{args} && cd .."
    end

    def generate_init_script(*modules)
      modules.flatten!
      
      return %Q{
#!/bin/sh

cat > /var/run/motd <<EOF
-------
WARNING
-------

Electrotank setup is still in progress
EOF

rm /etc/motd.tail
touch /etc/motd.tail

mkdir -p /opt/setup

cd /opt/setup
curl -s -S -f -L --retry 7 http://dev.electrotank.com/ec2/setup.tar.gz | tar xzof - 

./fetchec2metadata.rb

#{modules.join("\n")}

cp /etc/motd.tail /var/run/motd

# rm -rf /opt/setup      
      }
    end
    
    def type
      self.class.to_s.split('::').last
    end
  end
  
  module Clustered
    
    def terracotta_servers=(servers)
      @terracotta_servers = servers
    end
    
  end

  class Distributed
    include Clustered
    
    def initialize(aws)
      @aws = aws
    end
    
    def provision
      puts "Provisioning Distributed instance ..."
      
      registry = Registry.new @aws
      registry.terracotta_servers = @terracotta_servers
      registry.provision

      gateway = Gateway.new @aws, registry.dns_name
      gateway.provision
    end
  end
  
  class Gateway < Instance
    def initialize(aws, registry_name)
      super aws
      @registry_name = registry_name
    end
    
    def provision
      puts " - provisioning #{@aws.gateways} gateway(s) ..."
      
      args = "-p #{@aws.passphrase} -r #{@registry_name}"
      instance_ids = @aws.run_instances(@aws.gateways, es4_init_script(args)).collect { |instance| instance[:aws_instance_id] }
      wait_for_start instance_ids
    end
  end
  
  class Registry < Instance
    include Clustered
    
    attr_reader :dns_name
    
    def provision
      puts " - provisioning registry ..."
      
      args = "-g #{@aws.gateways} -p #{@aws.passphrase}"
      instance_id = @aws.run_instances(1, es4_init_script(args))[0][:aws_instance_id]
      
      @dns_name = wait_for_start(instance_id)[0][:private_dns_name]
    end
  end
  
  class StandAlone < Instance
    include Clustered
    
    def provision
      puts "Provisioning Standalone instance ..."
      wait_for_start @aws.run_instances(1, es4_init_script)[0][:aws_instance_id]
    end
  end
  
  class Jet < Instance
    include Clustered
    
    def provision
      puts "Provisioning Jet instance ..."
      wait_for_start @aws.run_instances(1, es4_init_script)[0][:aws_instance_id]
    end
  end
  
  class LoadTester < Instance
    
    def provision
      puts "Provisioning load tester instance ..."
      
      script = %Q{
#!/bin/sh

mkdir -p /opt/loadtest

cd /opt/loadtest
curl -s -S -f -L --retry 7 http://dev.electrotank.com/ec2/es4-loadtester.tar.gz  | tar xzof - 
      }
      
      wait_for_start @aws.run_instances(1, script)[0][:aws_instance_id]
    end
  end
  
  class Terracotta < Instance
    attr_reader :dns_name
    
    def provision
      puts " - provisioning Terracotta server ..."

      args = "cd terracotta && ./setup.rb && cd .."
      instance_id = @aws.run_instances(1, generate_init_script(args))[0][:aws_instance_id]
      
      @dns_name = wait_for_start(instance_id)[0][:private_dns_name]
    end
  end
  
  class Cluster
    def initialize(aws)
      @aws = aws
    end
    
    def provision
      puts "Provisioning Clustered instance ..."
      
      tc = Terracotta.new @aws
      tc.provision
      
      standalone = StandAlone.new @aws
      standalone.terracotta_servers = [tc.dns_name]
      standalone.provision
      
      distributed = Distributed.new @aws
      distributed.terracotta_servers = [tc.dns_name]
      distributed.provision
    end
  end
end
