#!/usr/bin/env bash

# This script is deisigned to extract statistical information
# from ntpd for use with LibreNMS.
#
# Tested on Rasbian 8 with ntp 4.2.6p5 but should work with newer versions
#
# Copyright (C) 2017 Simon Mott <me@simonmott.co.uk>
#
# Inspired by original libre-nms agent script by https://github.com/crcro

################################################################
# copy this script to somewhere like /opt and make chmod +x it #
# edit your snmpd.conf and include                             #
# extend ntp-server /opt/ntp-server.sh                         #
# restart snmpd and activate the app for desired host          #
# please make sure you have the path/binaries below            #
################################################################
# Binaries and paths required                                  #
################################################################

# Lets define some required binaries
# These can be hard coded, but using "which" to make compatable with other distros
BIN_NTPQ=`which ntpq`
BIN_NTPDC=`which ntpdc`
BIN_GREP=`which grep`
BIN_CUT=`which cut`
BIN_SED=`which sed`
BIN_HEAD=`which head`

# Below is a list of fields that LibreNMS currently expects from the poller and in which order
#    'stratum'        => $stratum,
#    'offset'         => $offset,
#    'frequency'      => $frequency,
#    'jitter'         => $jitter,
#    'noise'          => $noise,
#    'stability'      => $stability,
#    'uptime'         => $uptime,
#    'buffer_recv'    => $buffer_recv,
#    'buffer_free'    => $buffer_free,
#    'buffer_used'    => $buffer_used,
#    'packets_drop'   => $packets_drop,
#    'packets_ignore' => $packets_ignore,
#    'packets_recv'   => $packets_recv,
#    'packets_sent'   => $packets_sent,

# capture ntpq output
NTPQ_OUTPUT=`$BIN_NTPQ -c rv`

NTP_STRATUM=`echo $NTPQ_OUTPUT | $BIN_GREP -Eow "stratum=[0-9]+" | $BIN_CUT -d "=" -f 2`
NTP_OFFSET=`echo $NTPQ_OUTPUT | $BIN_GREP -Eow "offset=(\-)?[0-9]+\.[0-9]+" | $BIN_CUT -d "=" -f 2`
NTP_FREQUENCY=`echo $NTPQ_OUTPUT | $BIN_GREP -Eow "frequency=(\-)?[0-9]+\.[0-9]+" | $BIN_CUT -d "=" -f 2`
NTP_JITTER=`echo $NTPQ_OUTPUT | $BIN_GREP -Eow "sys_jitter=(\-)?[0-9]+\.[0-9]+" | $BIN_CUT -d "=" -f 2`
NTP_NOISE=`echo $NTPQ_OUTPUT | $BIN_GREP -Eow "clk_jitter=(\-)?[0-9]+\.[0-9]+" | $BIN_CUT -d "=" -f 2`
NTP_STABILITY=`echo $NTPQ_OUTPUT | $BIN_GREP -Eow "clk_wander=(\-)?[0-9]+\.[0-9]+" | $BIN_CUT -d "=" -f 2`

# ntp iostats

# Old script looked for a specific version to indicate which command we should use
# Lets do the same because I dont know any better :)
NTP_VER=`echo $NTPQ_OUTPUT | $BIN_GREP -Eowc "version=.*4\.2\.6p5"`

if [ $NTP_VER -eq 1 ]; then
        # Version string contains 4.2.6p5...
        NTP_IO_OUTPUT=`$BIN_NTPDC -c iostats`
else
        NTP_IO_OUTPUT=`$BIN_NTPQ -c iostats localhost`
fi

# Lets make the output easier to work with
# bash has already formatted this for us so
# there is a single space between : and the value
#
# So lets remove that space so we dont need
# to worry about spaces later
NTP_IO_OUTPUT=`echo $NTP_IO_OUTPUT | $BIN_SED 's/: /:/g'`

NTP_UPTIME=`echo $NTP_IO_OUTPUT | $BIN_GREP -Eow "time since reset:[0-9]+" | $BIN_CUT -d ":" -f 2`
NTP_BUF_RX=`echo $NTP_IO_OUTPUT | $BIN_GREP -Eow "receive buffers:[0-9]+" | $BIN_HEAD -1 | $BIN_CUT -d ":" -f 2`
NTP_BUF_FREE=`echo $NTP_IO_OUTPUT | $BIN_GREP -Eow "free receive buffers:[0-9]+" | $BIN_CUT -d ":" -f 2`
NTP_BUF_USED=`echo $NTP_IO_OUTPUT | $BIN_GREP -Eow "used receive buffers:[0-9]+" | $BIN_CUT -d ":" -f 2`
NTP_PKT_DROP=`echo $NTP_IO_OUTPUT | $BIN_GREP -Eow "dropped packets:[0-9]+" | $BIN_CUT -d ":" -f 2`
NTP_PKT_IGN=`echo $NTP_IO_OUTPUT | $BIN_GREP -Eow "ignored packets:[0-9]+" | $BIN_CUT -d ":" -f 2`
NTP_PKT_RX=`echo $NTP_IO_OUTPUT | $BIN_GREP -Eow "received packets:[0-9]+" | $BIN_CUT -d ":" -f 2`
NTP_PKT_TX=`echo $NTP_IO_OUTPUT | $BIN_GREP -Eow "packets sent:[0-9]+" | $BIN_CUT -d ":" -f 2`

# Do the needful

echo $NTP_STRATUM
echo $NTP_OFFSET
echo $NTP_FREQUENCY
echo $NTP_JITTER
echo $NTP_NOISE
echo $NTP_STABILITY
echo $NTP_UPTIME
echo $NTP_BUF_RX
echo $NTP_BUF_FREE
echo $NTP_BUF_USED
echo $NTP_PKT_DROP
echo $NTP_PKT_IGN
echo $NTP_PKT_RX
echo $NTP_PKT_TX
