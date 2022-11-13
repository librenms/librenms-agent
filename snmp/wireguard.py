#!/usr/bin/env python
#
# Name: Wireguard Script
# Author: bnerickson <bnerickson87@gmail.com> w/SourceDoctor's certificate.py script forming the
#         base of the vast majority of this one.
# Version: 1.0
# Description: This is a simple script to parse "wg show all" output for ingestion into LibreNMS
#              via the wireguard application.  We collect traffic, a friendly identifier (arbitrary
#              name), and last handshake time for all clients on all wireguard interfaces.
# Installation:
#     1. Copy this script to /etc/snmp/ and make it executable:
#         chmod +x /etc/snmp/wireguard.py
#     2. Edit your snmpd.conf and include:
#         extend wireguard /etc/snmp/wireguard.py
#     3. Create a /etc/snmp/wireguard.json file and specify:
#           a.) (optional) "wg_cmd" - String path to the wg binary ["/usr/bin/wg"]
#           b.) "public_key_to_arbitrary_name" - A dictionary to convert between the publickey
#                                                assigned to the client (specified in the wireguard
#                                                interface conf file) to an arbitrary, friendly
#                                                name.  The friendly names MUST be unique within
#                                                each interface.  Also note that the interface name
#                                                and friendly names are used in the RRD filename,
#                                                so using special characters is highly discouraged.
#         ```
#         {
#             "wg_cmd": "/bin/wg",
#             "public_key_to_arbitrary_name": {
#                 "wg0": {
#                     "z1iSIymFEFi/PS8rR19AFBle7O4tWowMWuFzHO7oRlE=": "client1",
#                     "XqWJRE21Fw1ke47mH1yPg/lyWqCCfjkIXiS6JobuhTI=": "server.domain.com"
#                 }
#             }
#         }
#         ```
#     4. Restart snmpd and activate the app for desired host.
# TODO:
#     1. If Wireguard ever implements a friendly identifier, then scrape that instead of providing
#        arbitrary names manually in the json conf file.

import json
import subprocess
import sys
from datetime import datetime
from itertools import chain

CONFIG_FILE = "/etc/snmp/wireguard.json"
WG_ARGS = ["show", "all", "dump"]
WG_CMD = "/usr/bin/wg"


