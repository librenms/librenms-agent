#!/usr/bin/env bash
################################################################
# copy this script to somewhere like /opt and make chmod +x it #
# edit your snmpd.conf and include                             #
# extend ntpdserver /opt/ntp-server.sh                         #
# restart snmpd and activate the app for desired host          #
# please make sure you have the path/binaries below            #
################################################################
# Binaries and paths required                                  #
################################################################ 
BIN_NTPQ='/usr/sbin/ntpq'
BIN_GREP='/usr/bin/grep'
BIN_TR='/usr/bin/tr'
BIN_CUT='/usr/bin/cut'
BIN_SED='/usr/bin/sed'
################################################################
# Don't change anything unless you know what are you doing     #
################################################################
CMD0=`$BIN_NTPQ -c rv | $BIN_GREP -Eow "stratum=[0-9]+" | $BIN_CUT -d "=" -f 2`
echo $CMD0

CMD1=`$BIN_NTPQ -c rv | $BIN_GREP 'jitter' | $BIN_TR '\n' ' '`
IFS=', ' read -r -a array <<< "$CMD1"

for value in 2 3 4 5 6
do
	echo ${array["$value"]} | $BIN_CUT -d "=" -f 2
done

CMD2=`$BIN_NTPQ -c iostats localhost | $BIN_TR -d ' ' | $BIN_TR '\n' ','`
IFS=',' read -r -a array <<< "$CMD2"

for value in 0 1 2 3 5 6 7 8
do
    echo ${array["$value"]} | $BIN_SED -e 's/[^0-9]/ /g' -e 's/^ *//g' -e 's/ *$//g'
done
