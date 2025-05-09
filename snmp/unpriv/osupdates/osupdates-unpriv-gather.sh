#!/bin/bash

SNMP_PERSISTENT_DIR="/var/lib/net-snmp"
UNPRIV_SHARED_FILE="$SNMP_PERSISTENT_DIR/osupdates/stats.txt"

if [ -f "$UNPRIV_SHARED_FILE" ]; then
    cat "$UNPRIV_SHARED_FILE"
else
    echo "0"
    logger -p daemon.error -t "osupdates-unpriv" Reading osupdate data from file "$UNPRIV_SHARED_FILE" failed!
fi
