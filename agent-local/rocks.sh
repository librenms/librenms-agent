#!/bin/bash
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by the
# Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.  Please see LICENSE.txt at the top level of
# the source code distribution for details.
# @author     SvennD <svennd@svennd.be>

# required
source /etc/profile.d/sge-binaries.sh;

QSTAT="/opt/gridengine/bin/linux-x64/qstat"
RUNNING_JOBS=$($QSTAT -u "*" -s r | wc -l)
PENDING_JOBS=$($QSTAT -u "*" -s p | wc -l)
SUSPEND_JOBS=$($QSTAT -u "*" -s s | wc -l)
ZOMBIE_JOBS=$($QSTAT -u "*" -s z | wc -l)

echo $RUNNING_JOBS;
echo $PENDING_JOBS;
echo $SUSPEND_JOBS;
echo $ZOMBIE_JOBS;

