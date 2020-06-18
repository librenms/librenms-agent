#!/usr/bin/env python3

import json
import yaml
from os.path import isfile
from time import time


output = {}
output['error'] = 0
output['errorString'] = ""
output['version'] = 1

CONFIGFILE = '/etc/snmp/puppet.json'
# optional config file
# {
#      "agent": {
#         "summary_file": "/my/custom/path/to/summary_file"
#      }
# }


summary_files = ['/var/cache/puppet/state/last_run_summary.yaml',
                 '/opt/puppetlabs/puppet/cache/state/last_run_summary.yaml']


def parse_yaml_file(filename):
    try:
        yaml_data = yaml.load(open(filename, 'r'))
        msg = None
    except yaml.scanner.ScannerError as e:
        yaml_data = []
        msg = str(e)
    except yaml.parser.ParserError as e:
        yaml_data = []
        msg = str(e)

    return msg, yaml_data


def time_processing(data):
    new_data = {}

    for k in data.keys():
        if k == 'last_run':
            # generate difference to last run (seconds)
            new_data[k] = round(time() - data[k])
            continue
        new_data[k] = round(data[k], 2)

    return new_data


def processing(data):
    new_data = {}
    for k in ['changes', 'events', 'resources', 'version']:
        new_data[k] = data[k]

    new_data['time'] = time_processing(data['time'])

    return new_data


# extend last_run_summary_file list with optional custom file
if isfile(CONFIGFILE):
    with open(CONFIGFILE, 'r') as json_file:
        try:
            configfile = json.load(json_file)
        except json.decoder.JSONDecodeError as e:
            output['error'] = 1
            output['errorString'] = "Configfile Error: '%s'" % e
else:
    configfile = None

if not output['error'] and configfile:
    try:
        if 'agent' in configfile.keys():
            custom_summary_file = configfile['agent']['summary_file']
            summary_files.insert(0, custom_summary_file)
    except KeyError:
        output['error'] = 1
        output['errorString'] = "Configfile Error: '%s'" % e

# search existing summary file from list
if not output['error']:
    summary_file = None
    for sum_file in summary_files:
        if isfile(sum_file):
            summary_file = sum_file
            break

    if not summary_file:
        output['error'] = 1
        output['errorString'] = "no puppet agent run summary file found"

# open summary file
if not output['error']:
    msg, data = parse_yaml_file(summary_file)

    if msg:
        output['error'] = 1
        output['errorString'] = msg

output['data'] = processing(data)

print (json.dumps(output))
