#!/usr/bin/env bash
################################################################
# copy this script to somewhere like /opt and make chmod +x it #
# edit your snmpd.conf and include                             #
# extend ups-apcups /opt/ups-apcups.sh                         #
# restart snmpd and activate the app for desired host          #
# please make sure you have the path/binaries below            #
################################################################
# Binaries and paths required                                  #
################################################################ 
BIN_APCS='/sbin/apcaccess'
BIN_TR='/usr/bin/tr'
BIN_CUT='/usr/bin/cut'
BIN_SED='/usr/bin/sed'
################################################################
# Don't change anything unless you know what are you doing     #
################################################################
CMD1=`$BIN_APCS | $BIN_TR '\n' '|'`
IFS='|' read -r -a array <<< "$CMD1"

for value in 11 12 13 14 22 33 34
do
   echo ${array["$value"]} | $BIN_CUT -d ":" -f 2 | $BIN_SED -e 's/[^0-9.]*//g' | $BIN_SED -e 's/^[ \t]*//'
done

for value in 9 31 
do
   echo ${array["$value"]} | $BIN_CUT -d ":" -f 2 | $BIN_SED 's/ *$//' | $BIN_SED -e 's/^[ \t]*//'
done
