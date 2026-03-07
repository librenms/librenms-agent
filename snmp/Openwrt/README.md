# OpenWrt-LibreNMS
SNMPD OpenWrt configuration - integration for OpenWrt devices to be visible wtih more features in LibreNMS network management platform. Based on https://github.com/librenms/librenms-agent/tree/master/snmp/Openwrt

This package provides unified, auto-detecting SNMP monitoring for OpenWrt devices with support for:
- Wireless interface metrics (clients, frequency, rate, noise, SNR)
- Thermal sensor monitoring via LM-SENSORS-MIB
- Auto-discovery of wireless interfaces
- Dynamic configuration generation

## Key Features

### 1. Auto-Generation of wlInterfaces.txt

`wlClients.sh` auto-detects all wireless interfaces on first run and generates the file automatically.

```bash
# First run automatically creates wlInterfaces.txt
/etc/librenms/wlClients.sh
```

### 2. Dynamic Config Generator
**Problem**: Different devices need different snmpd configs based on their wireless interfaces (ap1: wl0-ap0, wl1-ap0; ap2: wlan0, wlan02, wlan12, wlan22).

**Solution**: `snmpd-config-generator.sh` reads wlInterfaces.txt and generates appropriate UCI config entries for all detected interfaces.

```bash
# Generate config for current device
/etc/librenms/snmpd-config-generator.sh
```

### 3. Unified Base Configuration
**Problem**: Repetitive config entries across devices.

**Solution**: /etc/config/snmpd is updated with dynamic content.

### 4. Error Handling
All scripts have:
- Error messages
- Argument validation
- Fallback behavior
- Consistent exit codes

### 5. Thermal Sensor Support (LM-SENSORS-MIB)
Uses the `pass` directive to provide proper LM-SENSORS-MIB thermal sensors:
- `.1.3.6.1.4.1.2021.13.16.2.1.1` - lmTempSensorsIndex (INTEGER)
- `.1.3.6.1.4.1.2021.13.16.2.1.2` - lmTempSensorsDevice (STRING)
- `.1.3.6.1.4.1.2021.13.16.2.1.3` - lmTempSensorsValue (Gauge32, millidegrees)

The `pass` script (`lm-sensors-pass.sh`) provides proper data types and table structure, enabling automatic discovery in LibreNMS.

## File Structure

```
/etc/librenms/
├── wlInterfaces.txt              # Auto-generated interface list
├── wlClients.sh                  # Count Wi-Fi clients (auto-generates wlInterfaces.txt)
├── wlFrequency.sh                # Get operating frequency
├── wlNoiseFloor.sh               # Get noise floor
├── wlRate.sh                     # Get TX/RX rates (min/avg/max)
├── wlSNR.sh                      # Get SNR (min/avg/max)
├── lm-sensors-pass.sh            # LM-SENSORS-MIB pass script for thermal sensors
├── distro.sh                     # Extract OpenWrt version string
├── cleanup-and-fix.sh            # Remove old exec entries
└── snmpd-config-generator.sh     # Generate UCI config entries
```

## Installation

### Quick Setup
```bash
# Run setup script
chmod +x setup-snmpd.sh
./setup-snmpd.sh

### Manual Installation
```bash
# Create directory
mkdir -p /etc/librenms

