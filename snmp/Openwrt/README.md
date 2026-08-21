# OpenWrt wireless + sensors SNMP agent

These scripts expose per-radio and aggregate wireless metrics (plus lm-sensors
temperatures and fan speeds) to LibreNMS through net-snmp `pass_persist` handlers. Radios and
VAPs are discovered live at request time, so there is no per-interface or
per-metric snmpd configuration to maintain. See
[Device-Notes/Openwrt.md](https://docs.librenms.org/Support/Device-Notes/#openwrt)
for the LibreNMS-side install and discovery steps.

## Scripts

| Script | Purpose |
| --- | --- |
| `openwrt-snmp-pass.sh` | Wireless `pass_persist` handler. Serves the OpenWrt wireless subtree (OPENWRT-WIRELESS-MIB, `.1.3.6.1.4.1.66510.1.10`) from a single snmpd line. |
| `lm-sensors-pass.sh` | Temperature + fan `pass_persist` handler (LM-SENSORS-MIB emulation). Temperatures from thermal zones; fan RPM from hwmon tachometer inputs (`fan*_input`, e.g. `kmod-hwmon-pwmfan`). |
| `wlInterfaces.sh` | Interface/label inventory. Helper used by `openwrt-snmp-pass.sh`. |
| `wlClients.sh [iface]` | Client counts (per interface, or aggregate). Helper. |
| `wlFrequency.sh <iface>` | Channel frequency (MHz). Helper. |
| `wlNoiseFloor.sh <iface>` | Noise floor (dBm). Helper. |
| `wlRate.sh <iface> <tx\|rx> <min\|avg\|max>` | TX/RX rate (Mbit/s). Helper. |
| `wlSNR.sh <iface> <min\|avg\|max>` | SNR (dB). Helper. |

The `wl*.sh` scripts are collection helpers invoked by `openwrt-snmp-pass.sh`;
they are not registered with snmpd directly. They can be run standalone for
debugging.

## snmpd configuration

Copy the scripts to a directory on the device (the helpers must sit next to
`openwrt-snmp-pass.sh`, which calls them by relative path):

```sh
mkdir -p /usr/libexec/openwrt-snmp
for s in openwrt-snmp-pass lm-sensors-pass wlInterfaces wlClients \
         wlFrequency wlNoiseFloor wlRate wlSNR; do
  wget -O "/usr/libexec/openwrt-snmp/$s.sh" \
    "https://raw.githubusercontent.com/librenms/librenms-agent/master/snmp/Openwrt/$s.sh"
done
chmod +x /usr/libexec/openwrt-snmp/*.sh
```

Register the two handlers in `/etc/config/snmpd`:

```
config pass
	option miboid '.1.3.6.1.4.1.66510.1.10'
	option prog '/usr/libexec/openwrt-snmp/openwrt-snmp-pass.sh'
	option persist '1'

config pass
	option miboid '.1.3.6.1.4.1.2021.13.16'
	option prog '/usr/libexec/openwrt-snmp/lm-sensors-pass.sh'
	option persist '1'
```

OS detection additionally reads a `distro` and a `hardware` extend
(`nsExtendOutput1Line."distro"` / `."hardware"`); these use small inline
commands rather than shipped scripts:

```
config extend
	option name 'distro'
	option prog '/bin/sh'
	option args '-c '\''. /etc/os-release; echo $PRETTY_NAME'\'''

config extend
	option name 'hardware'
	option prog '/bin/cat'
	option args '/tmp/sysinfo/model'
```

(`/tmp/sysinfo/model` is OpenWrt's board-detection model string; it works on all
targets including x86, unlike `/sys/firmware/devicetree/base/model`.)

Restart snmpd:

```sh
/etc/init.d/snmpd restart
```

## Validation

From the LibreNMS host, walk the wireless subtree and the sensor tables
(temperatures at `.13.16.2`, fans at `.13.16.3`):

```sh
snmpwalk -v2c -c your_community_string <openwrt-host> .1.3.6.1.4.1.66510.1.10
snmpwalk -v2c -c your_community_string <openwrt-host> .1.3.6.1.4.1.2021.13.16
```

On the device, the handler can be exercised directly:

```sh
/usr/libexec/openwrt-snmp/openwrt-snmp-pass.sh --snapshot        # full OID table
/usr/libexec/openwrt-snmp/openwrt-snmp-pass.sh -g <oid>          # single GET
/usr/libexec/openwrt-snmp/openwrt-snmp-pass.sh -n <oid>          # GETNEXT
```
