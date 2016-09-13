#!/usr/bin/env bash
################################################################
# copy this script to somewhere like /opt and make chmod +x it #
# edit your snmpd.conf and include                             #
# extend ups-nut /opt/ups-nut.sh                               #
# restart snmpd and activate the app for desired host          #
# please make sure you have the path/binaries below            #
################################################################
# Binaries and paths required                                  #
################################################################ 
BIN_UPSC='/usr/bin/upsc'
UPSC_CMD='APCUPS'
BIN_SED='/usr/bin/sed'
BIN_TR='/usr/bin/tr'
BIN_CUT='/usr/bin/cut'
################################################################
# Don't change anything unless you know what are you doing     #
################################################################
CMD1=`$BIN_UPSC $UPSC_CMD | $BIN_SED "1 d" | $BIN_TR '\n' '|' | $BIN_TR -d ' '`
IFS='|' read -r -a array <<< "$CMD1"

for value in 0 1 5 8 11 12 25 26 31
do
   echo ${array["$value"]} | $BIN_CUT -d ":" -f 2
done
