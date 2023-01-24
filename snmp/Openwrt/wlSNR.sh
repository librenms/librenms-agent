#!/bin/sh

# wlSNR.sh
# Returns wlSNR, Signal-to-Noise ratio in dB
# Arguments:
#  $1: targeted interface
#  $2: desired result (sum, avg, min, max)

# Check number of arguments
if [ $# -ne 2 ]; then
	/bin/echo "Usage: wlSNR.sh interface result"
	/bin/echo "Incorrect script usage, exiting."
	exit 1
fi

# Calculate result. Sum just for debug, and return integer (safest / easiest)
snrlist=$(/usr/bin/iwinfo "$1" assoclist 2>/dev/null | /usr/bin/cut -s -d "/" -f 2 | /usr/bin/cut -s -d "(" -f 2 | /usr/bin/cut -s -d " " -f 2 | /usr/bin/cut -s -d ")" -f 1)
if [ "$2" = "sum" ]; then
  result=$(/bin/echo "$snrlist" | /usr/bin/awk -F ':' '{sum += $1} END {printf "%d\n", sum}')
elif [ "$2" = "avg" ]; then
  result=$(/bin/echo "$snrlist" | /usr/bin/awk -F ':' '{sum += $1} END {printf "%d\n", sum/NR}')
elif [ "$2" = "min" ]; then
  result=$(/bin/echo "$snrlist" | /usr/bin/awk -F ':' 'NR == 1 || $1 < min {min = $1} END {printf "%d\n", min}')
elif [ "$2" = "max" ]; then
  result=$(/bin/echo "$snrlist" | /usr/bin/awk -F ':' 'NR == 1 || $1 > max {max = $1} END {printf "%d\n", max}')
fi

# Return snmp result
echo "$result"
