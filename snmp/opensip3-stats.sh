#!/bin/bash
# Author: Sharad Kumar <skumar@securevoip.io>
# This script is for OpenSIPS 3.X + version

total_memory=$(opensips-cli -x mi  get_statistics total_size | awk '/shmem:total_size/ { gsub(/[",]/,""); print "Total Memory="  $2}')
used_memory=$(opensips-cli -x mi  get_statistics real_used_size | awk '/shmem:real_used_size/ { gsub(/[",]/,""); print "Used Memory=" $2}')
free_memory=$(opensips-cli -x mi  get_statistics free_size | awk '/shmem:free_size/ { gsub(/[",]/,""); print "Free Memory=" $2}')
load_average=$(ps -C opensips -o %cpu | awk '{sum += $1} END {print "Load Average=" sum}')
total_files=$(lsof -c opensips | wc -l)


echo "$total_memory"
echo "$used_memory"
echo "$free_memory"
echo "$load_average"
echo "Open files=""$total_files"

exit

