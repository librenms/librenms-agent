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

CONFIG_FILE = "/etc/snmp/systemd.json"
SYSTEMCTL_ARGS = ["list-units", "--full", "--plain", "--no-legend", "--no-page"]
SYSTEMCTL_CMD = "/usr/bin/systemctl"


output_data = {"errorString": "", "error": 0, "version": 1, "data": None}
systemctl_data = {
    "load": {
        "stub": None,
        "loaded": None,
        "not-found": None,
        "bad-setting": None,
        "error": None,
        "merged": None,
        "masked": None,
        "total": None,
    },
    "active": {
        "active": None,
        "reloading": None,
        "inactive": None,
        "failed": None,
        "activating": None,
        "deactivating": None,
        "maintenance": None,
        "total": None,
    },
    "sub": {
        "automount": {
            "dead": None,
            "waiting": None,
            "running": None,
            "failed": None,
            "total": None,
        },
        "device": {"dead": None, "tentative": None, "plugged": None, "total": None},
        "freezer": {
            "running": None,
            "freezing": None,
            "frozen": None,
            "thawing": None,
            "total": None,
        },
        "mount": {
            "dead": None,
            "mounting": None,
            "mounting-done": None,
            "mounted": None,
            "remounting": None,
            "unmounting": None,
            "remounting-sigterm": None,
            "remounting-sigkill": None,
            "unmounting-sigterm": None,
            "unmounting-sigkill": None,
            "failed": None,
            "cleaning": None,
            "total": None,
        },
        "path": {
            "dead": None,
            "waiting": None,
            "running": None,
            "failed": None,
            "total": None,
        },
        "scope": {
            "dead": None,
            "start-chown": None,
            "running": None,
            "abandoned": None,
            "stop-sigterm": None,
            "stop-sigkill": None,
            "failed": None,
            "total": None,
        },
        "service": {
            "dead": None,
            "condition": None,
            "start-pre": None,
            "start": None,
            "start-post": None,
            "running": None,
            "exited": None,
            "reload": None,
            "stop": None,
            "stop-watchdog": None,
            "stop-sigterm": None,
            "stop-sigkill": None,
            "stop-post": None,
            "final-watchdog": None,
            "final-sigterm": None,
            "final-sigkill": None,
            "failed": None,
            "auto-restart": None,
            "cleaning": None,
            "total": None,
        },
        "slice": {"dead": None, "active": None, "total": None},
        "socket": {
            "dead": None,
            "start-pre": None,
            "start-chown": None,
            "start-post": None,
            "listening": None,
            "running": None,
            "stop-pre": None,
            "stop-pre-sigterm": None,
            "stop-pre-sigkill": None,
            "stop-post": None,
            "final-sigterm": None,
            "final-sigkill": None,
            "failed": None,
            "cleaning": None,
            "total": None,
        },
        "swap": {
            "dead": None,
            "activating": None,
            "activating-done": None,
            "active": None,
            "deactivating": None,
            "deactivating-sigterm": None,
            "deactivating-sigkill": None,
            "failed": None,
            "cleaning": None,
            "total": None,
        },
        "target": {"dead": None, "active": None, "total": None},
        "timer": {
            "dead": None,
            "waiting": None,
            "running": None,
            "elapsed": None,
            "failed": None,
            "total": None,
        },
    },
}


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
        output_data["error"] = 1
        output_data["errorString"] = "Config file Error: '%s'" % err

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
        systemctl_process = subprocess.Popen(
            systemctl_cmd,
            stdin=None,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        poutput, perror = systemctl_process.communicate()

        if perror:
            raise subprocess.CalledProcessError(
                perror.decode("utf-8"), cmd=systemctl_cmd
            )
    except (subprocess.CalledProcessError, OSError) as err:
        poutput = b""
        output_data["error"] = 1
        output_data["errorString"] = "Command Execution Error: '%s'" % err
    return poutput


def unit_parser(line):
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
        sub_type = line_parsed[0][::-1].split(".")[0][::-1]
        load_state = line_parsed[1]
        active_state = line_parsed[2]
        sub_state = line_parsed[3]

        # Increment operators
        systemctl_data["load"][load_state] = (
            1
            if systemctl_data["load"][load_state] is None
            else (systemctl_data["load"][load_state] + 1)
        )
        systemctl_data["load"]["total"] = (
            1
            if systemctl_data["load"]["total"] is None
            else (systemctl_data["load"]["total"] + 1)
        )
        systemctl_data["active"][active_state] = (
            1
            if systemctl_data["active"][active_state] is None
            else (systemctl_data["active"][active_state] + 1)
        )
        systemctl_data["active"]["total"] = (
            1
            if systemctl_data["active"]["total"] is None
            else (systemctl_data["active"]["total"] + 1)
        )
        systemctl_data["sub"][sub_type][sub_state] = (
            1
            if systemctl_data["sub"][sub_type][sub_state] is None
            else (systemctl_data["sub"][sub_type][sub_state] + 1)
        )
        systemctl_data["sub"][sub_type]["total"] = (
            1
            if systemctl_data["sub"][sub_type]["total"] is None
            else (systemctl_data["sub"][sub_type]["total"] + 1)
        )
    except (IndexError, KeyError) as err:
        print(line_parsed)
        output_data["error"] = 1
        output_data["errorString"] = "Command Output Parsing Error: '%s'" % err


def null_eraser():
    """
    null_eraser(): Helper function to set all null values in the dictionary to '0'
                   if no errors were encountered during script execution.

    Inputs:
        None
    Outputs:
        None
    """
    for state_type in ["active", "load"]:
        for state_value, state_count in systemctl_data[state_type].items():
            if state_count is None:
                systemctl_data[state_type][state_value] = 0
    for sub_state_type in systemctl_data["sub"]:
        for sub_state_value, sub_state_count in systemctl_data["sub"][
            sub_state_type
        ].items():
            if sub_state_count is None:
                systemctl_data["sub"][sub_state_type][sub_state_value] = 0


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
    # Parse configuration file.
    systemctl_cmd = config_file_parser()

    # Execute systemctl command and parse output.
    for line in command_executor(systemctl_cmd).decode("utf-8").split("\n"):
        if not line:
            continue
        unit_parser(line)
    if not output_data["error"]:
        null_eraser()
    output_data["data"] = systemctl_data
    print(json.dumps(output_data))


if __name__ == "__main__":
    main()
