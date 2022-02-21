#!/bin/bash
# Author: Sharad Kumar <skumar@securevoip.io>
# This script is for OpenSIPS 3.X + version

statistics=$(curl -s --header "Content-Type: application/json" -X POST -i http://127.0.0.1:8888/json -d '{"jsonrpc":"2.0","id":1,"method":"get_statistics", "params":[["all"]]}')
total_memory=$(echo "$statistics" | grep -Po '"shmem:total_size":(\d+)' |awk -F':' '{print $3}')
used_memory=$(echo "$statistics" | grep -Po '"shmem:used_size":(\d+)' |awk -F':' '{print $3}')
free_memory=$(echo "$statistics" | grep -Po '"shmem:free_size":(\d+)' |awk -F':' '{print $3}')
load_average=$(ps -C opensips -o %cpu | awk '{sum += $1} END {print "Load Average=" sum}')
total_files=$(lsof -c opensips | wc -l)


echo "$total_memory"
echo "$used_memory"
echo "$free_memory"
echo "$load_average"
echo "Open files=""$total_files"

exit

