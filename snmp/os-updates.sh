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
BIN_AWK='/usr/bin/awk'
BIN_WC='/usr/bin/wc'
BIN_GREP='/bin/grep'
CMD_WC='-l'
BIN_ZYPPER='/usr/bin/zypper'
CMD_ZYPPER='lu'
BIN_YUM='/usr/bin/yum'
CMD_YUM='-q check-update'
BIN_APT='/usr/bin/apt-get'
CMD_APT='-qq -s upgrade'
BIN_PACMAN='/usr/bin/pacman'
CMD_PACMAN='-Sup'

################################################################
# Don't change anything unless you know what are you doing     #
################################################################
if [ -f /etc/os-release ]; then
	OS=`$BIN_AWK -F= '/^ID=/{print $2}' /etc/os-release`
	if [ $OS == "opensuse" ]; then
		UPDATES=`$BIN_ZYPPER $CMD_ZYPPER | $BIN_WC $CMD_WC`
		if [ $UPDATES -gt 3 ]; then
			echo $(($UPDATES-3));
		else
			echo "0";
		fi
	elif [ $OS == "\"centos\"" ]; then
		UPDATES=`$BIN_YUM $CMD_YUM | $BIN_WC $CMD_WC`
		if [ $UPDATES -gt 6 ]; then
			echo $(($UPDATES-6));
		else
			echo "0";
		fi
	elif [ $OS == "debian" ]; then
		UPDATES=`$BIN_APT $CMD_APT | $BIN_GREP 'Inst' | $BIN_WC $CMD_WC`
		if [ $UPDATES -gt 1 ]; then
			echo $UPDATES;
		else
			echo "0";
		fi
	elif [ $OS == "ubuntu" ]; then
		UPDATES=`$BIN_APT $CMD_APT | $BIN_GREP 'Inst' | $BIN_WC $CMD_WC`
		if [ $UPDATES -gt 1 ]; then
			echo $UPDATES;
		else
			echo "0";
		fi
	elif [ $OS == "arch" ]; then
		UPDATES=`$BIN_PACMAN $CMD_PACMAN | $BIN_WC $CMD_WC`
		if [ $UPDATES -gt 1 ]; then
        		echo $(($UPDATES-1));
    		else
        		echo "0";
		fi
	fi
else
	echo "0";
fi

