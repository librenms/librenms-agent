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
BIN_NTPQ='/usr/bin/env ntpq'
BIN_GREP='/usr/bin/env grep'
BIN_SED="/usr/bin/env sed"
BIN_AWK='/usr/bin/env awk'
NTPQV="p11"
################################################################
# Don't change anything unless you know what are you doing     #
################################################################
CONFIG=$0".conf"
if [ -f $CONFIG ]; then
    . $CONFIG
fi
VERSION=1
#error and errorString are hardcoded as if the above fails bad json will be generated
RAW=`$BIN_NTPQ -c rv | $BIN_GREP jitter | $BIN_SED 's/[[:alpha:]=,_]/ /g'`
if [ $NTPQV = "p11" ]; then
    echo $RAW | $BIN_AWK -F ' ' '{print "{\"data\":{\"offset\":\""$3\
                        "\",\"frequency\":\""$4\
                        "\",\"sys_jitter\":\""$5\
                        "\",\"clk_jitter\":\""$6\
                        "\",\"clk_wander\":\""$7\
                        "\"},\"version\":\""'$VERSION'"\",\"error\":\"0\",\"errorString\":\"\"}"
                        }'
    exit 0
fi

if [ $NTPQV = "p1" ]; then
    echo $RAW | $BIN_AWK -F ' ' '{print "{\"data\":{\"offset\":\""$2\
                        "\",\"frequency\":\""$3\
                        "\",\"sys_jitter\":\""$4\
                        "\",\"clk_jitter\":\""$5\
                        "\",\"clk_wander\":\""$6\
                        "\"},\"version\":\""'$VERSION'"\",\"error\":\"0\",\"errorString\":\"\"}"
                        }'
    exit 0
fi
