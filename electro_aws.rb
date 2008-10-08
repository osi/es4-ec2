require 'rubygems'
require 'right_aws'

module ElectroAws

  class Controller
    attr_accessor :access_key, :secret_key, :ami_id, :mode, :groups, :gateways, :keypair
    attr_reader :ec2, :passphrase

    def initialize
      @ami_id = "ami-4eda3e27"
      @groups = []
      @gateways = 1
      @passphrase = (0...50).map{ ('a'..'z').to_a[rand(26)] }.join
    end

    def provision
      @ec2 = RightAws::Ec2.new @access_key, @secret_key

      case @mode
      when :StandAlone
        instance = StandAlone.new self
      when :Distributed 
        instance = Distributed.new self
      else
        raise "Unknown mode: #{@mode}"
      end
      
      instance.provision
    end
    
    def run_instances(count, init_script)
      @ec2.run_instances @ami_id, count, count, @groups, @keypair, init_script
    end
  end
  
  class Instance
    def initialize(aws)
      @aws = aws
    end

    def wait_for_start(*instance_ids)
      descriptors = nil

      loop do
        descriptors = @aws.ec2.describe_instances(instance_ids)
        break if descriptors.all? { |descriptor| 'running' == descriptor[:aws_state] }
        puts "waiting for #{self.type} / #{instance_ids} for instance(s) to start .. "
        sleep 5
      end

      puts "#{self.type}"
      descriptors.each do |descriptor|
        puts "  - #{descriptor[:aws_instance_id]} - #{descriptor[:dns_name]}"
      end

      descriptors
    end

    def console_output(instance_id)
      @aws.ec2.get_console_output(instance_id)[:aws_output]
    end

    def generate_init_script(args = nil)
      return %Q{
#!/bin/sh

cat > /etc/motd.tail <<EOF
-------
WARNING
-------

Electrotank setup is still in progress
EOF

mkdir -p /opt/setup

cd /opt/setup
curl -s -S -f -L --retry 7 http://dev.electrotank.com/ec2/setup.tar.gz | tar xzf - 

./fetchec2metadata.rb

curl -s -S -f -L --retry 7 http://dev.electrotank.com/ec2/es4.tar.gz | tar xzf - 

cd es4
./setup.rb -m #{self.type} #{args}

# rm -rf /opt/setup      
      }
    end
    
    def type
      self.class.to_s.split('::').last
    end
  end

  class Distributed
    def initialize(aws)
      @aws = aws
    end
    
    def provision
      registry = Registry.new @aws
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
      args = "-p #{@aws.passphrase} -r #{@registry_name}"
      instance_ids = @aws.run_instances(@aws.gateways, generate_init_script(args)).collect { |instance| instance[:aws_instance_id] }
    end
  end
  
  class Registry < Instance
    attr_reader :dns_name
    
    def provision
      args = "-g #{@aws.gateways} -p #{@aws.passphrase}"
      instance_id = @aws.run_instances(1, generate_init_script(args))[0][:aws_instance_id]
      
      @dns_name = wait_for_start(instance_id)[0][:private_dns_name]
    end
  end
  
  class StandAlone < Instance
    def provision
      wait_for_start @aws.run_instances(1, generate_init_script)[0][:aws_instance_id]
    end
  end
end

