#!/bin/sh

# snmpd-config-generator.sh
# Generates SNMP extend entries for all wireless interfaces dynamically
# Usage: Run this script to generate UCI config commands for /etc/config/snmpd

SCRIPT_DIR="/etc/librenms"
INTERFACES_FILE="$SCRIPT_DIR/wlInterfaces.txt"

# Ensure wlInterfaces.txt exists
if [ ! -f "$INTERFACES_FILE" ]; then
	echo "Generating $INTERFACES_FILE..."
	$SCRIPT_DIR/wlClients.sh >/dev/null 2>&1
fi

# Read interfaces
if [ ! -f "$INTERFACES_FILE" ]; then
	echo "Error: Could not find or generate $INTERFACES_FILE"
	exit 1
fi

# Generate config for each interface
cat "$INTERFACES_FILE" | while IFS=',' read -r iface ssid; do
	[ -z "$iface" ] && continue
	
	# Sanitize interface name for use in UCI names (replace - with _)
	safe_name=$(echo "$iface" | tr '-' '_')
	
	echo ""
	echo "# Interface: $iface ($ssid)"
	echo ""
	
	# Clients
	echo "config extend"
	echo "        option name 'clients-$iface'"
	echo "        option prog '$SCRIPT_DIR/wlClients.sh'"
	echo "        option args '$iface'"
	echo ""
	
	# Frequency
	echo "config extend"
	echo "        option name 'frequency-$iface'"
	echo "        option prog '$SCRIPT_DIR/wlFrequency.sh'"
	echo "        option args '$iface'"
	echo ""
	
	# Rate TX (min, avg, max)
	for stat in min avg max; do
		echo "config extend"
		echo "        option name 'rate-tx-$iface-$stat'"
		echo "        option prog '$SCRIPT_DIR/wlRate.sh'"
		echo "        option args '$iface tx $stat'"
		echo ""
	done
	
	# Rate RX (min, avg, max)
	for stat in min avg max; do
		echo "config extend"
		echo "        option name 'rate-rx-$iface-$stat'"
		echo "        option prog '$SCRIPT_DIR/wlRate.sh'"
		echo "        option args '$iface rx $stat'"
		echo ""
	done
	
	# Noise floor
	echo "config extend"
	echo "        option name 'noise-floor-$iface'"
	echo "        option prog '$SCRIPT_DIR/wlNoiseFloor.sh'"
	echo "        option args '$iface'"
	echo ""
	
	# SNR (min, avg, max)
	for stat in min avg max; do
		echo "config extend"
		echo "        option name 'snr-$iface-$stat'"
		echo "        option prog '$SCRIPT_DIR/wlSNR.sh'"
		echo "        option args '$iface $stat'"
		echo ""
	done
done

# Generate thermal sensor config using pass (LM-SENSORS-MIB)
echo ""
echo "# Thermal Sensors (LM-SENSORS-MIB via pass)"
echo ""

echo "config pass"
echo "        option name 'lm-sensors'"
echo "        option prog '$SCRIPT_DIR/lm-sensors-pass.sh'"
echo "        option miboid '.1.3.6.1.4.1.2021.13.16.2.1'"
echo ""
