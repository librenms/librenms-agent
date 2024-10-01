#!/bin/sh

# wlFrequency.sh
# Returns wlFrequency, in MHz (not channel number)
# Arguments: targed interface

# Check number of arguments
if [ $# -ne 1 ]; then
	/bin/echo "Usage: wlFrequency.sh interface"
	/bin/echo "Missing targeted interface, exiting."
	exit 1
fi

# Extract frequency
frequency=$(/usr/sbin/iw dev "$1" info 2>/dev/null | /bin/grep channel | /usr/bin/cut -f 2- -s -d" " | /usr/bin/cut -f 2- -s -d"(" | /usr/bin/cut -f 1 -s -d" ")

# Return snmp result
/bin/echo "$frequency"
