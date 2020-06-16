#!/usr/bin/env python3

import subprocess
import json
from os.path import isfile

CONFIGFILE = '/etc/snmp/dhcp.json'

# Configfile is needed /etc/snmp/dhcp.json
#
# {"leasefile": "/var/lib/dhcp/dhcpd.leases"
# }
#

error = 0
error_string = ''
version = 2

with open(CONFIGFILE, 'r') as json_file:
    try:
        configfile = json.load(json_file)
    except json.decoder.JSONDecodeError as e:
        error = 1
        error_string = "Configfile Error: '%s'" % e


if not error:
    leases = {'total': 0,
              'active': 0,
              'expired': 0,
              'released': 0,
              'abandoned': 0,
              'reset': 0,
              'bootp': 0,
              'backup': 0,
              'free': 0,
             }
    if not isfile(configfile['leasefile']):
        error = 1
        error_string = 'Lease File not found'
    else:
        with open(configfile['leasefile']) as fp:
            line = fp.readline()
            while line:
                line = fp.readline()

                if 'rewind' not in line:
                    if line.startswith('lease'):
                        leases['total'] += 1
                    elif 'binding state active' in line:
                        leases['active'] += 1
                    elif 'binding state expired' in line:
                        leases['expired'] += 1
                    elif 'binding state released' in line:
                        leases['released'] += 1
                    elif 'binding state abandoned' in line:
                        leases['abandoned'] += 1
                    elif 'binding state reset' in line:
                        leases['reset'] += 1
                    elif 'binding state bootp' in line:
                        leases['bootp'] += 1
                    elif 'binding state backup' in line:
                        leases['backup'] += 1
                    elif 'binding state free' in line:
                        leases['free'] += 1

shell_cmd = "dhcpd-pools -s i -A"
pool_data = subprocess.Popen(shell_cmd, shell=True, stdout=subprocess.PIPE).stdout.read().split(b'\n')

data = {'leases': leases,
        'pools': [],
        'networks': [],
        'all_networks': []
        }

category = None
jump_line = 0
for p in pool_data:
    line = p.decode('utf-8')

    if jump_line:
        jump_line -= 1
        continue

    if line.startswith('Ranges:'):
        category = 'pools'
        jump_line = 1
        continue

    if line.startswith('Shared networks:'):
        category = 'networks'
        jump_line = 1
        continue

    if line.startswith('Sum of all ranges:'):
        category = 'all_networks'
        jump_line = 1
        continue

    if not len(line):
        continue

    p = line.split()

    if category == 'pools':
        data[category].append({'first_ip': p[1],
                                'last_ip':p[3],
                                'max': p[4],
                                'cur': p[5],
                                'percent': p[6],
                                })
        continue

    if category == 'networks':
        data[category].append({'network': p[0],
                                'max': p[1],
                                'cur': p[2],
                                'percent': p[3],
                                })
        continue

    if category == 'all_networks':
        data[category] ={'max': p[2],
                          'cur': p[3],
                          'percent': p[4],
                         }
        continue


output = {'version': version,
          'error': error,
          'errorString': error_string,
          'data': data}

print (json.dumps(output))
