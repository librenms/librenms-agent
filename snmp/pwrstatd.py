#!/usr/bin/env python
#
# Name: Pwrstatd Script
# Author: bnerickson <bnerickson87@gmail.com> w/SourceDoctor's certificate.py script forming
#         the base of the vast majority of this one.
# Version: 1.0
# Description: This is a simple script to parse "pwrstat -status" output for ingestion into
#              LibreNMS via the pwrstatd application.  Pwrstatd is a service/application
#              provided by CyberPower for their personal PSUs.  The software is available
#              here: https://www.cyberpowersystems.com/product/software/power-panel-personal/powerpanel-for-linux/
# Installation:
#     1. Copy this script to /etc/snmp/ and make it executable:
#         chmod +x /etc/snmp/pwrstatd.py
#     2. Edit your snmpd.conf and include:
#         extend pwrstatd /etc/snmp/pwrstatd.py
#     3. (Optional) Create a /etc/snmp/pwrstatd.json file and specify the path to the pwrstat
#        executable as json [the default path is /sbin/pwrstat]:
#         ```
#         {
#             "pwrstat_cmd": "/sbin/pwrstat"
#         }
#         ```
#     4. Restart snmpd and activate the app for desired host.


import json
import os
import re
import subprocess


CONFIG_FILE = "/etc/snmp/pwrstatd.json"
KEY_TO_VARIABLE_MAP = {
    "Firmware Number": "sn",
    "Rating Voltage": "vrating",
    "Rating Power": "wrating",
    "Utility Voltage": "vutility",
    "Output Voltage": "voutput",
    "Battery Capacity": "pcapacity",
    "Remaining Runtime": "mruntime",
    "Load": "wload",
}
PWRSTAT_ARGS = "-status"
PWRSTAT_CMD = "/sbin/pwrstat"
REGEX_PATTERN = r"([\w\s]+)\.\.+ (.*)"


def value_sanitizer(key, value):
    """
    value_sanitizer(): Parses the given value to extract the exact numerical (or string) value.

    Inputs:
        key: The key portion of the output after regex parsing (clean).
        value: The entire value portion of the output after regex parsing (dirty).
    Outputs:
        str, int, or None depending on what key is given.
    """
    if key == "Firmware Number":
        return str(value)
    elif (
        key == "Rating Voltage"
        or key == "Rating Power"
        or key == "Utility Voltage"
        or key == "Output Voltage"
        or key == "Battery Capacity"
        or key == "Remaining Runtime"
        or key == "Load"
    ):
        return int(value.split(" ")[0])
    else:
        return None


def main():
    """
    main(): main function performs pwrstat command execution and output parsing.

    Inputs:
        None
    Outputs:
        None
    """
    config_file = None
    pwrstat_cmd = PWRSTAT_CMD
    output_data = {"errorString": "", "error": 0, "version": 1, "data": []}
    psu_data = {
        "mruntime": 0,
        "pcapacity": 0,
        "pload": 0,
        "sn": "",
        "voutput": 0,
        "vrating": 0,
        "vutility": 0,
        "wload": 0,
        "wrating": 0,
    }

    # Load configuration file if it exists
    if os.path.isfile(CONFIG_FILE):
        with open(CONFIG_FILE, "r") as json_file:
            try:
                config_file = json.load(json_file)
            except json.decoder.JSONDecodeError as e:
                output_data["error"] = 1
                output_data["errorString"] = "Config file Error: '%s'" % e
    if not output_data["error"] and config_file:
        try:
            if "pwrstat_cmd" in config_file.keys():
                pwrstat_cmd = config_file["pwrstat_cmd"]
        except KeyError as e:
            output_data["error"] = 1
            output_data["errorString"] = "Config file Error: '%s'" % e

    # Execute pwrstat command and error handling
    pwrstat_process = subprocess.Popen(
        pwrstat_cmd + " " + PWRSTAT_ARGS,
        shell=True,
        stdin=None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    poutput, perror = pwrstat_process.communicate()
    if perror:
        output_data["error"] = 1
        output_data["errorString"] = "Command Execution Error: '%s'" % perror

    # Parse command output
    for line in poutput.decode("utf-8").split("\n"):
        if not len(line):
            continue

        line = line.strip()
        regex_search = re.search(REGEX_PATTERN, line)
        if not regex_search:
            continue

        try:
            key = regex_search.groups()[0]
            value = regex_search.groups()[1]
        except IndexError as e:
            output_data["error"] = 1
            output_data["errorString"] = "Command Output Parsing Error: '%s'" % e
            continue

        if key not in KEY_TO_VARIABLE_MAP.keys():
            continue

        psu_data[KEY_TO_VARIABLE_MAP[key]] = value_sanitizer(key, value)

    if psu_data["wrating"] != 0:
        # int to float hacks in-place for python2 backwards compatibility
        psu_data["pload"] = int(
            float(psu_data["wload"]) / float(psu_data["wrating"]) * 100
        )

    output_data["data"].append(psu_data)
    print(json.dumps(output_data))


if __name__ == "__main__":
    main()
