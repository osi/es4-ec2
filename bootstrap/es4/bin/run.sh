#!/bin/sh

dir=`dirname $0`
self=`basename $0`

cd $dir

exec java \
     -XX:+HeapDumpOnOutOfMemoryError \
     -XX:HeapDumpPath=../ \
     -Djava.awt.headless=true \
     -jar lib/ElectroServer4-bootstrap.jar \
     -mode $self \
     -config config/ES4Configuration.xml
