#!/bin/sh

# wlClients.sh
# Counts connected (associated) Wi-Fi devices
# Arguments: targed interface. Assumes all interfaces if no argument

# Check number of arguments
if [ $# -gt 1 ]; then
	/bin/echo "Usage: wlClients.sh interface"
	/bin/echo "Too many command line arguments, exiting."
	exit 1
fi

# Get path to this script
scriptdir=$(dirname "$(readlink -f -- "$0")")

# Get interface list. Set target, which is name returned for interface
if [ "$1" ]; then
	interfaces=$1
else
	interfaces=$(cat "$scriptdir"/wlInterfaces.txt | cut -f 1 -d",")
fi

# Count associated devices
count=0
for interface in $interfaces
do
	new=$(/usr/sbin/iw dev "$interface" station dump | /bin/grep Station | /usr/bin/cut -f 2 -s -d" " | /usr/bin/wc -l)
  	count=$(( $count + $new ))
done

# Return snmp result
/bin/echo $count
