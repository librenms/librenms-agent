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

# Live ubus discovery (ap1 wl*, ap2 wlan*, risc phy*)
ubus list hostapd.* 2>/dev/null | sed 's/^hostapd\.//' | while IFS= read -r iface; do
  # Robust ssid (handles JSON variance)
  ssid=$(ubus call "hostapd.$iface" get_status 2>/dev/null | \
    sed -n 's/.*"ssid":"\?\([^",]*\)"\?.*/\1/p' | head -1 || echo unknown)
  [ -n "$iface" ] || continue

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
