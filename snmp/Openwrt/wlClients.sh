#!/bin/sh

# wlClients.sh
# Counts connected (associated) Wi-Fi devices
# Arguments: target interface. Assumes all interfaces if no argument
# Auto-generates wlInterfaces.txt if it doesn't exist

# Get path to this script (ash-compatible)
scriptdir="$(cd "$(dirname "$0")" && pwd)"
interfaces_file="$scriptdir/wlInterfaces.txt"

# Function to auto-detect and generate wlInterfaces.txt
generate_interfaces_file() {
	local tmpfile="$interfaces_file.tmp"
	
	# Find all wireless interfaces that are actually in use
	for dev in /sys/class/net/*; do
		iface=$(basename "$dev")
		
		# Skip known non-client interfaces
		case "$iface" in
			mld*|wifi*|phy*|wlan-*|mon.*) 
				continue 
				;;
		esac
		
		# Check if it's a wireless interface
		if [ -d "$dev/wireless" ] || [ -d "$dev/phy80211" ]; then
			# Try to get SSID using iw first
			ssid=$(/usr/sbin/iw dev "$iface" info 2>/dev/null | /bin/grep ssid | /usr/bin/cut -f 2 -s -d" " | /usr/bin/tr -d '\n')
			
			# If no SSID from iw, try iwinfo
			if [ -z "$ssid" ]; then
				ssid=$(/usr/bin/iwinfo "$iface" info 2>/dev/null | /bin/grep "ESSID" | /usr/bin/cut -d'"' -f2)
			fi
			
			# Skip interfaces without SSID (not active AP/client interfaces)
			[ -z "$ssid" ] && continue
			
			# Skip interfaces with "unknown" SSID
			[ "$ssid" = "unknown" ] && continue
			
			# Check if interface is UP
			if ! /sbin/ip link show "$iface" 2>/dev/null | /bin/grep -q "UP"; then
				continue
			fi
			
			echo "$iface,$ssid" >> "$tmpfile"
		fi
	done
	
	# Only replace if we found interfaces
	if [ -s "$tmpfile" ]; then
		mv "$tmpfile" "$interfaces_file"
		return 0
	else
		rm -f "$tmpfile"
		return 1
	fi
}

# Check if wlInterfaces.txt exists, generate if not
if [ ! -f "$interfaces_file" ]; then
	generate_interfaces_file
	if [ $? -ne 0 ]; then
		/bin/echo "Error: Could not generate $interfaces_file and file does not exist"
		exit 1
	fi
fi

# Check number of arguments
if [ $# -gt 1 ]; then
	/bin/echo "Usage: wlClients.sh [interface]"
	/bin/echo "Too many command line arguments, exiting."
	exit 1
fi

# Get interface list. Set target, which is name returned for interface
if [ "$1" ]; then
	interfaces=$1
else
	interfaces=$(cat "$interfaces_file" | cut -f 1 -d",")
fi

# Count associated devices
count=0
for interface in $interfaces
do
	new=$(/usr/sbin/iw dev "$interface" station dump 2>/dev/null | /bin/grep Station | /usr/bin/cut -f 2 -s -d" " | /usr/bin/wc -l)
	count=$(( count + new ))
done

# Return snmp result
/bin/echo $count
