#!/bin/bash

mkdir data

while true ; do
	.jitb-gatherer.pl >> ./data/jitb-gather.log 2>&1
	sleep 5
done &

while true ; do
	./jitb-exporter.pl >> ./data/jitb-exporter.log 2>&1
	sleep 5
done &
