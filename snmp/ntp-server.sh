#!/usr/bin/env bash
################################################################
# copy this script to somewhere like /opt and make chmod +x it #
# edit your snmpd.conf and include                             #
# extend ntp-server /opt/ntp-server.sh                         #
# restart snmpd and activate the app for desired host          #
# please make sure you have the path/binaries below            #
################################################################
# Binaries and paths required                                  #
################################################################ 
BIN_NTPD=`/usr/bin/which ntpd`
BIN_NTPQ=`/usr/bin/which ntpq`
BIN_NTPDC=`/usr/bin/which ntpdc`
BIN_GREP=`/usr/bin/which grep`
BIN_TR=`/usr/bin/which tr`
BIN_CUT=`/usr/bin/which cut`
BIN_SED=`/usr/bin/which sed`
################################################################
# Don't change anything unless you know what are you doing     #
################################################################
VER=`$BIN_NTPD --version`

CMD0=`$BIN_NTPQ -c rv | $BIN_GREP -Eow "stratum=[0-9]+" | $BIN_CUT -d "=" -f 2`
echo $CMD0

CMD1=`$BIN_NTPQ -c rv | $BIN_GREP 'jitter' | $BIN_TR '\n' ' '`
IFS=', ' read -r -a array <<< "$CMD1"

for value in 2 3 4 5 6
do
	echo ${array["$value"]} | $BIN_CUT -d "=" -f 2
done

if [[ "$VER" =~ '4.2.6p5' ]]
then
  USECMD=`echo $BIN_NTPDC -c iostats`
else
  USECMD=`echo $BIN_NTPQ -c iostats localhost`
fi
CMD2=`$USECMD | $BIN_TR -d ' ' | $BIN_TR '\n' ','`

IFS=',' read -r -a array <<< "$CMD2"

for value in 0 1 2 3 5 6 7 8
do
    echo ${array["$value"]} | $BIN_SED -e 's/[^0-9]/ /g' -e 's/^ *//g' -e 's/ *$//g'
done
