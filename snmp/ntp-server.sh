#!/usr/bin/env bash

# - Copy this script to somewhere (like /opt/ntp-server.sh)
# - Make it executable (chmod +x /opt/ntp-server.sh)
# - Add the following line to your snmpd.conf file
#   extend ntp-server /opt/ntp-server.sh
# - Restart snmpd
#
# Note: Change the path accordingly, if you're not using "/opt/ntp-server.sh"

# You need the following tools to be in your PATH env, adjust accordingly
# - ntpd, ntpdc (if < v4.2.6p5), ntpq, sed
PATH=$PATH

NTP_STATUS=$(ntpq -c rv | sed 's/,/ /g')

for i in $NTP_STATUS
do
	export $i 2> /dev/null
done

echo $stratum
echo $offset
echo $frequency
echo $sys_jitter
echo $clk_jitter
echo $clk_wander

if [[ $(ntpd --version) =~ '4.2.6p5' ]]
then
  IOSTATS=$(ntpdc -c iostats)
else
  IOSTATS=$(ntpq -c iostats localhost)
fi

IFS=$'\n'
for val in $IOSTATS
do
  export $(echo "$val" | sed 's/: */=/g' | sed 's/ /_/g') 2> /dev/null
done

echo $time_since_reset
echo $receive_buffers
echo $free_receive_buffers
echo $used_receive_buffers
echo $dropped_packets
echo $ignored_packets
echo $received_packets
echo $packets_sent
