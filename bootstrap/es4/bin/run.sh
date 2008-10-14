#!/bin/sh

dir=`dirname $0`
self=`basename $0`
java_cmd=java

if test -n "$TC_CONFIG_PATH"; then
    java_cmd=/opt/terracotta/terracotta/bin/dso-java.sh
fi

cd $dir

exec $java_cmd \
     -XX:+HeapDumpOnOutOfMemoryError \
     -XX:HeapDumpPath=../ \
     -Djava.awt.headless=true \
     -jar lib/ElectroServer4-bootstrap.jar \
     -mode $self \
     -config config/ES4Configuration.xml
