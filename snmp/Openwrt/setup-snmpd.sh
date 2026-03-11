#!/bin/sh

# setup-snmpd.sh
# Installation and configuration script for OpenWrt SNMP monitoring
# This script sets up all necessary scripts and generates the snmpd config

SCRIPT_DIR="/etc/librenms"
BACKUP_DIR="/etc/librenms/backup"

echo "OpenWrt SNMPD Setup Script"
echo "=========================="
echo ""

remove_managed_snmpd_sections() {
	tmp_clean=$(mktemp)
	awk '
		BEGIN { RS=""; ORS="\n\n" }
		{
			block = $0
			managed = 0

			if (block ~ /LIBRENMS_OPENWRT_AUTOGEN_BEGIN/ || block ~ /LIBRENMS_OPENWRT_AUTOGEN_END/) {
				managed = 1
			}
			if (block ~ /config extend/ && block ~ /option name '\''interfaces'\''/) {
				managed = 1
			}
			if (block ~ /config extend/ && block ~ /option name '\''clients-wlan'\''/) {
				managed = 1
			}
			if (block ~ /config extend/ && block ~ /option name '\''(clients|wl-clients|frequency|noise-floor|rate|snr)-[^'\'']+'\''/) {
				managed = 1
			}
			if (block ~ /config pass/ && (block ~ /option name '\''lm-sensors'\''/ || block ~ /option prog '\''\/etc\/librenms\/lm-sensors-pass.sh'\''/)) {
				managed = 1
			}

			if (!managed) {
				print block
			}
		}
	' /etc/config/snmpd > "$tmp_clean"
	mv "$tmp_clean" /etc/config/snmpd
}

# Create directories
echo "Creating directories..."
mkdir -p "$SCRIPT_DIR"
mkdir -p "$BACKUP_DIR"

# Backup existing config if it exists
if [ -f /etc/config/snmpd ]; then
	timestamp=$(date +%Y%m%d_%H%M%S)
	echo "Backing up existing /etc/config/snmpd to $BACKUP_DIR/snmpd.$timestamp"
	cp /etc/config/snmpd "$BACKUP_DIR/snmpd.$timestamp"
fi

# Copy scripts to /etc/librenms/
echo "Installing monitoring scripts to $SCRIPT_DIR..."

scripts="wlInterfaces.sh wlClients.sh wlFrequency.sh wlNoiseFloor.sh wlRate.sh wlSNR.sh lm-sensors-pass.sh distro.sh snmpd-config-generator.sh"

for script in $scripts; do
	if [ -f "$script" ]; then
		cp "$script" "$SCRIPT_DIR/"
		chmod +x "$SCRIPT_DIR/$script"
		echo "  ✓ Installed $script"
	else
		echo "  ✗ Warning: $script not found in current directory"
	fi
done

# Generate sample config
echo ""
echo "Generating SNMPD configuration..."
echo "Run the following command to see the generated config:"
echo ""
echo "  $SCRIPT_DIR/snmpd-config-generator.sh"
echo ""
echo "To apply the configuration:"
echo "  1. Backup your current config: cp /etc/config/snmpd /etc/config/snmpd.backup"
echo "  2. Replace old LibreNMS wireless sections with the generated block"
echo "  3. Restart snmpd: /etc/init.d/snmpd restart"
echo ""
echo "Setup complete!"

# Ask for confirmation
printf "Do you want to update the SNMP configuration? [Y/n]: "
read -r answer

# Convert to lowercase and check (default to 'y' if empty)
answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')

if [ -z "$answer" ] || [ "$answer" = "y" ]; then
    echo "Updating snmpd configuration..."

    # 1. Backup existing config
    cp /etc/config/snmpd /etc/config/snmpd-backup

	# 2. Remove previously managed LibreNMS wireless sections
	remove_managed_snmpd_sections

	# 3. Append one fresh generated config block
    chmod +x "$SCRIPT_DIR/snmpd-config-generator.sh"
    "$SCRIPT_DIR/snmpd-config-generator.sh" >> /etc/config/snmpd

	# 4. Restart the service
    /etc/init.d/snmpd restart

    echo "Done! Service restarted."
else
    echo "Aborted. No changes made."
    exit 1
fi