# Copy all scripts
cp wl*.sh lm-sensors-pass.sh distro.sh cleanup-and-fix.sh snmpd-config-generator.sh /etc/librenms/
chmod +x /etc/librenms/*.sh

# Generate interface list
/etc/librenms/wlClients.sh

# Generate config
/etc/librenms/snmpd-config-generator.sh
```

## Usage

### Generate wlInterfaces.txt
```bash
# Auto-detect all wireless interfaces
/etc/librenms/wlClients.sh

# Manually edit if needed
vi /etc/librenms/wlInterfaces.txt
# Format: interface,ssid
# Example:
# wl0-ap0,MySSID
# wlan0,GuestNetwork
```

### Generate SNMPD Config
```bash
# Generate all extend entries for detected interfaces
/etc/librenms/snmpd-config-generator.sh

# Output can be appended to /etc/config/snmpd
/etc/librenms/snmpd-config-generator.sh >> /etc/config/snmpd
```

### Test Scripts Individually
```bash
# Test client count
/etc/librenms/wlClients.sh wlan0

# Test frequency
/etc/librenms/wlFrequency.sh wlan0

# Test rate (interface, direction, stat)
/etc/librenms/wlRate.sh wlan0 tx avg

# Test SNR (interface, stat)
/etc/librenms/wlSNR.sh wlan0 avg

# Test thermal sensors (pass script)
/etc/librenms/lm-sensors-pass.sh -g .1.3.6.1.4.1.2021.13.16.2.1.3.0
```

### Query SNMP
```bash
# From monitoring server
snmpwalk -v2c -c public localhost .1.3.6.1.4.1.8072.1.3.2

# Specific metrics
snmpget -v2c -c public localhost NET-SNMP-EXTEND-MIB::nsExtendOutput1Line.\"clients-wlan0\"
snmpget -v2c -c public localhost NET-SNMP-EXTEND-MIB::nsExtendOutput1Line.\"frequency-wlan0\"

# Thermal sensors (LM-SENSORS-MIB)
snmpwalk -v2c -c public localhost LM-SENSORS-MIB::lmTempSensorsValue
```

## SNMP OID Reference

### Wireless Metrics (via nsExtend)
Base OID: `.1.3.6.1.4.1.8072.1.3.2`

Per interface:
- `clients-<iface>` - Connected client count
- `frequency-<iface>` - Operating frequency (MHz)
- `rate-tx-<iface>-min/avg/max` - TX bitrate stats
- `rate-rx-<iface>-min/avg/max` - RX bitrate stats
- `noise-floor-<iface>` - Noise floor (dBm)
- `snr-<iface>-min/avg/max` - Signal-to-Noise Ratio (dB)

### Thermal Sensors (LM-Sensors MIB)
- `.1.3.6.1.4.1.2021.13.16.2.1.1` - lmSensorsIndex (INTEGER)
- `.1.3.6.1.4.1.2021.13.16.2.1.2` - lmSensorsDevice (STRING)
- `.1.3.6.1.4.1.2021.13.16.2.1.3` - lmSensorsValue (Gauge32, millidegrees)

## Configuration Examples

### Example: 4 Interface Device (like native OpenWrt)
wlInterfaces.txt:
```
wl0-ap0,IoT
wl0-ap1,guest
wl1-ap0,main
wl1-ap1,uplink
```

Generated extends:
- clients-wl0-ap0, clients-wl0-ap1, clients-wl1-ap0, clients-wl1-ap1
- frequency-wl0-ap0, frequency-wl0-ap1, frequency-wl1-ap0, frequency-wl1-ap1
- rate-tx-wl0-ap0-min/avg/max (and all other interfaces)
- rate-rx-wl0-ap0-min/avg/max (and all other interfaces)
- And so on...

### Example: Multi-VLAN Device (like gl.Inet flint3)
wlInterfaces.txt:
```
wlan0,MainNetwork
wlan02,VLAN2
wlan12,VLAN12
wlan22,VLAN22
```

## Troubleshooting

### wlInterfaces.txt not generated
```bash
# Check for wireless interfaces
ls /sys/class/net/*/wireless
ls /sys/class/net/*/phy80211

# Manually create the file
cat > /etc/librenms/wlInterfaces.txt << EOF
wlan0,YourSSID
EOF
```

### SNMP not returning data
```bash
# Check if snmpd is running
/etc/init.d/snmpd status

# Check if scripts are executable
ls -la /etc/librenms/*.sh

# Test script directly
/etc/librenms/wlClients.sh wlan0

# Check snmpd logs
logread | grep snmpd
```

### Script errors
```bash
# Enable debug output
sh -x /etc/librenms/wlClients.sh wlan0

# Check for required commands
which iw iwinfo awk cut grep
```

## Comparison: Before vs After

### Before (Manual, Per-Device)
❌ Required manual creation of wlInterfaces.txt for each device
❌ Different config file for each device type
❌ Repetitive config entries (280+ lines)
❌ Hard to maintain across multiple devices
❌ Interface changes require manual config updates

### After (Automated, Unified)
✅ Auto-detects wireless interfaces
✅ Single config generator works for all devices
✅ Generates only needed entries
✅ Easy to maintain and replicate
✅ Interface changes auto-detected on script run

## Benefits

1. **Zero Manual Configuration**: Just run setup script
2. **Device-Agnostic**: Works on any OpenWrt device
3. **Self-Documenting**: Auto-generated configs show what's monitored
4. **Easy Replication**: Same process for all devices
5. **Future-Proof**: Adding interfaces doesn't require config changes
6. **Reduced Errors**: No manual typing of repetitive entries
7. **Consistent**: All devices use same monitoring approach

## Security Notes

- Default SNMP community strings should be changed in production
- Restrict SNMP access to monitoring network (192.168.0.0/24 in examples)
- Use SNMPv3 for better security if supported by your NMS

## License

These scripts are provided as-is for use with OpenWrt systems.
