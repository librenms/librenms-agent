#!/bin/sh

# wlNoiseFloor.sh
# Returns wlNoiseFloor, in dBm
# Arguments: targeted interface

# Check number of arguments
if [ $# -ne 1 ]; then
	/bin/echo "Usage: wlNoiseFloor.sh interface"
	/bin/echo "Missing targeted interface, exiting."
	exit 1
fi

# Use awk to find the "[in use]" line, set a flag, and then print the very next "noise:" value it sees.
# This avoids using 'grep -A' which can be unreliable in embedded router environments.
noise=$(iw dev "$1" survey dump 2>/dev/null | awk '/\[in use\]/{flag=1} flag && /noise:/{print $2; exit}')

# Return snmp result
/bin/echo "$noise"
