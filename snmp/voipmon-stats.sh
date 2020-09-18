#!/bin/bash
# Author: Sharad Kumar <skumar@securevoip.io>

used_memory=$(ps -C voipmonitor -o rsz | awk 'FNR==2 {print}')
cpu_load=$(ps -C voipmonitor -o %cpu | awk 'FNR==2 {print}')

pid=$(pidof voipmonitor)
total_files=$(ls -l /proc/${pid}/fd | wc -l)

echo "Used Memory="$used_memory
echo "CPU Load="$cpu_load
echo "Open files="$total_files
exit
