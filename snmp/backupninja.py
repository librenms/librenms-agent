#!/usr/bin/python
import io
import re
import gzip
import os

LOGFILES = [
    "/var/log/backupninja.log",
    "/var/log/backupninja.log.1.gz",
]

def main():
    print_backupninja_state()

def readlog(logfile):
    if logfile.endswith('.gz'):
        return gzip.open(logfile,'r')
    else:
        return io.open(logfile,'r')

def print_backupninja_state():
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
                    last_actions = match.group(2)
                    last_fatal = match.group(3)
                    last_error = match.group(4)
                    last_warning = match.group(5)
                    print "%s %s %s %s" % (last_actions, last_fatal, last_error, last_warning)
                    break


if __name__ == '__main__':
    main()
