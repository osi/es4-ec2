# require 'rubygems'
require 'right_aws'

module ElectroAws

  class Controller
    attr_accessor :access_key, :secret_key, :ami_id, :mode, :groups, :gateways, :keypair, :debug, :instance_type, :cluster_nodes
    attr_reader :ec2, :passphrase

    def initialize
      @ami_id = nil
      @groups = []
      @gateways = 1
      @passphrase = (0...50).map{ ('a'..'z').to_a[rand(26)] }.join
      @instance_type = 'c1.medium'
      @cluster_nodes = nil
    end
    
    def cluster_nodes
      if @cluster_nodes.nil?
        if @mode == :Cluster
          2
        else
          1
        end
      else
        @cluster_nodes
      end
    end
    
    def ami_id
      if @ami_id.nil?
        if ['m1.small', 'c1.medium'].include?(@instance_type)
          "ami-ed46a784"
        else
          "ami-5b46a732"
        end
      else
        @ami_id
      end
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
      @ec2.run_instances ami_id, count, count, @groups, @keypair, init_script, nil, @instance_type
    end
  end
  
  class Instance
    def initialize(aws)
      @aws = aws
    end
    
    def run_and_wait_for_start(count, init_script)
      instance_ids = @aws.run_instances(count, init_script).collect { |instance| instance[:aws_instance_id] }
      wait_for_start instance_ids
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
        puts "    - #{descriptor[:aws_instance_id]} - #{descriptor[:dns_name]} - #{descriptor[:private_dns_name]}"
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
      run_and_wait_for_start @aws.gateways, es4_init_script(args)
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
      run_and_wait_for_start 1, es4_init_script
    end
  end
  
  class Jet < Instance
    include Clustered
    
    def provision
      if @terracotta_servers.nil?
        puts "Provisioning Jet instance ..."
        run_and_wait_for_start 1, es4_init_script
      else
        puts "Provisioning Jet #{@aws.cluster_nodes} instance(s) ..."
        run_and_wait_for_start @aws.cluster_nodes, es4_init_script
      end
    end
  end
  
  class LoadTester < Instance
    
    def provision
      puts "Provisioning #{@aws.cluster_nodes} load tester instance(s) ..."
      
      script = %Q{
#!/bin/sh

apt-get update
apt-get install -y openjdk-6-jre-headless

mkdir -p /opt/setup

cd /opt/setup
curl -s -S -f -L --retry 7 http://dev.electrotank.com/ec2/setup.tar.gz | tar xzof - 

./fetchec2metadata.rb

mkdir -p /opt/loadtest

cd /opt/loadtest
curl -s -S -f -L --retry 7 http://dev.electrotank.com/ec2/es4-loadtester.tar.gz  | tar xzof - 

sed -i -e '/^NUMBER_OF_SERVERS=/s/1/#{@aws.cluster_nodes}/' run_test.sh
      }
      
      run_and_wait_for_start @aws.cluster_nodes, script
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
      
      jet = Jet.new @aws
      jet.terracotta_servers = [tc.dns_name]
      jet.provision
    end
  end
end

