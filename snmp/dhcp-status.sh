#!/usr/bin/env bash

# - Copy this script to somewhere (like /opt/dhcp-status.sh)
# - Make it executable (chmod +x /opt/dhcp-status.sh)
# - Add the following line to your snmpd.conf file
#   extend dhcpstats /opt/dhcp-status.sh
# - Restart snmpd
#
# Note: Change the path accordingly, if you're not using "/opt/dhcp-status.sh"

# You need the following tools to be in your PATH env, adjust accordingly
# - cat, grep, sed, sort, tr, wc
PATH=$PATH

# Leases location
FILE_DHCP='/var/lib/dhcp/db/dhcpd.leases'

# Patterns
DHCP_LEASES='^lease'
DHCP_ACTIVE='^lease|binding state active'
DHCP_EXPIRED='^lease|binding state expired'
DHCP_RELEASED='^lease|binding state released'
DHCP_ABANDONED='^lease|binding state abandoned'
DHCP_RESET='^lease|binding state reset'
DHCP_BOOTP='^lease|binding state bootp'
DHCP_BACKUP='^lease|binding state backup'
DHCP_FREE='^lease|binding state free'
NO_ERROR='[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3} binding'

cat $FILE_DHCP | grep $DHCP_LEASES | sort -u | wc -l | tr -d "[:blank:]"

for state in "$DHCP_ACTIVE" "$DHCP_EXPIRED" "$DHCP_RELEASED" "$DHCP_ABANDONED" "$DHCP_RESET" "$DHCP_BOOTP" "$DHCP_BACKUP" "$DHCP_FREE"
do
    grep -E "$state" "$FILE_DHCP" | tr '\n' '|' | sed 's/ {| //g' | tr '|' '\n' | grep -E "$NO_ERROR" | sort -u | wc -l | tr -d "[:blank:]"
done
