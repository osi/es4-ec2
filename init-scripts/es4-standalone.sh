#!/bin/sh

service='es4'

# Below is boilerplate. Do not modify below this line
# ----------------------------------------------------------
# TODO - think about emitting this from a PHP script or such

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

curl -s -S -f -L --retry 7 http://dev.electrotank.com/ec2/$service.tar.gz | tar xzf - 

cd $service
./setup.rb

# rm -rf /opt/setup