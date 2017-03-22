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
# extend ntp-client /opt/ntp-client.sh                         #
# restart snmpd and activate the app for desired host          #
# please make sure you have the path/binaries below            #
################################################################
# Binaries and paths required                                  #
################################################################

# Lets define some required binaries
# These can be hard coded, but using "which" to make compatable with other distros
BIN_NTPQ=`which ntpq`
BIN_GREP=`which grep`
BIN_CUT=`which cut`

# Below is a list of fields that LibreNMS currently expects from the poller and in which order
#    'offset' => $offset,
#    'frequency' => $frequency,
#    'jitter' => $jitter,
#    'noise' => $noise,
#    'stability' => $stability,

# capture ntpq output
NTPQ_OUTPUT=`$BIN_NTPQ -c rv`

NTP_OFFSET=`echo $NTPQ_OUTPUT | $BIN_GREP -Eow "offset=(\-)?[0-9]+\.[0-9]+" | $BIN_CUT -d "=" -f 2`
NTP_FREQUENCY=`echo $NTPQ_OUTPUT | $BIN_GREP -Eow "frequency=(\-)?[0-9]+\.[0-9]+" | $BIN_CUT -d "=" -f 2`
NTP_JITTER=`echo $NTPQ_OUTPUT | $BIN_GREP -Eow "sys_jitter=(\-)?[0-9]+\.[0-9]+" | $BIN_CUT -d "=" -f 2`
NTP_NOISE=`echo $NTPQ_OUTPUT | $BIN_GREP -Eow "clk_jitter=(\-)?[0-9]+\.[0-9]+" | $BIN_CUT -d "=" -f 2`
NTP_STABILITY=`echo $NTPQ_OUTPUT | $BIN_GREP -Eow "clk_wander=(\-)?[0-9]+\.[0-9]+" | $BIN_CUT -d "=" -f 2`

# Do the needful

echo $NTP_OFFSET
echo $NTP_FREQUENCY
echo $NTP_JITTER
echo $NTP_NOISE
echo $NTP_STABILITY
