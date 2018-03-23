#!/usr/bin/env bash
################################################################
# copy this script to /etc/snmp/ and make it executable:       #
# chmod +x /etc/snmp/os-updates.sh                             #
# ------------------------------------------------------------ #
# edit your snmpd.conf and include:                            #
# extend osupdate /opt/os-updates.sh 			       #
#--------------------------------------------------------------#
# restart snmpd and activate the app for desired host          #
#--------------------------------------------------------------#
# please make sure you have the path/binaries below            #
################################################################ 
BIN_WC='/usr/bin/wc'
BIN_GREP='/bin/grep'
CMD_GREP='-c'
CMD_WC='-l'
BIN_ZYPPER='/usr/bin/zypper'
CMD_ZYPPER='-q lu'
BIN_YUM='/usr/bin/yum'
CMD_YUM='-q check-update'
BIN_DNF='/usr/bin/dnf'
CMD_DNF='-q check-update'
BIN_APT='/usr/bin/apt-get'
CMD_APT='-qq -s upgrade'
BIN_PACMAN='/usr/bin/pacman'
CMD_PACMAN='-Sup'

################################################################
# Don't change anything unless you know what are you doing     #
################################################################
if [ -f $BIN_ZYPPER ]; then
    # OpenSUSE
    UPDATES=`$BIN_ZYPPER $CMD_ZYPPER | $BIN_WC $CMD_WC`
    if [ $UPDATES -ge 2 ]; then
        echo $(($UPDATES-2));
    else
        echo "0";
    fi
elif [ -f $BIN_DNF ]; then
    # Fedora
    UPDATES=`$BIN_DNF $CMD_DNF | $BIN_WC $CMD_WC`
    if [ $UPDATES -ge 1 ]; then
        echo $(($UPDATES-1));
    else
        echo "0";
    fi
elif [ -f $BIN_PACMAN ]; then
    # Arch
    UPDATES=`$BIN_PACMAN $CMD_PACMAN | $BIN_WC $CMD_WC`
    if [ $UPDATES -ge 1 ]; then
        echo $(($UPDATES-1));
    else
        echo "0";
    fi
elif [ -f $BIN_YUM ]; then
    # CentOS / Redhat
    UPDATES=`$BIN_YUM $CMD_YUM | $BIN_WC $CMD_WC`
    if [ $UPDATES -ge 1 ]; then
        echo $(($UPDATES-1));
    else
        echo "0";
    fi
elif [ -f $BIN_APT ]; then
    # Debian / Devuan / Ubuntu
    UPDATES=`$BIN_APT $CMD_APT | $BIN_GREP $CMD_GREP 'Inst'`
    if [ $UPDATES -ge 1 ]; then
        echo $UPDATES;
    else
        echo "0";
    fi
else
    echo "0";
fi
