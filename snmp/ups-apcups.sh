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
exists_command()
{
  command -v "$1" >/dev/null 2>&1
}
require_commands=("apcaccess" "tr" "cut" "grep") ;

for i in "${require_commands[@]}" ;
do
    if exists_command $i; then
        eval "BIN_${i^^}"="$(command -v $i)";
    else
        echo "Your system does not have [$i]";
        exit
    fi

done ;


################################################################
# Don't change anything unless you know what are you doing     #
################################################################
TMP=`$BIN_APCACCESS 2>/dev/null`

for value in "LINEV:[0-9]+" "LOADPCT:[0-9.]+" "BCHARGE:[0-9.]+" "TIMELEFT:[0-9.]+" "^BATTV:[0-9.]+" "NOMINV:[0-9]+" "NOMBATTV:[0-9.]+"
do
        OUT=`echo "$TMP" | $BIN_TR -d ' ' | $BIN_GREP -Eo $value | $BIN_CUT -d ":" -f 2`
        if [ -n "$OUT" ]; then
                echo $OUT
        else
                echo "Unknown"
        fi
done
