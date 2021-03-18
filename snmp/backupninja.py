#!/usr/bin/env python3
import io
import json
import os
import re

version = 1
error = 0
error_string = ""

logfile = "/var/log/backupninja.log"

backupninja_datas = {
    "last_actions": 0,
    "last_fatal": 0,
    "last_error": 0,
    "last_warning": 0,
}

if not os.path.isfile(logfile):
    error_string = "file unavailable"
    error = 1
else:
    with io.open(logfile, "r") as f:
        for line in reversed(list(f)):
            match = re.search(
                "^(.*) [a-zA-Z]*: FINISHED: ([0-9]+) actions run. ([0-9]+) fatal. ([0-9]+) error. ([0-9]+) warning.$",
                line,
            )
            if match:
                backupninja_datas["last_actions"] = int(match.group(2))
                backupninja_datas["last_fatal"] = int(match.group(3))
                backupninja_datas["last_error"] = int(match.group(4))
                backupninja_datas["last_warning"] = int(match.group(5))
                break


output = {
    "version": version,
    "error": error,
    "errorString": error_string,
    "data": backupninja_datas,
}

print(json.dumps(output))
