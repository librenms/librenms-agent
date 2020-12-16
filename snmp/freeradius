#!/usr/bin/env sh

CONFIG_FILE=/etc/snmp/freeradius.conf
METRICS_MATCH_FILE=/etc/snmp/freeradius.sed

# Set 0 for SNMP extend; set to 1 for Check_MK agent
AGENT=0

# Set FreeRADIUS status_server details
RADIUS_SERVER='localhost'
RADIUS_PORT='18121'
RADIUS_KEY='adminsecret'

# Override any of the above settings from optional config file
if [ -f $CONFIG_FILE ]; then
    . $CONFIG_FILE
fi

# Default radclient access request, shouldn't need to be changed
RADIUS_STATUS_CMD='Message-Authenticator = 0x00, FreeRADIUS-Statistics-Type = 31, Response-Packet-Type = Access-Accept'

# Paths for executables, should work if within PATH
BIN_RADCLIENT="$(command -v radclient)"
BIN_SED="$(command -v sed)"

if [ $AGENT == 1 ]; then
  echo "<<<freeradius>>>"
fi

RESULT=$(echo "$RADIUS_STATUS_CMD" | $BIN_RADCLIENT -x $RADIUS_SERVER:$RADIUS_PORT status $RADIUS_KEY)

# Extract only the desired metrics from the radclient result
# Order of metrics will remain as returned by radclient
echo "$RESULT" | $BIN_SED -n -f $METRICS_MATCH_FILE
