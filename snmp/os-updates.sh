#!/usr/bin/env bash

# - Copy this script to somewhere (like /opt/osupdate.sh)
# - Make it executable (chmod +x /opt/osupdate.sh)
# - Add the following line to your snmpd.conf file
#   extend osupdate /opt/osupdate.sh
# - Restart snmpd
#
# Note: Change the path accordingly, if you're not using "/opt/osupdate.sh"

# You need the following tools to be in your PATH env, adjust accordingly
# - grep, wc
PATH=$PATH

if [ -x "$(command -v zypper)" ]; then
    # OpenSUSE
    UPDATES=$(zypper -q lu | wc -l)
    if [ $UPDATES -gt 2 ]; then
        echo $(($UPDATES-2));
    else
        echo "0";
    fi
elif [ -x "$(command -v dnf)" ]; then
    # Fedora
    UPDATES=$(dnf -q check-update | wc -l)
    if [ $UPDATES -gt 1 ]; then
        echo $(($UPDATES-1));
    else
        echo "0";
    fi
elif [ -x "$(command -v pacman)" ]; then
    # Arch
    UPDATES=$(pacman -Sup | wc -l)
    if [ $UPDATES -gt 1 ]; then
        echo $(($UPDATES-1));
    else
        echo "0";
    fi
elif [ -x "$(command -v yum)" ]; then
    # CentOS / Redhat
    UPDATES=$(yum -q check-update | wc -l)
    if [ $UPDATES -gt 1 ]; then
        echo $(($UPDATES-1));
    else
        echo "0";
    fi
elif [ -x "$(command -v apt-get)" ]; then
    # Debian / Devuan / Ubuntu
    UPDATES=$(apt-get -qq -s upgrade | grep -c 'Inst')
    if [ $UPDATES -gt 1 ]; then
        echo $UPDATES;
    else
        echo "0";
    fi
else
    echo "0";
fi
