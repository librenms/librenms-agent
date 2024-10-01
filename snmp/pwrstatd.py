#!/usr/bin/env python
#
# Name: Pwrstatd Script
# Author: bnerickson <bnerickson87@gmail.com> w/SourceDoctor's certificate.py script forming
#         the base of the vast majority of this one.
# Version: 1.0
# Description: This is a simple script to parse "pwrstat -status" output for ingestion into
#              LibreNMS via the pwrstatd application.  Pwrstatd is a service/application
#              provided by CyberPower for their personal PSUs.  The software is available
#              here:
#     https://www.cyberpowersystems.com/product/software/power-panel-personal/powerpanel-for-linux/
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
import sys

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
PWRSTAT_ARGS = ["-status"]
PWRSTAT_CMD = "/sbin/pwrstat"
REGEX_PATTERN = r"([\w\s]+)\.\.+ (.*)"


def error_handler(error_name, err):
    """
    error_handler(): Common error handler for config/output parsing and
                     command execution.
    Inputs:
        error_name: String describing the error handled.
        err: The error message in its entirety.
    Outputs:
        None
    """
    output_data = {
        "errorString": "%s: '%s'" % (error_name, err),
        "error": 1,
        "version": 1,
        "data": [],
    }
    print(json.dumps(output_data))
    sys.exit(1)


def config_file_parser():
    """
    config_file_parser(): Parses the config file (if it exists) and extracts the
                          necessary parameters.

    Inputs:
        None
    Outputs:
        pwrstat_cmd: The full pwrstat command to execute.
    """
    pwrstat_cmd = [PWRSTAT_CMD]

    # Load configuration file if it exists
    try:
        with open(CONFIG_FILE, "r") as json_file:
            config_file = json.load(json_file)
            pwrstat_cmd = [config_file["pwrstat_cmd"]]
    except FileNotFoundError:
        pass
    except (KeyError, PermissionError, OSError, json.decoder.JSONDecodeError) as err:
        error_handler("Config File Error", err)

    # Create and return full pwrstat command.
    pwrstat_cmd.extend(PWRSTAT_ARGS)
    return pwrstat_cmd


def command_executor(pwrstat_cmd):
    """
    command_executor(): Execute the pwrstat command and return the output.

    Inputs:
        pwrstat_cmd: The full pwrstat command to execute.
    Outputs:
        poutput: The stdout of the executed command.
    """
    try:
        # Execute pwrstat command
        poutput = subprocess.check_output(
            pwrstat_cmd,
            stdin=None,
            stderr=subprocess.PIPE,
        )
    except (subprocess.CalledProcessError, OSError) as err:
        error_handler("Command Execution Error", err)
    return poutput


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
    if key in (
        "Rating Voltage",
        "Rating Power",
        "Utility Voltage",
        "Output Voltage",
        "Battery Capacity",
        "Remaining Runtime",
        "Load",
    ):
        return int(value.split(" ")[0])
    return None


def output_parser(pwrstat_output):
    """
    output_parser(): Parses the pwrstat command output and returns a dictionary
                     of PSU metrics.

    Inputs:
        pwrstat_output: The pwrstat command stdout
    Outputs:
        psu_data: A dictionary of PSU metrics.
    """
    psu_data = {}

    for line in pwrstat_output.decode("utf-8").split("\n"):
        regex_search = re.search(REGEX_PATTERN, line.strip())

        if not regex_search:
            continue

        try:
            key = regex_search.groups()[0]
            value = regex_search.groups()[1]
            if key in KEY_TO_VARIABLE_MAP:
                psu_data[KEY_TO_VARIABLE_MAP[key]] = value_sanitizer(key, value)
        except IndexError as err:
            error_handler("Command Output Parsing Error", err)

    # Manually calculate percentage load on PSU
    if "wrating" in psu_data and "wload" in psu_data and psu_data["wrating"]:
        # int to float hacks in-place for python2 backwards compatibility
        psu_data["pload"] = int(
            float(psu_data["wload"]) / float(psu_data["wrating"]) * 100
        )
    return psu_data


def main():
    """
    main(): main function performs pwrstat command execution and output parsing.

    Inputs:
        None
    Outputs:
        None
    """
    output_data = {"errorString": "", "error": 0, "version": 1, "data": []}

    # Parse configuration file.
    pwrstat_cmd = config_file_parser()

    # Execute pwrstat command and parse output.
    output_data["data"].append(output_parser(command_executor(pwrstat_cmd)))

    print(json.dumps(output_data))


if __name__ == "__main__":
    main()
