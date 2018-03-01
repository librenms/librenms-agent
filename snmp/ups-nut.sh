#!/usr/bin/env bash

# - Copy this script to somewhere (like /opt/ups-nut.sh)
# - Make it executable (chmod +x /opt/ups-nut.sh)
# - Change the UPS_NAME variable to match the name of your UPS
# - Add the following line to your snmpd.conf file
#   extend ups-nut /opt/ups-nut.sh
# - Restart snmpd
#
# Note: Change the path accordingly, if you're not using "/opt/ups-nut.sh"

# You need the following tools to be in your PATH env, adjust accordingly
# - awk, grep, upsc
PATH=$PATH

# Change the name to match your UPS
UPS_NAME='APCUPS'

IFS=$'\n'
for conf in $(upsc $UPS_NAME 2>/dev/null | grep ":" | awk -F":" '{gsub(/\./, "_", $1);gsub(/^[ \t]+/, "", $2); print $1 "=" $2}')
do
	export $conf
done

echo $battery_charge
echo $battery_runtime_low
echo $battery_runtime
echo $battery_voltage
echo $battery_voltage_nominal
echo $input_voltage_nominal
echo $input_voltage
echo $ups_load