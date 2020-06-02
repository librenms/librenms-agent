#!/usr/bin/python3
import io
import re
import gzip
import os
import json

LOGFILES = [
    "/var/log/backupninja.log",
]

def main():
    last_actions, last_fatal, last_error, last_warning = get_backupninja_state()
    output = {'version': '1', 'error': '0', 'error_string': '', 'actions': last_actions, 'fatal': last_fatal, 'error': last_error, 'warning': last_warning}
    print(json.dumps(output))


def readlog(logfile):
    if logfile.endswith('.gz'):
        return gzip.open(logfile,'r')
    else:
        return io.open(logfile,'r')


def get_backupninja_state():
    last_actions = 0
    last_fatal = 0
    last_error = 0
    last_warning = 0
    
    for logfile in LOGFILES:
        if not os.path.isfile(logfile):
            continue

        with readlog(logfile) as f:
            for line in reversed(list(f)):
                match = re.search('^(.*) [a-zA-Z]*: FINISHED: ([0-9]+) actions run. ([0-9]+) fatal. ([0-9]+) error. ([0-9]+) warning.$', line)
                if match:
                    last_actions = int(match.group(2))
                    last_fatal = int(match.group(3))
                    last_error = int(match.group(4))
                    last_warning = int(match.group(5))
                    break
    
    return last_actions, last_fatal, last_error, last_warning


if __name__ == '__main__':
    main()
