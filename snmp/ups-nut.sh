#!/usr/bin/env bash
################################################################
# Instructions:                                                #
# 1. copy this script to /etc/snmp/ and make it executable:    #
#    chmod +x ups-nut.sh                                       #
# 2. make sure UPS_NAME below matches the name of your UPS     #
# 3. edit your snmpd.conf to include this line:                #
#    extend ups-nut /etc/snmp/ups-nut.sh                       #
# 4. restart snmpd on the host                                 #
# 5. activate the app for the desired host in LibreNMS         #
################################################################
UPS_NAME='APCUPS'

PATH=$PATH:/usr/bin:/bin
TMP=$(upsc $UPS_NAME 2>/dev/null)

for value in "battery\.charge: [0-9.]+" "battery\.(runtime\.)?low: [0-9]+" "battery\.runtime: [0-9]+" "battery\.voltage: [0-9.]+" "battery\.voltage\.nominal: [0-9]+" "input\.voltage\.nominal: [0-9.]+" "input\.voltage: [0-9.]+" "ups\.load: [0-9.]+" "ups\.status: [A-Z\ ]+"
do
	OUT=$(echo $TMP | grep -Eo "$value" | awk '{for (i=2; i<NF; i++) printf $i " "; print $NF}' | LANG=C sort | head -n 1)
	if [ -n "$OUT" ]; then
		echo $OUT
	else
		echo "Unknown"
	fi
done
