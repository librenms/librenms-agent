# OpenWrt wireless + sensors SNMP extends

These scripts expose per-radio and aggregate wireless metrics (plus lm-sensors
temperatures) to LibreNMS via NET-SNMP extends. See
[Device-Notes/Openwrt.md](https://docs.librenms.org/Support/Device-Notes/#openwrt)
in the LibreNMS docs for install and discovery steps.

## Scripts

| Script | Purpose |
| --- | --- |
| `distro.sh` | OS / version string for device identification |
| `wlInterfaces.sh` | Interface map consumed by wireless discovery |
| `wlClients.sh [iface]` | Client counts (per interface, or aggregate) |
| `wlFrequency.sh <iface>` | Channel frequency (MHz) |
| `wlNoiseFloor.sh <iface>` | Noise floor (dBm) |
| `wlRate.sh <iface> <tx\|rx> <min\|avg\|max>` | TX/RX rate (bps) |
| `wlSNR.sh <iface> <min\|avg\|max>` | SNR (dB) |
| `lm-sensors-pass.sh` | Temperature sensors (pass_persist) |

## Generating the snmpd extends (optional)

Writing the per-radio `extend` blocks by hand is tedious on routers with several
radios. The sample below discovers the live hostapd interfaces (via
`wlInterfaces.sh`) and prints a ready-to-paste block for `/etc/config/snmpd`.

It is a **starting point**, not a shipped/maintained tool — review and adapt it for
your device before use:

```sh
#!/bin/sh
set -eu
# Sample: generate LibreNMS OpenWrt wireless SNMP extends from the live interfaces.
SCRIPT_DIR="/etc/librenms"

echo "# LIBRENMS_OPENWRT_AUTOGEN_BEGIN"
cat <<EOF
config extend
	option name 'interfaces'
	option prog '$SCRIPT_DIR/wlInterfaces.sh'

config extend
	option name 'clients-wlan'
	option prog '$SCRIPT_DIR/wlClients.sh'
EOF

# Use the same interface inventory that LibreNMS discovery consumes.
"$SCRIPT_DIR/wlInterfaces.sh" 2>/dev/null | while IFS=',' read -r iface label; do
	[ -n "$iface" ] || continue
	ssid=$(printf '%s' "$label" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
	[ -n "$ssid" ] || ssid="$iface"

	cat <<EOF

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

	for dir in tx rx; do for stat in min avg max; do cat <<EOF
config extend
	option name 'rate-$dir-$iface-$stat'
	option prog '$SCRIPT_DIR/wlRate.sh'
	option args '$iface $dir $stat'
EOF
	done; done

	for stat in min avg max; do cat <<EOF
config extend
	option name 'snr-$iface-$stat'
	option prog '$SCRIPT_DIR/wlSNR.sh'
	option args '$iface $stat'
EOF
	done
done

cat <<EOF

config pass
	option name 'lm-sensors'
	option prog '$SCRIPT_DIR/lm-sensors-pass.sh'
	option miboid '.1.3.6.1.4.1.2021.13.16.2.1'
EOF
echo "# LIBRENMS_OPENWRT_AUTOGEN_END"
```

Apply (or re-apply) the output safely — back up first, replace any previously
generated block, then restart snmpd:

```sh
cp /etc/config/snmpd /etc/config/snmpd.bak
sed -i '/# LIBRENMS_OPENWRT_AUTOGEN_BEGIN/,/# LIBRENMS_OPENWRT_AUTOGEN_END/d' /etc/config/snmpd
sh generate-extends.sh >> /etc/config/snmpd
/etc/init.d/snmpd restart
```

The `AUTOGEN_BEGIN/END` markers let you re-run after WLAN/SSID changes without
duplicating extends.

Verify from the LibreNMS host:

```sh
snmpwalk -v2c -c your_community_string <openwrt-host> NET-SNMP-EXTEND-MIB::nsExtendObjects
```
