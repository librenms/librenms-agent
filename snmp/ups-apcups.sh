#!/usr/bin/env bash

# - Copy this script to somewhere (like /opt/ups-apcups.sh)
# - Make it executable (chmod +x /opt/ups-apcups.sh)
# - Change the UPS_NAME variable to match the name of your UPS
# - Add the following line to your snmpd.conf file
#   extend ups-apcups /opt/ups-apcups.sh
# - Restart snmpd
#
# Note: Change the path accordingly, if you're not using "/opt/ups-apcups.sh"

# You need the following tools to be in your PATH env, adjust accordingly
# - apcaccess, cut, grep
PATH=$PATH

IFS=$'\n'
for conf in $(apcaccess 2>/dev/null | grep ":" | awk -F":" '{gsub(/ /, "", $1);gsub(/^[ \t]+/, "", $2); print $1 "=" $2}')
do
    export $conf
done

echo $BCHARGE   | cut -d " " -f1
echo $TIMELEFT  | cut -d " " -f1
echo $NOMBATTV  | cut -d " " -f1
echo $BATTV     | cut -d " " -f1
echo $LINEV     | cut -d " " -f1
echo $NOMINV    | cut -d " " -f1
echo $LOADPCT   | cut -d " " -f1
