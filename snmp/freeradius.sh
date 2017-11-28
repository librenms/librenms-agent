#!/usr/bin/env bash

# Set 0 for SNMP extend; set to 1 for Check_MK agent
AGENT=0

# Set FreeRADIUS status_server details
RADIUS_SERVER='localhost'
RADIUS_PORT='18121'
RADIUS_KEY='adminsecret'

# Default radclient access request, shouldn't need to be changed
RADIUS_STATUS_CMD='Message-Authenticator = 0x00, FreeRADIUS-Statistics-Type = 31, Response-Packet-Type = Access-Accept'

# Pathes for grep and radclient executables, should work if within PATH
BIN_GREP="$(command -v grep)"
BIN_RADCLIENT="$(command -v radclient)"

if [ $AGENT == 1 ]; then
  echo "<<<freeradius>>>"
fi

RESULT=`echo "$RADIUS_STATUS_CMD" | $BIN_RADCLIENT -x $RADIUS_SERVER:$RADIUS_PORT status $RADIUS_KEY`

ACCESS_REQ=`echo $RESULT | grep -o 'FreeRADIUS-Total-Access-Requests = [[:digit:]]*'`
ACCESS_ACC=`echo $RESULT | grep -o 'FreeRADIUS-Total-Access-Accepts = [[:digit:]]*'`
ACCESS_REJ=`echo $RESULT | grep -o 'FreeRADIUS-Total-Access-Rejects = [[:digit:]]*'`
ACCESS_CHL=`echo $RESULT | grep -o 'FreeRADIUS-Total-Access-Challenges = [[:digit:]]*'`
AUTH_RES=`echo $RESULT | grep -o 'FreeRADIUS-Total-Auth-Responses = [[:digit:]]*'`
AUTH_DUP=`echo $RESULT | grep -o 'FreeRADIUS-Total-Auth-Duplicate-Requests = [[:digit:]]*'`
AUTH_MAL=`echo $RESULT | grep -o 'FreeRADIUS-Total-Auth-Malformed-Requests = [[:digit:]]*'`
AUTH_INV=`echo $RESULT | grep -o 'FreeRADIUS-Total-Auth-Invalid-Requests = [[:digit:]]*'`
AUTH_DRP=`echo $RESULT | grep -o 'FreeRADIUS-Total-Auth-Dropped-Requests = [[:digit:]]*'`
AUTH_UNK=`echo $RESULT | grep -o 'FreeRADIUS-Total-Auth-Unknown-Types = [[:digit:]]*'`
ACCT_REQ=`echo $RESULT | grep -o 'FreeRADIUS-Total-Accounting-Requests = [[:digit:]]*'`
ACCT_RES=`echo $RESULT | grep -o 'FreeRADIUS-Total-Accounting-Responses = [[:digit:]]*'`
ACCT_DUP=`echo $RESULT | grep -o 'FreeRADIUS-Total-Acct-Duplicate-Requests = [[:digit:]]*'`
ACCT_MAL=`echo $RESULT | grep -o 'FreeRADIUS-Total-Acct-Malformed-Requests = [[:digit:]]*'`
ACCT_INV=`echo $RESULT | grep -o 'FreeRADIUS-Total-Acct-Invalid-Requests = [[:digit:]]*'`
ACCT_DRP=`echo $RESULT | grep -o 'FreeRADIUS-Total-Acct-Dropped-Requests = [[:digit:]]*'`
ACCT_UNK=`echo $RESULT | grep -o 'FreeRADIUS-Total-Acct-Unknown-Types = [[:digit:]]*'`
PROXY_ACCESS_REQ=`echo $RESULT | grep -o 'FreeRADIUS-Total-Proxy-Access-Requests = [[:digit:]]*'`
PROXY_ACCESS_ACC=`echo $RESULT | grep -o 'FreeRADIUS-Total-Proxy-Access-Accepts = [[:digit:]]*'`
PROXY_ACCESS_REJ=`echo $RESULT | grep -o 'FreeRADIUS-Total-Proxy-Access-Rejects = [[:digit:]]*'`
PROXY_ACCESS_CHL=`echo $RESULT | grep -o 'FreeRADIUS-Total-Proxy-Access-Challenges = [[:digit:]]*'`
PROXY_AUTH_RES=`echo $RESULT | grep -o 'FreeRADIUS-Total-Proxy-Auth-Responses = [[:digit:]]*'`
PROXY_AUTH_DUP=`echo $RESULT | grep -o 'FreeRADIUS-Total-Proxy-Auth-Duplicate-Requests = [[:digit:]]*'`
PROXY_AUTH_MAL=`echo $RESULT | grep -o 'FreeRADIUS-Total-Proxy-Auth-Malformed-Requests = [[:digit:]]*'`
PROXY_AUTH_INV=`echo $RESULT | grep -o 'FreeRADIUS-Total-Proxy-Auth-Invalid-Requests = [[:digit:]]*'`
PROXY_AUTH_DRP=`echo $RESULT | grep -o 'FreeRADIUS-Total-Proxy-Auth-Dropped-Requests = [[:digit:]]*'`
PROXY_AUTH_UNK=`echo $RESULT | grep -o 'FreeRADIUS-Total-Proxy-Auth-Unknown-Types = [[:digit:]]*'`
PROXY_ACCT_REQ=`echo $RESULT | grep -o 'FreeRADIUS-Total-Proxy-Accounting-Requests = [[:digit:]]*'`
PROXY_ACCT_RES=`echo $RESULT | grep -o 'FreeRADIUS-Total-Proxy-Accounting-Responses = [[:digit:]]*'`
PROXY_ACCT_DUP=`echo $RESULT | grep -o 'FreeRADIUS-Total-Proxy-Acct-Duplicate-Requests = [[:digit:]]*'`
PROXY_ACCT_MAL=`echo $RESULT | grep -o 'FreeRADIUS-Total-Proxy-Acct-Malformed-Requests = [[:digit:]]*'`
PROXY_ACCT_INV=`echo $RESULT | grep -o 'FreeRADIUS-Total-Proxy-Acct-Invalid-Requests = [[:digit:]]*'`
PROXY_ACCT_DRP=`echo $RESULT | grep -o 'FreeRADIUS-Total-Proxy-Acct-Dropped-Requests = [[:digit:]]*'`
PROXY_ACCT_UNK=`echo $RESULT | grep -o 'FreeRADIUS-Total-Proxy-Acct-Unknown-Types = [[:digit:]]*'`
QUE_INT=`echo $RESULT | grep -o 'FreeRADIUS-Queue-Len-Internal = [[:digit:]]*'`
QUE_PROX=`echo $RESULT | grep -o 'FreeRADIUS-Queue-Len-Proxy = [[:digit:]]*'`
QUE_AUTH=`echo $RESULT | grep -o 'FreeRADIUS-Queue-Len-Auth = [[:digit:]]*'`
QUE_ACCT=`echo $RESULT | grep -o 'FreeRADIUS-Queue-Len-Acct = [[:digit:]]*'`
QUE_DETL=`echo $RESULT | grep -o 'FreeRADIUS-Queue-Len-Detail = [[:digit:]]*'`
QUE_PPSI=`echo $RESULT | grep -o 'FreeRADIUS-Queue-PPS-In = [[:digit:]]*'`
QUE_PPSO=`echo $RESULT | grep -o 'FreeRADIUS-Queue-PPS-Out = [[:digit:]]*'`

