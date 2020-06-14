#!/usr/bin/env python3

import os
import json

CONFIGFILE = '/etc/snmp/pureftpd.json'

pureftpwho_cmd = '/usr/sbin/pure-ftpwho'
pureftpwho_args = '-v -s -n'


output_data = {}
output_data['version'] = 1
output_data['errorString'] = ""
output_data['error'] = 0


if os.path.isfile(CONFIGFILE):
    with open(CONFIGFILE, 'r') as json_file:
        try:
            configfile = json.load(json_file)
        except json.decoder.JSONDecodeError as e:
            output_data['error'] = 1
            output_data['errorString'] = "Configfile Error: '%s'" % e
else:
    configfile = None

if not output_data['error'] and configfile:
    try:
        if 'pureftpwho_cmd' in configfile.keys():
            pureftpwho_cmd = configfile['pureftpwho_cmd']
    except KeyError:
        output_data['error'] = 1
        output_data['errorString'] = "Configfile Error: '%s'" % e


output = os.popen(pureftpwho_cmd + ' ' + pureftpwho_args).read()

data = {}

for line in output.split('\n'):
    if not len(line):
        continue

    pid, acct, time, state, file, peer, local, port, transfered, total, percent, bandwidth = line.split('|')

    if "IDLE" in state:
        state = "IDLE"
    elif "DL" in state:
        state = "DL"
    elif "UL" in state:
        state = "UL"

    if acct not in data.keys():
        data[acct] = {}
    if state not in data[acct]:
        data[acct][state] = {'bitrate': 0,
                             'connections': 0
                             }
    bandwidth_bit = int(bandwidth) * 1024 * 8
    data[acct][state]['bitrate'] += bandwidth_bit
    data[acct][state]['connections'] += 1

output_data['data'] = data

print (json.dumps(output_data))
