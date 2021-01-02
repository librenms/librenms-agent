#!/bin/bash
# Author: Sharad Kumar <skumar@securevoip.io>
# This script is for OpenSIPS 2.X + version

total_memory=$(opensipsctl fifo get_statistics total_size | awk '{print "Total Memory=" $2}')
used_memory=$(opensipsctl fifo get_statistics real_used_size | awk '{print "Used Memory=" $2}')
free_memory=$(opensipsctl fifo get_statistics free_size | awk '{print "Free Memory=" $2}')
load_average=$(ps -C opensips -o %cpu | awk '{sum += $1} END {print "Load Average=" sum}')
total_files=$(lsof -c opensips | wc -l)


echo $total_memory
echo $used_memory
echo $free_memory
echo $load_average
echo "Open files="$total_files

exit
