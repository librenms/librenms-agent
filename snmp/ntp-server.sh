#!/usr/bin/env bash
################################################################
# copy this script to /etc/snmp/ and make it executable:       # 
# chmod +x ntp-server.sh                                       #
# ------------------------------------------------------------ #
# edit your snmpd.conf and include:                            #
# extend ntp-server /etc/snmp/ntp-server.sh                    #
#--------------------------------------------------------------#
# restart snmpd and activate the app for desired host          #
#--------------------------------------------------------------#
# please make sure you have the path/binaries below            #
################################################################ 
BIN_NTPD='/usr/sbin/ntpd'
BIN_NTPQ='/usr/sbin/ntpq'
BIN_NTPDC='/usr/sbin/ntpdc'
BIN_CAT='/usr/bin/cat'
BIN_GREP='/usr/bin/grep'
BIN_TR='/usr/bin/tr'
BIN_CUT='/usr/bin/cut'
################################################################
# Don't change anything unless you know what are you doing     #
################################################################
VER=`$BIN_NTPD --version`
if [[ $VER =~ .*4.2.6p5.* ]]
then
  USECMD=`echo $BIN_NTPDC -c iostats`
else
  USECMD=`echo $BIN_NTPQ -c iostats localhost`
fi

TMP0=`$BIN_NTPQ -c rv`
TMP1=`$USECMD`

for output in "stratum=[0-9]+" "offset=[-0-9.]+" "frequency=[-0-9.]+" "sys_jitter=[0-9.]+" "clk_jitter=[0-9.]+" "clk_wander=[0-9.]+"
do
	echo `echo "$TMP0" | $BIN_GREP -Eow $output | $BIN_CUT -d "=" -f 2`
done

for output in "timesincereset:[0-9]+" "receivebuffers:[0-9]+" "freereceivebuffers:[0-9]+" "usedreceivebuffers:[0-9]+" "droppedpackets:[0-9]+" "ignoredpackets:[0-9]+" "receivedpackets:[0-9]+" "packetssent:[0-9]+"
do
	echo `echo "$TMP1" | $BIN_TR -d ' ' | $BIN_GREP -Eow $output | $BIN_CUT -d ":" -f 2`
done
