#!/bin/bash

used_memory=$(ps -U icecast -o rsz | awk 'FNR==2 {print}')
cpu_load=$(ps -U icecast -o %cpu | awk 'FNR==2 {print}')

echo "<<<icecast>>>"
echo "Used Memory="$used_memory
echo "CPU Load="$cpu_load
exit
