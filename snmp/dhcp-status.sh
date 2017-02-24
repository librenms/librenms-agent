#!/bin/bash
################################################################
# copy this script to somewhere like /opt and make chmod +x it #
# edit your snmpd.conf add the below line and restart snmpd    #
# extend dhcpstats /opt/dhcp-status.sh                         #
################################################################ 
exists_command()
{
  command -v "$1" >/dev/null 2>&1
}

require_commands=("cat" "grep" "tr" "sed" "sort" "wc") ;

for i in "${require_commands[@]}" ;
do
    if exists_command $i; then
        eval "BIN_${i^^}"="$(command -v $i)";
    else
        echo "Your system does not have [$i]";
        exit
    fi

done ;

FILE_DHCP='/var/lib/dhcp/db/dhcpd.leases'


if [ ! -f $FILE_DHCP ]; then
   echo "File $FILE_DHCP does not exist.";
   exit;
fi


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

for state in "$DHCP_ACTIVE" "$DHCP_EXPIRED" "$DHCP_RELEASED" "$DHCP_ABANDONED" "$DHCP_RESET" "$DHCP_BOOTP" "$DHCP_BACKUP" "$DHCP_FREE"
do
        $BIN_GREP -E "$state"  $FILE_DHCP | $BIN_TR '\n' '|' | $BIN_SED 's/ {| //g' | $BIN_TR '|' '\n' | $BIN_GREP -E "$NO_ERROR" | $BIN_SORT -u | $BIN_WC -l
done
