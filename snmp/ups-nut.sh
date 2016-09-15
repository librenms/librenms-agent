#!/usr/bin/env bash
################################################################
# copy this script to /etc/snmp/ and make it executable:       #
# chmod +x ups-nut.sh                                          #
# ------------------------------------------------------------ #
# edit your snmpd.conf and include:                            #
# extend ups-nut /etc/snmp/ups-nut.sh                          #
#--------------------------------------------------------------#
# restart snmpd and activate the app for desired host          #
#--------------------------------------------------------------#
# please make sure you have the path/binaries below            #
################################################################
BIN_UPSC='/usr/bin/upsc'
UPSC_CMD='APCUPS'
BIN_CAT='/usr/bin/cat'
BIN_GREP='/usr/bin/grep'
BIN_TR='/usr/bin/tr'
BIN_CUT='/usr/bin/cut'
################################################################
# Don't change anything unless you know what are you doing     #
################################################################
TMP=`$BIN_UPSC $UPSC_CMD 2>/dev/null`

for value in "battery.charge:[0-9]+" "battery.runtime:[0-9]+" "battery.voltage:[0-9.]+" "device.model:[a-zA-Z0-9]+" "device.serial:[a-zA-Z0-9]+" "battery.voltage.nominal:[0-9]+" "input.voltage.nominal:[0-9.]+" "input.voltage:[0-9.]+" "ups.load:[0-9]+" 
do
	OUT=`echo "$TMP" | $BIN_TR -d ' ' | $BIN_GREP -Eow $value | $BIN_CUT -d ":" -f 2`
	if [ -n "$OUT" ]; then
		echo $OUT
	else
		echo "Unknown"
	fi
done
