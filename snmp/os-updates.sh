#!/bin/bash
################################################################
# copy this script to somewhere like /opt and make chmod +x it #
# edit your snmpd.conf and include                             #
# extend osupdate /opt/os-updates.sh                           #
# restart snmpd and activate the app for desired host          #
################################################################ 
BIN_WC='/usr/bin/wc'
CMD_WC='-l'
BIN_ZYPPER='/usr/bin/zypper'
CMD_ZYPPER='lu'
BIN_YUM='/usr/bin/yum'
CMD_YUM='-q check-update'
BIN_APT='/usr/bin/apt-get'
CMD_APT='-s upgrade'
BIN_PACMAN='/usr/bin/pacman'
CMD_PACMAN='-Sup'

if [ -f $BIN_APT ]; then
    # Debian / Ubuntu
    UPDATES=`$BIN_APT $CMD_APT | grep 'Inst' | $BIN_WC $CMD_WC`
    echo $UPDATES;
elif [ -f $BIN_YUM ]; then
    # CentOS / Redhat
    UPDATES=`$BIN_YUM $CMD_YUM | $BIN_WC $CMD_WC`
    if [ $UPDATES -gt 1 ]; then
        echo $(($UPDATES-1));
    else
        echo "0";
    fi
elif [ -f $BIN_ZYPPER ]; then
    # OpenSUSE
    UPDATES=`$BIN_ZYPPER $CMD_ZYPPER | $BIN_WC $CMD_WC`
    if [ $UPDATES -gt 3 ]; then
        echo $(($UPDATES-3));
    else
        echo "0";
    fi
elif [ -f $BIN_PACMAN ]; then
    # Arch
    UPDATES=`$BIN_PACMAN $CMD_PACMAN | $BIN_WC $CMD_WC`
    if [ $UPDATES -gt 1 ]; then
        echo $(($UPDATES-1));
    else
        echo "0";
    fi
else
    echo "0";
fi
