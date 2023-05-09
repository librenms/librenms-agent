#!/usr/bin/env python
#
# Name: linux_config_files Script
# Author: bnerickson <bnerickson87@gmail.com> w/SourceDoctor's certificate.py script forming
#         the base of the vast majority of this one.
# Version: 1.0
# Description: This is a simple script to parse "pkg_tool_cmd" output for ingestion into
#              LibreNMS via the linux_config_files application.  Additional distribution
#              support may be added.
# Installation:
#     1. Copy this script to /etc/snmp/ and make it executable:
#         chmod +x /etc/snmp/linux_config_files.py
#     2. Edit your snmpd.conf and include:
#         extend linux_config_files /etc/snmp/linux_config_files.py
#     3. (Optional, if RPM-based) Create a /etc/snmp/linux_config_files.json file and specify:
#           a.) "pkg_system" - String designating the distribution name of the system.  At
#                              the moment only "rpm" is supported.
#           b.) "pkg_tool_cmd" - String path to the package tool binary ["/sbin/rpmconf"]
#         ```
#         {
#             "pkg_system": "rpm",
#             "pkg_tool_cmd": "/bin/rpmconf",
#         }
#         ```
#     4. Restart snmpd and activate the app for desired host.

import json
import subprocess
import sys

CONFIG_FILE = "/etc/snmp/linux_config_files.json"
PKG_SYSTEM = "rpm"
PKG_TOOL_ARGS = {"rpm": ["--all", "--test"]}
PKG_TOOL_CMD = {"rpm": "/sbin/rpmconf"}


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
        pkg_system: The package management used by the system.
        pkg_tool_cmd: The full package tool command to execute.
    """
    pkg_system = PKG_SYSTEM
    pkg_tool_cmd = [PKG_TOOL_CMD[pkg_system]]

    # Load configuration file if it exists
    try:
        with open(CONFIG_FILE, "r") as json_file:
            config_file = json.load(json_file)
            if "pkg_system" in config_file:
                pkg_system = config_file["pkg_system"].strip().lower()
            pkg_tool_cmd = (
                [config_file["pkg_tool_cmd"].strip().lower()]
                if "pkg_tool_cmd" in config_file
                else [PKG_TOOL_CMD[pkg_system]]
            )
    except FileNotFoundError:
        pass
    except (KeyError, PermissionError, OSError, json.decoder.JSONDecodeError) as err:
        error_handler("Config File Error", err)

    # Create and return pkg_system & full pkg_tool_cmd command.
    pkg_tool_cmd.extend(PKG_TOOL_ARGS[pkg_system])
    return pkg_system, pkg_tool_cmd


def command_executor(pkg_system, pkg_tool_cmd):
    """
    command_executor(): Execute the pkg_tool_cmd command and return the output.

    Inputs:
        pkg_system: The package management used by the system.
        pkg_tool_cmd: The full package tool command to execute.
    Outputs:
        poutput: The stdout of the executed command (empty byte-string if error).
    """
    poutput = None
    try:
        # Execute pkg_tool_cmd command
        poutput = subprocess.check_output(
            pkg_tool_cmd,
            stdin=None,
            stderr=subprocess.PIPE,
        )
    except (subprocess.CalledProcessError, OSError) as err:
        # Per rpmconf man page, an error code of 5 indicates there are conf file
        # to merge, so disregard that error code.
        if err.returncode != 5 or pkg_system != "rpm":
            error_handler("Command Execution Error", err)
        poutput = err.output
    return poutput


def output_parser(pkg_system, cmd_output):
    """
    output_parser(): Parses stdout of executed command and returns updated dictionary
                     with parsed data.

    Inputs:
        pkg_system: The package management used by the system.
        cmd_output: stdout of the executed command.
    Outputs:
        output_data: Dictionary updated with parsed data.
    """
    output_data = {
        "errorString": "",
        "error": 0,
        "version": 1,
        "data": {"number_of_confs": None},
    }

    if pkg_system == "rpm":
        if not cmd_output:
            output_data["data"]["number_of_confs"] = 0
        else:
            output_data["data"]["number_of_confs"] = len(
                cmd_output.decode("utf-8").strip().split("\n")
            )

    return output_data


def main():
    """
    main(): main function that delegates config file parsing, command execution,
            and unit stdout parsing.  Then it prints out the expected json output
            for the pkg_tool_cmd application.

    Inputs:
        None
    Outputs:
        None
    """
    # Parse configuration file.
    pkg_system, pkg_tool_cmd = config_file_parser()

    # Execute pkg_tool_cmd command and parse output.
    cmd_output = command_executor(pkg_system, pkg_tool_cmd)

    # Parse command output.
    output_data = output_parser(pkg_system, cmd_output)

    # Print json dumps of dictionary.
    print(json.dumps(output_data))


if __name__ == "__main__":
    main()
