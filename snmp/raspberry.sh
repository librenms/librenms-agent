#!/bin/bash
#######################################
# please read DOCS to succesfully get #
# raspberry sensors into your host    #
#######################################
exists_command()
{
  command -v "$1" >/dev/null 2>&1
}

require_commands=("vcgencmd" "sed") ;

for i in "${require_commands[@]}" ;
do
    if exists_command $i; then
        eval "BIN_${i^^}"="$(command -v $i)";
    else
        echo "Your system does not have [$i]";
        exit
    fi

done ;


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

sudo $BIN_VCGENCMD $getTemp | $BIN_SED 's|[^0-9.]||g'
sudo $BIN_VCGENCMD $getVoltsCore | $BIN_SED 's|[^0-9.]||g'
sudo $BIN_VCGENCMD $getVoltsRamC | $BIN_SED 's|[^0-9.]||g'
sudo $BIN_VCGENCMD $getVoltsRamI | $BIN_SED 's|[^0-9.]||g'
sudo $BIN_VCGENCMD $getVoltsRamP | $BIN_SED 's|[^0-9.]||g'
sudo $BIN_VCGENCMD $getFreqArm  | $BIN_SED 's/frequency(45)=//g'
sudo $BIN_VCGENCMD $getFreqCore | $BIN_SED 's/frequency(1)=//g'
sudo $BIN_VCGENCMD $getStatusH264 | $BIN_SED 's/H264=//g'
sudo $BIN_VCGENCMD $getStatusMPG2 | $BIN_SED 's/MPG2=//g'
sudo $BIN_VCGENCMD $getStatusWVC1 | $BIN_SED 's/WVC1=//g'
sudo $BIN_VCGENCMD $getStatusMPG4 | $BIN_SED 's/MPG4=//g'
sudo $BIN_VCGENCMD $getStatusMJPG | $BIN_SED 's/MJPG=//g'
sudo $BIN_VCGENCMD $getStatusWMV9 | $BIN_SED 's/WMV9=//g'
