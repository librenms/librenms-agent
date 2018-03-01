#!/usr/bin/env bash

# - Copy this script to somewhere (like /opt/ntp-client.sh)
# - Make it executable (chmod +x /opt/ntp-client.sh)
# - Add the following line to your snmpd.conf file
#   extend ntp-client /opt/ntp-client.shh
# - Restart snmpd
#
# Note: Change the path accordingly, if you're not using "/opt/ntp-client.sh"

# You need the following tools to be in your PATH env, adjust accordingly
# - ntpq, sed
PATH=$PATH

NTP_STATUS=$(ntpq -c rv | sed 's/,/ /g')

for i in $NTP_STATUS
do
	export $i 2> /dev/null
done

echo $offset
echo $frequency
echo $sys_jitter
echo $clk_jitter
echo $clk_wander