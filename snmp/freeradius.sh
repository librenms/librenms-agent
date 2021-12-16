#!/usr/bin/env bash

CONFIGFILE=/etc/snmp/freeradius.conf

# Set 0 for SNMP extend; set to 1 for Check_MK agent
AGENT=0

# Set FreeRADIUS status_server details
RADIUS_SERVER='localhost'
RADIUS_PORT='18121'
RADIUS_KEY='adminsecret'

if [ -f $CONFIGFILE ]; then
    # shellcheck disable=SC1090
    . $CONFIGFILE
fi

# Default radclient access request, shouldn't need to be changed
RADIUS_STATUS_CMD='Message-Authenticator = 0x00, FreeRADIUS-Statistics-Type = 31, Response-Packet-Type = Access-Accept'

# Paths for sed and radclient executables, should work if within PATH
BIN_SED="$(command -v sed)"
BIN_RADCLIENT="$(command -v radclient)"

if [ $AGENT -eq 1 ]; then
  echo "<<<freeradius>>>"
fi

RESULT=$(echo "$RADIUS_STATUS_CMD" | $BIN_RADCLIENT -x $RADIUS_SERVER:$RADIUS_PORT status $RADIUS_KEY)

if [[ $RESULT != *"Received Access-Accept"* ]] ;  then
	# A valid result must contain the match string. Otherwise, verify:
	# - the FreeRADIUS 'status' virtual server is enabled and running
	# - the server, port or key match the 'status' server settings
	echo "invalid result from radclient status request, check server settings"
	exit 1
fi

# Return only those AV pairs expected by the FreeRADIUS app, one per line
# Drop any leading or trailing whitespace
# They may be returned in any order
echo "$RESULT" | $BIN_SED -n \
	-e 's/\s*\(FreeRADIUS-Total-Access-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Access-Accepts = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Access-Rejects = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Access-Challenges = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Auth-Responses = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Auth-Duplicate-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Auth-Malformed-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Auth-Invalid-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Auth-Dropped-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Auth-Unknown-Types = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Accounting-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Accounting-Responses = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Acct-Duplicate-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Acct-Malformed-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Acct-Invalid-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Acct-Dropped-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Acct-Unknown-Types = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Proxy-Access-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Proxy-Access-Accepts = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Proxy-Access-Rejects = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Proxy-Access-Challenges = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Proxy-Auth-Responses = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Proxy-Auth-Duplicate-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Proxy-Auth-Malformed-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Proxy-Auth-Invalid-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Proxy-Auth-Dropped-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Proxy-Auth-Unknown-Types = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Proxy-Accounting-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Proxy-Accounting-Responses = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Proxy-Acct-Duplicate-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Proxy-Acct-Malformed-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Proxy-Acct-Invalid-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Proxy-Acct-Dropped-Requests = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Total-Proxy-Acct-Unknown-Types = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Queue-Len-Internal = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Queue-Len-Proxy = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Queue-Len-Auth = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Queue-Len-Acct = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Queue-Len-Detail = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Queue-PPS-In = [0-9]*\)/\1/p' \
	-e 's/\s*\(FreeRADIUS-Queue-PPS-Out = [0-9]*\)/\1/p'
