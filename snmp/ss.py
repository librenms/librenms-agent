#!/usr/bin/env python
#
# Name: Socket Statistics Script
# Author: bnerickson <bnerickson87@gmail.com> w/SourceDoctor's certificate.py script forming
#         the base of the vast majority of this one.
# Version: 1.0
# Description: This is a simple script to parse "ss" output for ingestion into
#              LibreNMS via the ss application.
# Installation:
#     1. Copy this script to /etc/snmp/ and make it executable:
#         chmod +x /etc/snmp/ss.py
#     2. Edit your snmpd.conf and include:
#         extend ss /etc/snmp/ss.py
#     3. (Optional) Create a /etc/snmp/ss.json file and specify:
#           a.) "ss_cmd"        - String path to the ss binary: ["/sbin/ss"]
#           b.) "socket_types"  - A comma-delimited list of socket types to include.
#                                 The following socket types are valid: dccp, icmp6,
#                                 mptcp, p_dgr, p_raw, raw, sctp, tcp, ti_dg, ti_rd,
#                                 ti_sq, ti_st, u_dgr, u_seq, u_str, udp, unknown,
#                                 v_dgr, v_dgr, xdp.  Please note that the "unknown"
#                                 socket type is represented in ss output with the
#                                 netid "???".  Please also note that the p_dgr and
#                                 p_raw socket types are specific to the "link"
#                                 address family; the ti_dg, ti_rd, ti_sq, and ti_st
#                                 socket types are specific to the "tipc" address
#                                 family; the u_dgr, u_seq, and u_str socket types
#                                 are specific to the "unix" address family; and the
#                                 v_dgr and v_str socket types are specific to the
#                                 "vsock" address family.  Filtering out the parent
#                                 address families for the aforementioned will also
#                                 filter out their specific socket types.  Specifying
#                                 "all" includes all of the socket types.  For
#                                 example: to include only tcp, udp, icmp6 sockets,
#                                 you would specify "tcp,udp,icmp6": ["all"]
#           c.) "addr_families" - A comma-delimited list of address families to
#                                 include.  The following families are valid:
#                                 inet, inet6, link, netlink, tipc, unix, vsock.  As
#                                 mentioned above under (b), filtering out the link,
#                                 tipc, unix, or vsock address families will also
#                                 filter out their respective socket types.
#                                 Specifying "all" includes all of the families.
#                                 For example: to include only inet and inet6
#                                 families, you would specify "inet,inet6": ["all"]
#         ```
#         {
#             "ss_cmd": "/sbin/ss",
#             "socket_types": "all",
#             "addr_families": "all"
#         }
#         ```
#     4. Restart snmpd and activate the app for desired host.

import json
import subprocess
import sys

CONFIG_FILE = "/etc/snmp/ss.json"
SOCKET_MAPPINGS = {
    "dccp": {
        "args": ["--dccp"],
        "netids": [],
        "addr_family": False,
        "socket_type": True,
    },
    "inet": {
        "args": ["--family", "inet"],
        "netids": ["dccp", "mptcp", "raw", "sctp", "tcp", "udp", "unknown"],
        "addr_family": True,
        "socket_type": False,
    },
    "inet6": {
        "args": ["--family", "inet6"],
        "netids": ["dccp", "icmp6", "mptcp", "raw", "sctp", "tcp", "udp", "unknown"],
        "addr_family": True,
        "socket_type": False,
    },
    "link": {
        "args": ["--family", "link"],
        "netids": ["p_dgr", "p_raw", "unknown"],
        "addr_family": True,
        "socket_type": False,
    },
    "mptcp": {
        "args": ["--mptcp"],
        "netids": [],
        "addr_family": False,
        "socket_type": True,
    },
    "netlink": {
        "args": ["--family", "netlink"],
        "netids": [],
        "addr_family": True,
        "socket_type": False,
    },
    "raw": {
        "args": ["--raw"],
        "netids": [],
        "addr_family": False,
        "socket_type": True,
    },
    "sctp": {
        "args": ["--sctp"],
        "netids": [],
        "addr_family": False,
        "socket_type": True,
    },
    "tcp": {
        "args": ["--tcp"],
        "netids": [],
        "addr_family": False,
        "socket_type": True,
    },
    "tipc": {
        "args": ["--family", "tipc"],
        "netids": ["ti_dg", "ti_rd", "ti_sq", "ti_st", "unknown"],
        "addr_family": True,
        "socket_type": False,
    },
    "udp": {
        "args": ["--udp"],
        "netids": [],
        "addr_family": False,
        "socket_type": True,
    },
    "unix": {
        "args": ["--family", "unix"],
        "netids": ["u_dgr", "u_seq", "u_str"],
        "addr_family": True,
        "socket_type": False,
    },
    "vsock": {
        "args": ["--family", "vsock"],
        "netids": ["v_dgr", "v_str", "unknown"],
        "addr_family": True,
        "socket_type": False,
    },
    "xdp": {
        "args": ["--xdp"],
        "netids": [],
        "addr_family": False,
        "socket_type": True,
    },
}
GLOBAL_ARGS = ["--all", "--no-header"]
ADDR_FAMILY_ALLOW_LIST = []
SOCKET_ALLOW_LIST = []

# Populate the state allow lists.
for gentype_key, gentype_values in SOCKET_MAPPINGS.items():
    if gentype_values["socket_type"]:
        SOCKET_ALLOW_LIST.append(gentype_key)
    if gentype_values["addr_family"]:
        ADDR_FAMILY_ALLOW_LIST.append(gentype_key)
    for gentype_netid in gentype_values["netids"]:
        SOCKET_ALLOW_LIST.append(gentype_netid)

