#!/usr/bin/env bash
# (C) 2017  Cercel Valentin
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# - Copy this script to somewhere (like /opt/exim-stats.sh)
# - Make it executable (chmod +x /opt/exim-stats.sh)
# - Add the following line to your snmpd.conf file
#   extend exim-stats /opt/exim-stats.sh
# - Restart snmpd
#
# Note: Change the path accordingly, if you're not using "/opt/exim-stats.sh"

# You need the following tools to be in your PATH env, adjust accordingly
# - exim, grep, wc
PATH=$PATH

echo exim -bp | grep 'frozen' | wc -l

echo exim -bpc
