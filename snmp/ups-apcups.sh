#!/usr/bin/env bash
################################################################
# copy this script to /etc/snmp/ and make it executable:       #
# chmod +x /etc/snmp/ups-apcups.sh                             #
# ------------------------------------------------------------ #
# edit your snmpd.conf and include:                            #
# extend ups-apcups /etc/snmp/ups-apcups.sh                    #
#--------------------------------------------------------------#
# restart snmpd and activate the app for desired host          #
#--------------------------------------------------------------#
# please make sure you have the path/binaries below            #
################################################################
BIN_APCS='/sbin/apcaccess'
BIN_TR='/usr/bin/tr'
BIN_CUT='/usr/bin/cut'
BIN_GREP='/usr/bin/grep'
################################################################
# Don't change anything unless you know what are you doing     #
################################################################
TMP=$($BIN_APCS 2>/dev/null)

for value in "^LINEV:[0-9]+" "LOADPCT:[0-9.]+" "BCHARGE:[0-9.]+" "TIMELEFT:[0-9.]+" "^BATTV:[0-9.]+" "NOMINV:[0-9]+" "NOMBATTV:[0-9.]+"
do
        OUT=$(echo "$TMP" | $BIN_TR -d ' ' | $BIN_GREP -Eo "$value" | $BIN_CUT -d ":" -f 2)
        if [ -n "$OUT" ]; then
                echo "$OUT"
        else
                echo "Unknown"
        fi
done
