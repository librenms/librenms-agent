#!/usr/bin/env python
#
# Name: Systemd Script
# Author: bnerickson <bnerickson87@gmail.com> w/SourceDoctor's certificate.py script forming
#         the base of the vast majority of this one.
# Version: 1.0
# Description: This is a simple script to parse "systemctl" output for ingestion into
#              LibreNMS via the systemd application.
# Installation:
#     1. Copy this script to /etc/snmp/ and make it executable:
#         chmod +x /etc/snmp/systemd.py
#     2. Edit your snmpd.conf and include:
#         extend systemdd /etc/snmp/systemd.py
#     3. (Optional) Create a /etc/snmp/systemd.json file and specify:
#           a.) "systemctl_cmd" - String path to the systemctl binary ["/usr/bin/systemctl"]
#           b.) "include_inactive_units" - True/False string to include inactive units in
#               results ["False"]
#         ```
#         {
#             "systemctl_cmd": "/bin/systemctl",
#             "include_inactive_units": "True"
#         }
#         ```
#     4. Restart snmpd and activate the app for desired host.

import json
import subprocess
import sys

CONFIG_FILE = "/etc/snmp/systemd.json"
SYSTEMCTL_ARGS = ["list-units", "--full", "--plain", "--no-legend", "--no-page"]
SYSTEMCTL_CMD = "/usr/bin/systemctl"
# The unit "sub" type is the only unit state that has three layers of
# depth.  "load" and "active" are two layers deep.
SYSTEMCTL_TERNARY_STATES = ["sub"]


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
        systemctl_cmd: The full systemctl command to execute.
    """
    systemctl_cmd = [SYSTEMCTL_CMD]
    systemctl_args = SYSTEMCTL_ARGS

    # Load configuration file if it exists
    try:
        with open(CONFIG_FILE, "r") as json_file:
            config_file = json.load(json_file)
            systemctl_cmd = [config_file["systemctl_cmd"]]
            if config_file["include_inactive_units"].lower().strip() == "true":
                systemctl_args.append("--all")
    except FileNotFoundError:
        pass
    except (KeyError, PermissionError, OSError, json.decoder.JSONDecodeError) as err:
        error_handler("Config File Error", err)

    # Create and return full systemctl command.
    systemctl_cmd.extend(systemctl_args)
    return systemctl_cmd


def command_executor(systemctl_cmd):
    """
    command_executor(): Execute the systemctl command and return the output.

    Inputs:
        systemctl_cmd: The full systemctl command to execute.
    Outputs:
        poutput: The stdout of the executed command (empty byte-string if error).
    """
    try:
        # Execute systemctl command
        poutput = subprocess.check_output(
            systemctl_cmd,
            stdin=None,
            stderr=subprocess.PIPE,
        )
    except (subprocess.CalledProcessError, OSError) as err:
        error_handler("Command Execution Error", err)
    return poutput


def unit_parser(line, systemctl_data):
    """
    unit_parser(): Parses a unit's line for load, active, and sub status.  Each
                   of those values is incremented in the global systemctl_data
                   variable as-well-as the totals for each category.

    Inputs:
        line: The unit's status line from the systemctl stdout.
    Outputs:
        None
    """
    line_parsed = line.strip().split()

    try:
        # Reverse the <unit_name.sub_type> to grab the sub type
        # (ignoring periods in the service name).
        parsed_results = {
            "load": line_parsed[1],
            "active": line_parsed[2],
            "sub": {line_parsed[0][::-1].split(".")[0][::-1]: line_parsed[3]},
        }
    except (IndexError) as err:
        error_handler("Command Output Parsing Error", err)

    for state_type, state_value in parsed_results.items():
        if state_type not in systemctl_data:
            systemctl_data[state_type] = {}
        if state_type not in SYSTEMCTL_TERNARY_STATES:
            systemctl_data[state_type][state_value] = (
                1
                if state_value not in systemctl_data[state_type]
                else (systemctl_data[state_type][state_value] + 1)
            )
            systemctl_data[state_type]["total"] = (
                1
                if "total" not in systemctl_data[state_type]
                else (systemctl_data[state_type]["total"] + 1)
            )
        else:
            for sub_state_type, sub_state_value in state_value.items():
                if sub_state_type not in systemctl_data[state_type]:
                    systemctl_data[state_type][sub_state_type] = {}
                systemctl_data[state_type][sub_state_type][sub_state_value] = (
                    1
                    if sub_state_value not in systemctl_data[state_type][sub_state_type]
                    else (
                        systemctl_data[state_type][sub_state_type][sub_state_value] + 1
                    )
                )
                systemctl_data[state_type][sub_state_type]["total"] = (
                    1
                    if "total" not in systemctl_data[state_type][sub_state_type]
                    else (systemctl_data[state_type][sub_state_type]["total"] + 1)
                )
    return systemctl_data


def main():
    """
    main(): main function that delegates config file parsing, command execution,
            and unit stdout parsing.  Then it prints out the expected json output
            for the systemd application.

    Inputs:
        None
    Outputs:
        None
    """
    output_data = {"errorString": "", "error": 0, "version": 1, "data": {}}

    # Parse configuration file.
    systemctl_cmd = config_file_parser()

    # Execute systemctl command and parse output.
    for line in command_executor(systemctl_cmd).decode("utf-8").split("\n"):
        if not line:
            continue
        output_data["data"] = unit_parser(line, output_data["data"])
    print(json.dumps(output_data))


if __name__ == "__main__":
    main()
