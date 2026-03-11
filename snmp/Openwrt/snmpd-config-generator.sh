#!/bin/sh
set -eu
# snmpd-config-generator.sh - LibreNMS OpenWrt wireless SNMP extends (file-less)

SCRIPT_DIR="/etc/librenms"
printf "\n# Generated %s - Wireless + sensors\n" "$(date)"
echo "# LIBRENMS_OPENWRT_AUTOGEN_BEGIN"

cat << EOF

# Interface map for LibreNMS OpenWrt wireless discovery
config extend
	option name 'interfaces'
	option prog '$SCRIPT_DIR/wlInterfaces.sh'

# Aggregate client count across active wireless interfaces
config extend
	option name 'clients-wlan'
	option prog '$SCRIPT_DIR/wlClients.sh'

EOF

# Use the same interface inventory that LibreNMS discovery consumes.
"$SCRIPT_DIR/wlInterfaces.sh" 2>/dev/null | while IFS=',' read -r iface label; do
  [ -n "$iface" ] || continue

	ssid=$(printf '%s' "$label" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
	[ -n "$ssid" ] || ssid="$iface"

  cat << EOF

# $ssid ($iface)
config extend
	option name 'clients-$iface'
	option prog '$SCRIPT_DIR/wlClients.sh'
	option args '$iface'

config extend
	option name 'frequency-$iface'
	option prog '$SCRIPT_DIR/wlFrequency.sh'
	option args '$iface'

config extend
	option name 'noise-floor-$iface'
	option prog '$SCRIPT_DIR/wlNoiseFloor.sh'
	option args '$iface'

EOF
  # Rates/SNR loops (add your for min/avg/max...)
  for dir in tx rx; do for stat in min avg max; do cat << EOF
config extend
	option name 'rate-${dir}-$iface-$stat'
	option prog '$SCRIPT_DIR/wlRate.sh'
	option args '$iface $dir $stat'
EOF
  done; done
  for stat in min avg max; do cat << EOF
config extend
	option name 'snr-$iface-$stat'
	option prog '$SCRIPT_DIR/wlSNR.sh'
	option args '$iface $stat'
EOF
  done
done

cat << EOF

# Sensors (always)
config pass
	option name 'lm-sensors'
	option prog '$SCRIPT_DIR/lm-sensors-pass.sh'
	option miboid '.1.3.6.1.4.1.2021.13.16.2.1'
EOF

echo "# LIBRENMS_OPENWRT_AUTOGEN_END"
