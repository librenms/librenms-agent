#!/usr/bin/python3
# Copyright(C) 2009  Glen Pitt-Pladdy
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or(at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
#
#

CACHETIME=30
CACHEFILE='/var/cache/librenms/apache-snmp'

# Check for a cache file newer than CACHETIME seconds ago
import os
import time
if os.path.isfile(CACHEFILE) \
        and(time.time() - os.stat(CACHEFILE)[8]) < CACHETIME:
        # use cached data
        f=open(CACHEFILE, 'r')
        data=f.read()
        f.close()
else:
        # Grab the status URL (fresh data), needs package python-urlgrabber
        from urlgrabber import urlread
        data=urlread('http://localhost/server-status?auto', user_agent='SNMP Apache Stats').decode() # "data" is UTF string, need to decode.
        # Write file
        f=open(CACHEFILE+'.TMP.'+str(os.getpid()), 'w')
        f.write(data)
        f.close()
        os.rename(CACHEFILE+'.TMP.'+str(os.getpid()), CACHEFILE)


# dice up the data
scoreboardkey=['_', 'S', 'R', 'W', 'K', 'D', 'C', 'L', 'G', 'I', '.']
params={}
for line in data.splitlines():
        fields=line.split(': ')
        if len(fields) <= 1:
                continue  # "localhost" as first line causes out of index error
        elif fields[0] == 'Scoreboard':
            # count up the scoreboard into states
            states={}
            for state in scoreboardkey:
                states[state]=0
            for state in fields[1]:
                states[state] += 1
        elif fields[0] == 'Total kBytes':
            # turn into base(byte) value
            params[fields[0]]=int(fields[1])*1024
        elif len(fields) > 1:
            # just store everything else
            params[fields[0]]=fields[1]

# output the data in order(this is because some platforms don't have them all)
dataorder=[
    'Total Accesses',
    'Total kBytes',
    'CPULoad',
    'Uptime',
    'ReqPerSec',
    'BytesPerSec',
    'BytesPerReq',
    'BusyWorkers',
    'IdleWorkers'
]
for param in dataorder:
    try:
        print(params[param])
    except: # not all Apache's have all stats
        print('U')

# print the scoreboard
for state in scoreboardkey:
    print(states[state])
