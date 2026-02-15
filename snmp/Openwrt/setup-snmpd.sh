#!/bin/sh

# setup-snmpd.sh
# Installation and configuration script for OpenWrt SNMP monitoring
# This script sets up all necessary scripts and generates the snmpd config

SCRIPT_DIR="/etc/librenms"
BACKUP_DIR="/etc/librenms/backup"

echo "OpenWrt SNMPD Setup Script"
echo "=========================="
echo ""

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

scripts="wlClients.sh wlFrequency.sh wlNoiseFloor.sh wlRate.sh wlSNR.sh lm-sensors-pass.sh distro.sh cleanup-and-fix.sh snmpd-config-generator.sh"

for script in $scripts; do
	if [ -f "$script" ]; then
		cp "$script" "$SCRIPT_DIR/"
		chmod +x "$SCRIPT_DIR/$script"
		echo "  ✓ Installed $script"
	else
		echo "  ✗ Warning: $script not found in current directory"
	fi
done

# Generate wlInterfaces.txt
echo ""
echo "Generating wlInterfaces.txt..."
"$SCRIPT_DIR/wlClients.sh" > /dev/null 2>&1
if [ -f "$SCRIPT_DIR/wlInterfaces.txt" ]; then
	echo "  ✓ Generated $SCRIPT_DIR/wlInterfaces.txt"
	cat "$SCRIPT_DIR/wlInterfaces.txt"
else
	echo "  ✗ Failed to generate wlInterfaces.txt"
fi

# Generate sample config
echo ""
echo "Generating SNMPD configuration..."
echo "Run the following command to see the generated config:"
echo ""
echo "  $SCRIPT_DIR/snmpd-config-generator.sh"
echo ""
echo "To apply the configuration:"
echo "  1. Backup your current config: cp /etc/config/snmpd /etc/config/snmpd.backup"
echo "  2. Edit /etc/config/snmpd and add the generated sections"
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
    
    # 2. Append generated config
    # Ensure the generator script is executable
    chmod +x "$SCRIPT_DIR/snmpd-config-generator.sh"
    "$SCRIPT_DIR/snmpd-config-generator.sh" >> /etc/config/snmpd
    
    # 3. Restart the service
    /etc/init.d/snmpd restart
    
    echo "Done! Service restarted."
else
    echo "Aborted. No changes made."
    exit 1
fi