SS_CMD = ["/sbin/ss"]


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
        "errorString": f"{error_name}: '{err}'",
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
        ss_cmd: The full ss command to execute.
        socket_allow_list: A list of the socket types to parse output for.
    """
    ss_cmd = SS_CMD.copy()
    socket_allow_list = SOCKET_ALLOW_LIST.copy()
    addr_family_allow_list = ADDR_FAMILY_ALLOW_LIST.copy()

    # Load configuration file if it exists
    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as json_file:
            config_file = json.load(json_file)
            ss_cmd = [config_file["ss_cmd"]]
            socket_allow_list_clean = list(
                map(str.lower, config_file["socket_types"].split(","))
            )
            addr_family_allow_list_clean = list(
                map(str.lower, config_file["addr_families"].split(","))
            )
            if "all" not in socket_allow_list_clean:
                socket_allow_list = socket_allow_list_clean
            if "all" not in addr_family_allow_list_clean:
                addr_family_allow_list = addr_family_allow_list_clean
    except FileNotFoundError:
        pass
    except (KeyError, PermissionError, OSError, json.decoder.JSONDecodeError) as err:
        error_handler("Config File Error", err)

    # Verify the socket types specified by the user are valid.
    err = ""
    for socket_type in socket_allow_list:
        if socket_type in SOCKET_ALLOW_LIST:
            continue
        if not err:
            err = "Invalid socket types specified: "
        err += socket_type + " "
    if err:
        error_handler("Configuration File Error", err.strip())

    # Verify the address families specified by the user are valid.
    err = ""
    for addr_family in addr_family_allow_list:
        if addr_family in ADDR_FAMILY_ALLOW_LIST:
            continue
        if not err:
            err = "Invalid address families specified: "
        err += addr_family + " "
    if err:
        error_handler("Configuration File Error", err.strip())

    # Create and return full ss command and allow lists.
    return ss_cmd, socket_allow_list, addr_family_allow_list


def command_executor(ss_cmd, socket_type):
    """
    command_executor(): Execute the ss command and return the output.

    Inputs:
        ss_cmd: The full ss command to execute.
        socket_type: The type of socket to collect data for.
    Outputs:
        poutput: The stdout of the executed command (empty byte-string if error).
    """
    ss_socket_cmd = ss_cmd.copy()
    ss_socket_cmd.extend(SOCKET_MAPPINGS[socket_type]["args"])
    ss_socket_cmd.extend(GLOBAL_ARGS)

    try:
        # Execute ss command
        poutput = subprocess.check_output(
            ss_socket_cmd,
            stdin=None,
            stderr=subprocess.PIPE,
        )
    except (subprocess.CalledProcessError, OSError) as err:
        error_handler("Command Execution Error", err)
    return poutput


def socket_parser(line, gentype, ss_data, socket_allow_list):
    """
    socket_parser(): Parses a socket line for its current status.
                     That status type is added to the global ss_data
                     variable if it does not exist or incremented if
                     it does.  The totals for the socket type are
                     incremented as well.

    Inputs:
        line: The sockets's status line from the ss stdout.
        gentype: The socket or address family to parse data for.
        ss_data: All of the socket data as a dictionary.
        socket_allow_list: List of sockets to parse data for.
    Outputs:
        None
    """
    line_parsed = line.strip().split()

    netid = None
    state = None

    try:
        if SOCKET_MAPPINGS[gentype]["netids"]:
            netid = line_parsed[0]
            state = line_parsed[1]
        else:
            state = line_parsed[0]
    except IndexError as err:
        error_handler("Command Output Parsing Error", err)

    if SOCKET_MAPPINGS[gentype]["netids"]:
        # Special case to convert the question-marks symbol
        # to a safe string.
        if netid == "???":
            netid = "unknown"

        # Omit filtered sockets from the address families.
        if netid not in socket_allow_list:
            return ss_data

        ss_data[netid][state] = (
            1 if state not in ss_data[netid] else (ss_data[netid][state] + 1)
        )
        ss_data[netid]["TOTAL"] = (
            1 if "TOTAL" not in ss_data[netid] else (ss_data[netid]["TOTAL"] + 1)
        )
    else:
        ss_data[state] = 1 if state not in ss_data else (ss_data[state] + 1)
        ss_data["TOTAL"] = 1 if "TOTAL" not in ss_data else (ss_data["TOTAL"] + 1)

    return ss_data


def main():
    """
    main(): main function that delegates config file parsing, command execution,
            and socket stdout parsing.  Then it prints out the expected json output
            for the ss application.

    Inputs:
        None
    Outputs:
        None
    """
    output_data = {"errorString": "", "error": 0, "version": 1, "data": {}}

    # Parse configuration file.
    ss_cmd, socket_allow_list, addr_family_allow_list = config_file_parser()

    # Execute ss command for socket types.
    for gentype in list(SOCKET_MAPPINGS.keys()):
        # Skip socket types and address families disabled by the user.
        if (
            SOCKET_MAPPINGS[gentype]["socket_type"] and gentype not in socket_allow_list
        ) or (
            SOCKET_MAPPINGS[gentype]["addr_family"]
            and gentype not in addr_family_allow_list
        ):
            continue

        # Build the initial output_data datastructures.
        output_data["data"][gentype] = {}
        for netid in SOCKET_MAPPINGS[gentype]["netids"]:
            # Skip the netid if the socket is not allowed.
            if netid not in socket_allow_list:
                continue
            output_data["data"][gentype][netid] = {}

        for line in command_executor(ss_cmd, gentype).decode("utf-8").split("\n"):
            if not line:
                continue

            output_data["data"][gentype] = socket_parser(
                line,
                gentype,
                output_data["data"][gentype],
                socket_allow_list,
            )

    print(json.dumps(output_data))


if __name__ == "__main__":
    main()
