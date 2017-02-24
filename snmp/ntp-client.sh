#!/usr/bin/env bash
################################################################
# copy this script to somewhere like /opt and make chmod +x it #
# edit your snmpd.conf and include                             #
# extend ntp-client /opt/ntp-client.sh                         #
# restart snmpd and activate the app for desired host          #
# please make sure you have the path/binaries below            #
################################################################
# Binaries and paths required                                  #
################################################################
exists_command()
{
  command -v "$1" >/dev/null 2>&1
}
require_commands=("ntpq" "grep" "tr" "cut") ;

for i in "${require_commands[@]}" ;
do
    if exists_command $i; then
        eval "BIN_${i^^}"="$(command -v $i)";
    else
        echo "Your system does not have [$i]";
        exit
    fi

done ;

################################################################
# Don't change anything unless you know what are you doing     #
################################################################
CMD1=`$BIN_NTPQ -c rv | $BIN_GREP 'jitter' | $BIN_TR '\n' ' '`
IFS=', ' read -r -a array <<< "$CMD1"

for value in 2 3 4 5 6
do
	echo ${array["$value"]} | $BIN_CUT -d "=" -f 2
done

