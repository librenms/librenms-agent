#!/usr/bin/env python

import json
import subprocess

pdnscontrol = '/usr/bin/pdns_control'

process = subprocess.Popen([pdnscontrol, 'show', '*'], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
input = process.communicate()
stdout = input[0].decode()
stderr = input[1].decode()

data = {}
for var in stdout.split(','):
    if '=' in var:
        key, value = var.split('=')
        data[key] = value

output = {
    'version': 1,
    'error': process.returncode,
    'errorString': stderr,
    'data': data
}

print(json.dumps(output))
