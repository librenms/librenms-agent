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

# Calculate min/avg/max rates
min_rate=$(/bin/echo "$ratelist" | awk 'NR==1{min=$1} $1<min{min=$1} END{printf "%d\n", (min=="" ? 0 : min)}')
avg_rate=$(/bin/echo "$ratelist" | awk '{sum+=$1; n++} END{printf "%d\n", (n>0 ? sum/n : 0)}')
max_rate=$(/bin/echo "$ratelist" | awk '$1>max{max=$1} END{printf "%d\n", (max=="" ? 0 : max)}')

case "$3" in
  min) echo "$min_rate" ;;
  avg) echo "$avg_rate" ;;
  max) echo "$max_rate" ;;
  *)   echo "0" ;;
esac

# Second line for nsExtendOutputFull compatibility
echo "# wlRate $1 $2 $3"
exit 0
