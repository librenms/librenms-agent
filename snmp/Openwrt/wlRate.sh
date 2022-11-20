#!/bin/sh

# wlRate.sh
# Returns wlRate, bit rate in Mbit/s
# Arguments:
#  $1: targeted interface
#  $2: direction (tx or rx)
#  $3: desired result (sum, avg, min, max)

# Check number of arguments
if [ $# -ne 3 ]; then
	/bin/echo "Usage: wlRate.sh interface direction result"
	/bin/echo "Incorrect script usage, exiting."
	exit 1
fi

# Calculate result. Sum just for debug, and have to return integer
# => If not integer (e.g. 2.67e+07), LibreNMS will drop the exponent (result, 2.67 bits/sec!)
ratelist=$(/usr/sbin/iw dev "$1" station dump 2>/dev/null | /bin/grep "$2 bitrate" | /usr/bin/cut -f 2 -s -d" ")
result=0
if [ "$3" = "sum" ]; then
  result=$(/bin/echo "$ratelist" | /usr/bin/awk -F ':' '{sum += $2} END {printf "%d\n", 1000000*sum}')
elif [ "$3" = "avg" ]; then
  result=$(/bin/echo "$ratelist" | /usr/bin/awk -F ':' '{sum += $2} END {printf "%d\n", 1000000*sum/NR}')
elif [ "$3" = "min" ]; then
  result=$(/bin/echo "$ratelist" | /usr/bin/awk -F ':' 'NR == 1 || $2 < min {min = $2} END {printf "%d\n", 1000000*min}')
elif [ "$3" = "max" ]; then
  result=$(/bin/echo "$ratelist" | /usr/bin/awk -F ':' 'NR == 1 || $2 > max {max = $2} END {printf "%d\n", 1000000*max}')
fi

# Return snmp result
echo "$result"
