#!/bin/bash

mkdir -p /t

while true ; do
	./jitb-gatherer.pl >> /t/jitb-gather.log 2>&1
	sleep 5
done &

while true ; do
	./jitb-exporter.pl >> /t/jitb-exporter.log 2>&1
	sleep 5
done &