def error_handler(error_name, err):
    """
    error_handler(): Common error handler for config/output parsing and command execution.  We set
                     the data to none and print out the json.
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
        "data": {},
    }
    print(json.dumps(output_data))
    sys.exit(1)


def config_file_parser():
    """
    config_file_parser(): Parse the config file and extract the necessary parameters.

    Inputs:
        None
    Outputs:
        wg_cmd: The full wg command to execute.
        interface_clients_dict: Dictionary mapping of interface names to public_key->client names.
    """
    # Load configuration file if it exists
    try:
        with open(CONFIG_FILE, "r") as json_file:
            config_file = json.load(json_file)
            interface_clients_dict = config_file["public_key_to_arbitrary_name"]
            wg_cmd = [config_file["wg_cmd"]] if "wg_cmd" in config_file else [WG_CMD]
    except (
        FileNotFoundError,
        KeyError,
        PermissionError,
        OSError,
        json.decoder.JSONDecodeError,
    ) as err:
        error_handler("Config File Error", err)

    # Create and return full wg command.
    wg_cmd.extend(WG_ARGS)
    return wg_cmd, interface_clients_dict


def config_file_validator(interface_clients_dict):
    """
    config_file_validator(): Verifies the uniqueness of the arbitrary names in the interface to
                             public_key->client names dictionary.

    Inputs:
        interface_clients_dict: Dictionary mapping of interface names to public_key->client names.
    Outputs:
        None
    """
    # Search for valid, unique arbitrary names
    for interface, public_key_to_arbitrary_name in interface_clients_dict.items():
        rev_dict = {}
        for public_key, arbitrary_name in public_key_to_arbitrary_name.items():
            rev_dict.setdefault(str(arbitrary_name), set()).add(public_key)

        # Verify the arbitrary names set in the wireguard.json file are unique.
        result = set(
            chain.from_iterable(
                arbitrary_name
                for public_key, arbitrary_name in rev_dict.items()
                if len(arbitrary_name) > 1
            )
        )
        if not result:
            continue

        err = (
            "%s interface has non-unique arbitrary names configured for public keys %s"
            % (interface, str(result))
        )
        error_handler("Config File Error", err)


def command_executor(wg_cmd):
    """
    command_executor(): Execute the wg command and return the output.

    Inputs:
        wg_cmd: The full wg command to execute.
    Outputs:
        poutput: The stdout of the executed command (empty byte-string if error).
    """
    try:
        # Execute wg command
        poutput = subprocess.check_output(
            wg_cmd,
            stdin=None,
            stderr=subprocess.PIPE,
        )
    except (subprocess.CalledProcessError, OSError) as err:
        error_handler("Command Execution Error", err)
    return poutput


def output_parser(line, interface_clients_dict):
    """
    output_parser(): Parses a line from the wg command for the client's public key, traffic inbound
                     and outbound, wireguard interface, and last handshake timestamp.

    Inputs:
        line: The wireguard client status line from the wg command stdout.
        interface_clients_dict: Dictionary mapping of interface to public_key->client names.
    Outputs:
        wireguard_data: A dictionary of a peer's server interface, public key, bytes sent and
                        received, and minutes since last handshake
    """
    line_parsed = line.strip().split()

    try:
        interface = str(line_parsed[0])
        public_key = str(line_parsed[1])
        timestamp = int(line_parsed[5])
        bytes_rcvd = int(line_parsed[6])
        bytes_sent = int(line_parsed[7])
    except (IndexError, ValueError) as err:
        error_handler("Command Output Parsing Error", err)

    # Return an empty dictionary if the interface is not in the dictionary.
    if interface not in interface_clients_dict:
        return {}

    # Return an empty dictionary if there is no public key to arbitrary name mapping.
    if public_key not in interface_clients_dict[interface]:
        return {}

    # Perform in-place replacement of publickeys with arbitrary names.
    friendly_name = str(interface_clients_dict[interface][public_key])

    # Calculate minutes since last handshake here
    last_handshake_timestamp = datetime.fromtimestamp(timestamp) if timestamp else 0
    minutes_since_last_handshake = (
        int((datetime.now() - last_handshake_timestamp).total_seconds() / 60)
        if last_handshake_timestamp
        else None
    )

    wireguard_data = {
        interface: {
            friendly_name: {
                "minutes_since_last_handshake": minutes_since_last_handshake,
                "bytes_rcvd": bytes_rcvd,
                "bytes_sent": bytes_sent,
            }
        }
    }

    return wireguard_data


def main():
    """
    main(): main function that delegates config file parsing, command execution, and unit stdout
            parsing.  Then it prints out the expected json output for the wireguard application.

    Inputs:
        None
    Outputs:
        None
    """
    output_data = {"errorString": "", "error": 0, "version": 1, "data": {}}

    # Parse configuration file.
    wg_cmd, interface_clients_dict = config_file_parser()

    # Verify contents of the config file are valid.
    config_file_validator(interface_clients_dict)

    # Execute wg command and parse output. We skip the first line ("[1:]") since that's the
    # wireguard server's public key declaration.
    for line in command_executor(wg_cmd).decode("utf-8").split("\n")[1:]:
        if not line:
            continue
        # Parse each line and import the resultant dictionary into output_data.  We update the
        # interface key with new clients as they are found and instantiate new interface keys as
        # they are found.
        for intf, intf_data in output_parser(line, interface_clients_dict).items():
            if intf not in output_data["data"]:
                output_data["data"][intf] = {}
            for client, client_data in intf_data.items():
                output_data["data"][intf][client] = client_data

    print(json.dumps(output_data))


if __name__ == "__main__":
    main()
