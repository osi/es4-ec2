require 'rubygems'
require 'right_aws'

module ElectroAws

  class Controller
    attr_accessor :access_key, :secret_key, :ami_id, :mode, :groups, :gateways, :keypair
    attr_reader :ec2

    def initialize
      @ami_id = "ami-4eda3e27"
      @mode = :StandAlone
      @groups = []
      @gateways = 1
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
    
    def wait_for_start(instance_id)
      state = nil
      descriptor = nil

      while state != 'running'
        descriptor = @aws.ec2.describe_instances([instance_id])[0]
        state = descriptor[:aws_state]
        puts " .. waiting #{instance_id} for instance to start .. "
        sleep 5
      end
      
      puts "#{descriptor[:dns_name]} is running"

      descriptor
    end
    
    def console_output(instance_id)
      @aws.ec2.get_console_output(instance_id)[:aws_output]
    end
  end

  class StandAlone < Instance
    def provision
      instance = @aws.run_instances(1, generate_init_script)[0]
      instance_id = instance[:aws_instance_id]
      
      wait_for_start instance_id
    end
    
    private
    
    def generate_init_script
      return %q{
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
./setup.rb -m StandAlone

# rm -rf /opt/setup      
      }
    end
  end
  
end

