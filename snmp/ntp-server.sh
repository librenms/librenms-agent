#!/bin/sh
# Please make sure the paths below are correct.
# Alternatively you can put them in $0.conf, meaning if you've named
# this script ntp-client.sh then it must go in ntp-client.sh.conf .
#
# NTPQV output version of "ntpq -c rv"
# p1 DD-WRT and some other outdated linux distros
# p11 FreeBSD 11 and any linux distro that is up to date
#
# If you are unsure, which to set, run this script and make sure that
# the JSON output variables match that in "ntpq -c rv".
#

CONFIGFILE=/etc/snmp/ntp-server.conf

BIN_ENV='/usr/bin/env'

if [ -f $CONFIGFILE ] ; then
	# shellcheck disable=SC1090
	. $CONFIGFILE
fi

BIN_NTPD="$BIN_ENV ntpd"
BIN_NTPQ="$BIN_ENV ntpq"
BIN_NTPDC="$BIN_ENV ntpdc"
BIN_GREP="$BIN_ENV grep"
BIN_TR="$BIN_ENV tr"
BIN_CUT="$BIN_ENV cut"
BIN_SED="$BIN_ENV sed"
BIN_AWK="$BIN_ENV awk"

NTPQV="p11"
################################################################
# Don't change anything unless you know what are you doing     #
################################################################
CONFIG=$0".conf"
if [ -f "$CONFIG" ]; then
	# shellcheck disable=SC1090
	. "$CONFIG"
fi
VERSION=1

STRATUM=$($BIN_NTPQ -c rv | $BIN_GREP -Eow "stratum=[0-9]+" | $BIN_CUT -d "=" -f 2)

# parse the ntpq info that requires version specific info
NTPQ_RAW=$($BIN_NTPQ -c rv | $BIN_GREP jitter | $BIN_SED 's/[[:alpha:]=,_]/ /g')
if [ $NTPQV = "p11" ]; then
	# shellcheck disable=SC2086
	OFFSET=$(echo $NTPQ_RAW | $BIN_AWK -F ' ' '{print $3}')
	# shellcheck disable=SC2086
	FREQUENCY=$(echo $NTPQ_RAW | $BIN_AWK -F ' ' '{print $4}')
	# shellcheck disable=SC2086
	SYS_JITTER=$(echo $NTPQ_RAW | $BIN_AWK -F ' ' '{print $5}')
	# shellcheck disable=SC2086
	CLK_JITTER=$(echo $NTPQ_RAW | $BIN_AWK -F ' ' '{print $6}')
	# shellcheck disable=SC2086
	CLK_WANDER=$(echo $NTPQ_RAW | $BIN_AWK -F ' ' '{print $7}')
fi
if [ $NTPQV = "p1" ]; then
	# shellcheck disable=SC2086
	OFFSET=$(echo $NTPQ_RAW | $BIN_AWK -F ' ' '{print $2}')
	# shellcheck disable=SC2086
	FREQUENCY=$(echo $NTPQ_RAW | $BIN_AWK -F ' ' '{print $3}')
	# shellcheck disable=SC2086
	SYS_JITTER=$(echo $NTPQ_RAW | $BIN_AWK -F ' ' '{print $4}')
	# shellcheck disable=SC2086
	CLK_JITTER=$(echo $NTPQ_RAW | $BIN_AWK -F ' ' '{print $5}')
	# shellcheck disable=SC2086
	CLK_WANDER=$(echo $NTPQ_RAW | $BIN_AWK -F ' ' '{print $6}')
fi

VER=$($BIN_NTPD --version 2>&1 | cut -d\  -f 2  | head -n 1)
if [ "$VER" = "4.2.6p5" ]; then
  USECMD=$(echo "$BIN_NTPDC" -c iostats 127.0.0.1)
else
  USECMD=$(echo "$BIN_NTPQ" -c iostats 127.0.0.1)
fi
CMD2=$($USECMD 2>/dev/null | $BIN_TR -d ' ' | $BIN_CUT -d : -f 2 | $BIN_TR '\n' ' ')

# shellcheck disable=SC2086
TIMESINCERESET=$(echo $CMD2 | $BIN_AWK -F ' ' '{print $1}')
# shellcheck disable=SC2086
RECEIVEDBUFFERS=$(echo $CMD2 | $BIN_AWK -F ' ' '{print $2}')
# shellcheck disable=SC2086
FREERECEIVEBUFFERS=$(echo $CMD2 | $BIN_AWK -F ' ' '{print $3}')
# shellcheck disable=SC2086
USEDRECEIVEBUFFERS=$(echo $CMD2 | $BIN_AWK -F ' ' '{print $4}')
# shellcheck disable=SC2086
LOWWATERREFILLS=$(echo $CMD2 | $BIN_AWK -F ' ' '{print $5}')
# shellcheck disable=SC2086
DROPPEDPACKETS=$(echo $CMD2 | $BIN_AWK -F ' ' '{print $6}')
# shellcheck disable=SC2086
IGNOREDPACKETS=$(echo $CMD2 | $BIN_AWK -F ' ' '{print $7}')
# shellcheck disable=SC2086
RECEIVEDPACKETS=$(echo $CMD2 | $BIN_AWK -F ' ' '{print $8}')
# shellcheck disable=SC2086
PACKETSSENT=$(echo $CMD2 | $BIN_AWK -F ' ' '{print $9}')
# shellcheck disable=SC2086
PACKETSENDFAILURES=$(echo $CMD2 | $BIN_AWK -F ' ' '{print $10}')
#INPUTWAKEUPS=$(echo $CMD2 | $BIN_AWK -F ' ' '{print $11}')
# shellcheck disable=SC2086
USEFULINPUTWAKEUPS=$(echo $CMD2 | $BIN_AWK -F ' ' '{print $12}')

echo '{"data":{"offset":"'"$OFFSET"\
'","frequency":"'"$FREQUENCY"\
'","sys_jitter":"'"$SYS_JITTER"\
'","clk_jitter":"'"$CLK_JITTER"\
'","clk_wander":"'"$CLK_WANDER"\
'","stratum":"'"$STRATUM"\
'","time_since_reset":"'"$TIMESINCERESET"\
'","receive_buffers":"'"$RECEIVEDBUFFERS"\
'","free_receive_buffers":"'"$FREERECEIVEBUFFERS"\
'","used_receive_buffers":"'"$USEDRECEIVEBUFFERS"\
'","low_water_refills":"'"$LOWWATERREFILLS"\
'","dropped_packets":"'"$DROPPEDPACKETS"\
'","ignored_packets":"'"$IGNOREDPACKETS"\
'","received_packets":"'"$RECEIVEDPACKETS"\
'","packets_sent":"'"$PACKETSSENT"\
'","packet_send_failures":"'"$PACKETSENDFAILURES"\
'","input_wakeups":"'"$PACKETSENDFAILURES"\
'","useful_input_wakeups":"'"$USEFULINPUTWAKEUPS"\
'"},"error":"0","errorString":"","version":"'$VERSION'"}'
