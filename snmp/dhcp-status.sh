#!/bin/bash
################################################################
# copy this script to somewhere like /opt and make chmod +x it #
# edit your snmpd.conf add the below line and restart snmpd    #
# extend dhcpstats /opt/dhcp-status.sh                         #
################################################################ 
FILE_DHCP='/var/lib/dhcp/db/dhcpd.leases'
BIN_CAT='/usr/bin/cat'
BIN_GREP='/usr/bin/grep'
BIN_TR='/usr/bin/tr'
BIN_SED='/usr/bin/sed'
BIN_SORT='/usr/bin/sort'
BIN_WC='/usr/bin/wc'
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

$BIN_CAT $FILE_DHCP | $BIN_GREP $DHCP_LEASES | $BIN_SORT -u | $BIN_WC -l
$BIN_GREP -E "$DHCP_ACTIVE" $FILE_DHCP | $BIN_TR '\n' '|' | $BIN_SED 's/ {| //g' | $BIN_TR '|' '\n' | $BIN_GREP -E "$NO_ERROR" | $BIN_SORT -u | $BIN_WC -l
$BIN_GREP -E "$DHCP_EXPIRED" $FILE_DHCP | $BIN_TR '\n' '|' | $BIN_SED 's/ {| //g' | $BIN_TR '|' '\n' | $BIN_GREP -E "$NO_ERROR" | $BIN_SORT -u | $BIN_WC -l
$BIN_GREP -E "$DHCP_RELEASED" $FILE_DHCP | $BIN_TR '\n' '|' | $BIN_SED 's/ {| //g' | $BIN_TR '|' '\n' | $BIN_GREP -E "$NO_ERROR" | $BIN_SORT -u | $BIN_WC -l
$BIN_GREP -E "$DHCP_ABANDONED" $FILE_DHCP | $BIN_TR '\n' '|' | $BIN_SED 's/ {| //g' | $BIN_TR '|' '\n' | $BIN_GREP -E "$NO_ERROR" | $BIN_SORT -u | $BIN_WC -l
$BIN_GREP -E "$DHCP_RESET" $FILE_DHCP | $BIN_TR '\n' '|' | $BIN_SED 's/ {| //g' | $BIN_TR '|' '\n' | $BIN_GREP -E "$NO_ERROR" | $BIN_SORT -u | $BIN_WC -l
$BIN_GREP -E "$DHCP_BOOTP" $FILE_DHCP | $BIN_TR '\n' '|' | $BIN_SED 's/ {| //g' | $BIN_TR '|' '\n' | $BIN_GREP -E "$NO_ERROR" | $BIN_SORT -u | $BIN_WC -l
$BIN_GREP -E "$DHCP_BACKUP" $FILE_DHCP | $BIN_TR '\n' '|' | $BIN_SED 's/ {| //g' | $BIN_TR '|' '\n' | $BIN_GREP -E "$NO_ERROR" | $BIN_SORT -u | $BIN_WC -l
$BIN_GREP -E "$DHCP_FREE" $FILE_DHCP | $BIN_TR '\n' '|' | $BIN_SED 's/ {| //g' | $BIN_TR '|' '\n' | $BIN_GREP -E "$NO_ERROR" | $BIN_SORT -u | $BIN_WC -l
