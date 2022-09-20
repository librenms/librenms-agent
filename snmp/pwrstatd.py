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
# TODO:
#     1. If CyberPower ends up building support to collect data from multiple PSUs on a
#        single computer, then this script will be updated to support that.

import json
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
    elif key in (
        "Rating Voltage",
        "Rating Power",
        "Utility Voltage",
        "Output Voltage",
        "Battery Capacity",
        "Remaining Runtime",
        "Load",
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
    pwrstat_cmd = PWRSTAT_CMD
    output_data = {"errorString": "", "error": 0, "version": 1, "data": []}
    psu_data = {
        "mruntime": None,
        "pcapacity": None,
        "pload": None,
        "sn": None,
        "voutput": None,
        "vrating": None,
        "vutility": None,
        "wload": None,
        "wrating": None,
    }

    # Load configuration file if it exists
    try:
        with open(CONFIG_FILE, "r") as json_file:
            config_file = json.load(json_file)
            if "pwrstat_cmd" in config_file.keys():
                pwrstat_cmd = config_file["pwrstat_cmd"]
    except FileNotFoundError:
        pass
    except (KeyError, PermissionError, OSError, json.decoder.JSONDecodeError) as err:
        output_data["error"] = 1
        output_data["errorString"] = "Config file Error: '%s'" % err

    try:
        # Execute pwrstat command
        pwrstat_process = subprocess.Popen(
            [pwrstat_cmd, PWRSTAT_ARGS],
            stdin=None,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        poutput, perror = pwrstat_process.communicate()

        if perror:
            raise OSError(perror.decode("utf-8"))

        # Parse pwrstat command output and collect data.
        for line in poutput.decode("utf-8").split("\n"):
            regex_search = re.search(REGEX_PATTERN, line.strip())
            if not regex_search:
                continue

            try:
                key = regex_search.groups()[0]
                value = regex_search.groups()[1]
                if key in KEY_TO_VARIABLE_MAP.keys():
                    psu_data[KEY_TO_VARIABLE_MAP[key]] = value_sanitizer(key, value)
            except IndexError as err:
                output_data["error"] = 1
                output_data["errorString"] = "Command Output Parsing Error: '%s'" % err
                continue

        # Manually calculate percentage load on PSU
        if psu_data["wrating"]:
            # int to float hacks in-place for python2 backwards compatibility
            psu_data["pload"] = int(
                float(psu_data["wload"]) / float(psu_data["wrating"]) * 100
            )
    except (subprocess.CalledProcessError, OSError) as err:
        output_data["error"] = 1
        output_data["errorString"] = "Command Execution Error: '%s'" % err

    output_data["data"].append(psu_data)
    print(json.dumps(output_data))


if __name__ == "__main__":
    main()
