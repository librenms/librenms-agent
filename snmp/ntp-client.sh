#!/bin/sh
################################################################
# copy this script to somewhere like /opt and make chmod +x it #
# edit your snmpd.conf and include                             #
# extend ntp-client /opt/ntp-client.sh                         #
# restart snmpd and activate the app for desired host          #
# please make sure you have the path/binaries below            #
################################################################
# Binaries and paths required, please correct before using.    #
################################################################
BIN_NTPQ="/usr/bin/env ntpq"
BIN_GREP="/usr/bin/env grep"
BIN_TR="/usr/bin/env tr"
BIN_SED="/usr/bin/env sed"
################################################################
# Don't change anything unless you know what are you doing     #
################################################################
$BIN_NTPQ -c rv | $BIN_GREP jitter | $BIN_SED 's/[[:alpha:]=,_]/ /g' | $BIN_SED 's/^\ *[0-9]\ *//;' | $BIN_SED 's/\ \ */ /g' | $BIN_SED 's/\ $//' | $BIN_TR ' ' '\n'
