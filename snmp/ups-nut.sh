#!/bin/sh
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
UPS_NAME="${1:-APCUPS}"

PATH=$PATH:/usr/bin:/bin
TMP=$(upsc $UPS_NAME 2>/dev/null)

for value in "battery\.charge: [0-9.]+" "battery\.(runtime\.)?low: [0-9]+" "battery\.runtime: [0-9]+" "battery\.voltage: [0-9.]+" "battery\.voltage\.nominal: [0-9]+" "input\.voltage\.nominal: [0-9.]+" "input\.voltage: [0-9.]+" "ups\.load: [0-9.]+"
do
	OUT=$(echo "$TMP" | grep -Eo "$value" | awk '{print $2}' | LANG=C sort | head -n 1)
	if [ -n "$OUT" ]; then
		echo "$OUT"
	else
		echo "Unknown"
	fi
done

for value in "ups\.status:[A-Z ]{0,}OL" "ups\.status:[A-Z ]{0,}OB" "ups\.status:[A-Z ]{0,}LB" "ups\.status:[A-Z ]{0,}HB" "ups\.status:[A-Z ]{0,}RB" "ups\.status:[A-Z ]{0,}CHRG" "ups\.status:[A-Z ]{0,}DISCHRG" "ups\.status:[A-Z ]{0,}BYPASS" "ups\.status:[A-Z ]{0,}CAL" "ups\.status:[A-Z ]{0,}OFF" "ups\.status:[A-Z ]{0,}OVER" "ups\.status:[A-Z ]{0,}TRIM" "ups\.status:[A-Z ]{0,}BOOST" "ups\.status:[A-Z ]{0,}FSD" "ups\.alarm:[A-Z ]"
do
    UNKNOWN=$(echo "$TMP" | grep -Eo "ups\.status:")
    if [ -z "$UNKNOWN" ]; then
        echo "Unknown"
    else
        OUT=$(echo "$TMP" | grep -Eo "$value")
        if [ -n "$OUT" ]; then
            echo "1"
        else
            echo "0"
        fi
    fi
done

