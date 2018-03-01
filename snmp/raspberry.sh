#!/usr/bin/env bash

# - Copy this script to somewhere (like /opt/raspberry.sh)
# - Make it executable (chmod +x /opt/raspberry.sh)
# - Add the following line to your snmpd.conf file
#   extend raspberry /opt/raspberry.sh
# - Add the following line to your sudoers file (you can use visudo)
#   snmp ALL=(ALL) NOPASSWD: /opt/raspberry.sh, /usr/bin/vcgencmd*
# - Restart snmpd
#
# Note: Change the path accordingly, if you're not using "/opt/raspberry.sh"

# You need the following tools to be in your PATH env, adjust accordingly
# - sed, sudo, vcgencmd
PATH=$PATH

getTemp='measure_temp'
getVoltsCore='measure_volts core'
getVoltsRamC='measure_volts sdram_c'
getVoltsRamI='measure_volts sdram_i'
getVoltsRamP='measure_volts sdram_p'
getFreqArm='measure_clock arm'
getFreqCore='measure_clock core'
getStatusH264='codec_enabled H264'
getStatusMPG2='codec_enabled MPG2'
getStatusWVC1='codec_enabled WVC1'
getStatusMPG4='codec_enabled MPG4'
getStatusMJPG='codec_enabled MJPG'
getStatusWMV9='codec_enabled WMV9'

sudo vcgencmd $getTemp | sed 's|[^0-9.]||g'
sudo vcgencmd $getVoltsCore | sed 's|[^0-9.]||g'
sudo vcgencmd $getVoltsRamC | sed 's|[^0-9.]||g'
sudo vcgencmd $getVoltsRamI | sed 's|[^0-9.]||g'
sudo vcgencmd $getVoltsRamP | sed 's|[^0-9.]||g'
sudo vcgencmd $getFreqArm  | sed 's/frequency(45)=//g'
sudo vcgencmd $getFreqCore | sed 's/frequency(1)=//g'
sudo vcgencmd $getStatusH264 | sed 's/H264=//g'
sudo vcgencmd $getStatusMPG2 | sed 's/MPG2=//g'
sudo vcgencmd $getStatusWVC1 | sed 's/WVC1=//g'
sudo vcgencmd $getStatusMPG4 | sed 's/MPG4=//g'
sudo vcgencmd $getStatusMJPG | sed 's/MJPG=//g'
sudo vcgencmd $getStatusWMV9 | sed 's/WMV9=//g'
sudo vcgencmd $getStatusH264 | sed 's/enabled/2/g'
sudo vcgencmd $getStatusMPG2 | sed 's/enabled/2/g'
sudo vcgencmd $getStatusWVC1 | sed 's/enabled/2/g'
sudo vcgencmd $getStatusMPG4 | sed 's/enabled/2/g'
sudo vcgencmd $getStatusMJPG | sed 's/enabled/2/g'
sudo vcgencmd $getStatusWMV9 | sed 's/enabled/2/g'
sudo vcgencmd $getStatusWMV9 | sed 's/enabled/2/g'
sudo vcgencmd $getStatusH264 | sed 's/disabled/1/g'
sudo vcgencmd $getStatusMPG2 | sed 's/disabled/1/g'
sudo vcgencmd $getStatusWVC1 | sed 's/disabled/1/g'
sudo vcgencmd $getStatusMPG4 | sed 's/disabled/1/g'
sudo vcgencmd $getStatusMJPG | sed 's/disabled/1/g'
sudo vcgencmd $getStatusWMV9 | sed 's/disabled/1/g'