if [ ${#ACCESS_REQ} -le 20 ]; then ACCESS_REQ='FreeRADIUS-Total-Access-Requests = 0'; fi
if [ ${#ACCESS_ACC} -le 20 ]; then ACCESS_ACC='FreeRADIUS-Total-Access-Accepts = 0'; fi
if [ ${#ACCESS_REJ} -le 20 ]; then ACCESS_REJ='FreeRADIUS-Total-Access-Rejects = 0'; fi
if [ ${#ACCESS_CHL} -le 20 ]; then ACCESS_CHL='FreeRADIUS-Total-Access-Challenges = 0'; fi
if [ ${#AUTH_RES} -le 20 ]; then AUTH_RES='FreeRADIUS-Total-Auth-Responses = 0'; fi
if [ ${#AUTH_DUP} -le 20 ]; then AUTH_DUP='FreeRADIUS-Total-Auth-Duplicate-Requests = 0'; fi
if [ ${#AUTH_MAL} -le 20 ]; then AUTH_MAL='FreeRADIUS-Total-Auth-Malformed-Requests = 0'; fi
if [ ${#AUTH_INV} -le 20 ]; then AUTH_INV='FreeRADIUS-Total-Auth-Invalid-Requests = 0'; fi
if [ ${#AUTH_DRP} -le 20 ]; then AUTH_DRP='FreeRADIUS-Total-Auth-Dropped-Requests = 0'; fi
if [ ${#AUTH_UNK} -le 20 ]; then AUTH_UNK='FreeRADIUS-Total-Auth-Unknown-Types = 0'; fi
if [ ${#PROXY_ACCESS_REQ} -le 20 ]; then PROXY_ACCESS_REQ='FreeRADIUS-Total-Proxy-Access-Requests = 0'; fi
if [ ${#PROXY_ACCESS_ACC} -le 20 ]; then PROXY_ACCESS_ACC='FreeRADIUS-Total-Proxy-Access-Accepts = 0'; fi
if [ ${#PROXY_ACCESS_REJ} -le 20 ]; then PROXY_ACCESS_REJ='FreeRADIUS-Total-Proxy-Access-Rejects = 0'; fi
if [ ${#PROXY_ACCESS_CHL} -le 20 ]; then PROXY_ACCESS_CHL='FreeRADIUS-Total-Proxy-Access-Challenges = 0'; fi
if [ ${#PROXY_AUTH_RES} -le 20 ]; then PROXY_AUTH_RES='FreeRADIUS-Total-Proxy-Auth-Responses = 0'; fi
if [ ${#PROXY_AUTH_DUP} -le 20 ]; then PROXY_AUTH_DUP='FreeRADIUS-Total-Proxy-Auth-Duplicate-Requests = 0'; fi
if [ ${#PROXY_AUTH_MAL} -le 20 ]; then PROXY_AUTH_MAL='FreeRADIUS-Total-Proxy-Auth-Malformed-Requests = 0'; fi
if [ ${#PROXY_AUTH_INV} -le 20 ]; then PROXY_AUTH_INV='FreeRADIUS-Total-Proxy-Auth-Invalid-Requests = 0'; fi
if [ ${#PROXY_AUTH_DRP} -le 20 ]; then PROXY_AUTH_DRP='FreeRADIUS-Total-Proxy-Auth-Dropped-Requests = 0'; fi
if [ ${#PROXY_AUTH_UNK} -le 20 ]; then PROXY_AUTH_UNK='FreeRADIUS-Total-Proxy-Auth-Unknown-Types = 0'; fi
if [ ${#PROXY_ACCT_REQ} -le 20 ]; then PROXY_ACCT_REQ='FreeRADIUS-Total-Proxy-Accounting-Requests = 0'; fi
if [ ${#PROXY_ACCT_RES} -le 20 ]; then PROXY_ACCT_RES='FreeRADIUS-Total-Proxy-Accounting-Responses = 0'; fi
if [ ${#PROXY_ACCT_DUP} -le 20 ]; then PROXY_ACCT_DUP='FreeRADIUS-Total-Proxy-Acct-Duplicate-Requests = 0'; fi
if [ ${#PROXY_ACCT_MAL} -le 20 ]; then PROXY_ACCT_MAL='FreeRADIUS-Total-Proxy-Acct-Malformed-Requests = 0'; fi
if [ ${#PROXY_ACCT_INV} -le 20 ]; then PROXY_ACCT_INV='FreeRADIUS-Total-Proxy-Acct-Invalid-Requests = 0'; fi
if [ ${#PROXY_ACCT_DRP} -le 20 ]; then PROXY_ACCT_DRP='FreeRADIUS-Total-Proxy-Acct-Dropped-Requests = 0'; fi
if [ ${#PROXY_ACCT_UNK} -le 20 ]; then PROXY_ACCT_UNK='FreeRADIUS-Total-Proxy-Acct-Unknown-Types = 0'; fi
if [ ${#QUE_INT} -le 20 ]; then QUE_INT='FreeRADIUS-Queue-Len-Internal = 0'; fi
if [ ${#QUE_PROX} -le 20 ]; then QUE_PROX='FreeRADIUS-Queue-Len-Proxy = 0'; fi
if [ ${#QUE_AUTH} -le 20 ]; then QUE_AUTH='FreeRADIUS-Queue-Len-Auth = 0'; fi
if [ ${#QUE_ACCT} -le 20 ]; then QUE_ACCT='FreeRADIUS-Queue-Len-Acct = 0'; fi
if [ ${#QUE_DETL} -le 20 ]; then QUE_DETL='FreeRADIUS-Queue-Len-Detail = 0'; fi
if [ ${#QUE_PPSI} -le 20 ]; then QUE_PPSI='FreeRADIUS-Queue-PPS-In = 0'; fi
if [ ${#QUE_PPSO} -le 20 ]; then QUE_PPSO='FreeRADIUS-Queue-PPS-Out = 0'; fi

echo $ACCESS_REQ
echo $ACCESS_ACC
echo $ACCESS_REJ
echo $ACCESS_CHL
echo $AUTH_RES
echo $AUTH_DUP
echo $AUTH_MAL
echo $AUTH_INV
echo $AUTH_DRP
echo $AUTH_UNK
echo $PROXY_ACCESS_REQ
echo $PROXY_ACCESS_ACC
echo $PROXY_ACCESS_REJ
echo $PROXY_ACCESS_CHL
echo $PROXY_AUTH_RES
echo $PROXY_AUTH_DUP
echo $PROXY_AUTH_MAL
echo $PROXY_AUTH_INV
echo $PROXY_AUTH_DRP
echo $PROXY_AUTH_UNK
echo $PROXY_ACCT_REQ
echo $PROXY_ACCT_RES
echo $PROXY_ACCT_DUP
echo $PROXY_ACCT_MAL
echo $PROXY_ACCT_INV
echo $PROXY_ACCT_DRP
echo $PROXY_ACCT_UNK
echo $QUE_INT
echo $QUE_PROX
echo $QUE_AUTH
echo $QUE_ACCT
echo $QUE_DETL
echo $QUE_PPSI
echo $QUE_PPSO
