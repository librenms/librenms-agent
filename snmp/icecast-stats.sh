#!/bin/bash
# Author: Sharad Kumar <skumar@securevoip.io>

used_memory=$(ps -U icecast -o rsz | awk 'FNR==2{print}')
cpu_load=$(ps -U icecast -o %cpu | awk 'FNR==2{print}')

pid=$(pidof icecast)
total_files=$(find /proc/"${pid}"/fd | wc -l)

echo "Used Memory=""$used_memory"
echo "CPU Load=""$cpu_load"
echo "Open files=""$total_files"

exit
