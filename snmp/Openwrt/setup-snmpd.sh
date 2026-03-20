#!/bin/sh
set -eu

# setup-snmpd.sh
# Install OpenWrt LibreNMS helper scripts and optionally apply generated
# SNMP extend configuration.

SCRIPT_DIR="/etc/librenms"
BACKUP_DIR="$SCRIPT_DIR/backup"
SOURCE_DIR=$(cd -- "$(dirname -- "$0")" && pwd)

AUTO_YES=0
NO_RESTART=0

while [ "$#" -gt 0 ]; do
	case "$1" in
		-y|--yes) AUTO_YES=1 ;;
		--no-restart) NO_RESTART=1 ;;
		-h|--help)
			cat <<'EOF'
Usage: setup-snmpd.sh [--yes|-y] [--no-restart]

	-y, --yes       Apply generated snmpd config without prompt
			--no-restart  Do not restart snmpd after applying config
EOF
			exit 0
			;;
		*)
			echo "Unknown option: $1" >&2
			exit 2
			;;
	esac
	shift
done

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

has_extend_name() {
	name="$1"
	grep -Eq "^[[:space:]]*option[[:space:]]+name[[:space:]]+'$name'[[:space:]]*$" /etc/config/snmpd
}

ensure_base_os_extends() {
	if ! has_extend_name distro; then
		cat >> /etc/config/snmpd <<'EOF'

config extend
	option name 'distro'
	option prog '/bin/sh'
	option args "-c '. /etc/os-release; echo \"\$PRETTY_NAME\"'"
EOF
		echo "  + Added missing extend: distro"
	fi

	if ! has_extend_name hardware; then
		cat >> /etc/config/snmpd <<'EOF'

config extend
	option name 'hardware'
	option prog '/bin/cat'
	option args '/sys/firmware/devicetree/base/model'
EOF
		echo "  + Added missing extend: hardware"
	fi
}

ensure_system_section() {
	if ! grep -Eq "^[[:space:]]*config[[:space:]]+system[[:space:]]+'system'[[:space:]]*$" /etc/config/snmpd; then
		hostname=$(uname -n 2>/dev/null || echo openwrt)
		cat >> /etc/config/snmpd <<EOF

config system 'system'
	option sysLocation 'unknown'
	option sysName '$hostname'
	option sysContact 'root@localhost'
	option sysDescr 'OpenWrt'
EOF
		echo "  + Added missing section: config system 'system'"
	fi
}

apply_generated_snmpd_block() {
	tmp_block=$(mktemp)
	tmp_new=$(mktemp)

	"$SCRIPT_DIR/snmpd-config-generator.sh" > "$tmp_block"

	# Remove previously managed sections first (legacy and marker-based).
	remove_managed_snmpd_sections

	# Append exactly one fresh generated block.
	cat /etc/config/snmpd "$tmp_block" > "$tmp_new"
	mv "$tmp_new" /etc/config/snmpd
	rm -f "$tmp_block"
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
else
  touch /etc/config/snmpd
fi

# Copy scripts to /etc/librenms/
echo "Installing monitoring scripts to $SCRIPT_DIR..."

scripts="wlInterfaces.sh wlClients.sh wlFrequency.sh wlNoiseFloor.sh wlRate.sh wlSNR.sh lm-sensors-pass.sh snmpd-config-generator.sh"

for script in $scripts; do
	src="$SOURCE_DIR/$script"
	dst="$SCRIPT_DIR/$script"
	if [ -f "$src" ]; then
		if [ "$src" = "$dst" ]; then
			chmod +x "$dst"
			echo "  ✓ Using existing $script"
		else
			cp "$src" "$SCRIPT_DIR/"
			chmod +x "$dst"
			echo "  ✓ Installed $script"
		fi
	else
		echo "  ✗ Warning: $script not found in $SOURCE_DIR"
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

if [ "$AUTO_YES" -eq 1 ]; then
	answer="y"
else
	printf "Do you want to update the SNMP configuration? [Y/n]: "
	read -r answer
	answer=$(echo "$answer" | tr '[:upper:]' '[:lower:]')
fi

if [ -z "$answer" ] || [ "$answer" = "y" ]; then
    echo "Updating snmpd configuration..."

		# Extra one-shot backup before write
		cp /etc/config/snmpd /etc/config/snmpd-backup

		# Write exactly one fresh generated LibreNMS block.
    chmod +x "$SCRIPT_DIR/snmpd-config-generator.sh"
		ensure_base_os_extends
		ensure_system_section
		apply_generated_snmpd_block

		if [ "$NO_RESTART" -eq 0 ]; then
			/etc/init.d/snmpd restart
			echo "Done! Service restarted."
		else
			echo "Skipped snmpd restart (--no-restart)."
			echo "Done! Configuration updated."
		fi
else
    echo "Aborted. No changes made."
    exit 1
fi
