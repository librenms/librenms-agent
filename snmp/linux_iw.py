#!/usr/bin/env python

"""
Name: linux_iw Script
Author: bnerickson <bnerickson87@gmail.com> w/SourceDoctor's certificate.py script forming the base
        of the vast majority of this one.
Version: 1.0
Description: This is a simple script to parse iw command output for ingestion into LibreNMS via the
             linux_iw application.  This script can be used on wireless clients as well as wireless
             access points.
Installation:
    1. Copy this script to /etc/snmp/ and make it executable:
        chmod +x /etc/snmp/linux_iw.py
    2. Edit your snmpd.conf and include:
        extend linux_iw /etc/snmp/linux_iw.py
    3. (optional) Create a /etc/snmp/linux_iw.json file and specify:
          a.) (optional) "linux_iw_cap_lifetime" - Specify the number of days a dead client (for
              APs) or AP (for clients) should remain on the graphs in LibreNMS before being removed
              (data is not removed, however).  There are two special values that can also be used:
              specifying '0' will never expire any client and specifying '-1' (or any negative
              value) will result in NO client wireless metrics being graphed in LibreNMS [global
              default: 0]
          b.) (optional) "iw_cmd" - String path to the wg binary [default: "/usr/sbin/iw"]
          c.) (optional) "mac_addr_to_friendly_name" - A dictionary to convert between the wireless
              mac address and a friendly, arbitrary name for wireless clients.  This name will be
              used on the graph titles in LibreNMS, so it's just for readability and easier human =
              parsing of data.
        ```
        {
            "linux_iw_cap_lifetime": 50,
            "iw_cmd": "/bin/iw",
            "mac_addr_to_friendly_name": {
                "00:53:00:00:00:01": "client_1.domain.tlv",
                "00:53:ff:ff:ff:ff": "my_tablet"
            }
        }
        ```
    4. Restart snmpd and activate the app for desired host.
"""

import json
import re
import subprocess
import sys

VALID_MAC_ADDR = (
    r"([0-9a-fA-F][0-9a-fA-F]:"
    + r"[0-9a-fA-F][0-9a-fA-F]:"
    + r"[0-9a-fA-F][0-9a-fA-F]:"
    + r"[0-9a-fA-F][0-9a-fA-F]:"
    + r"[0-9a-fA-F][0-9a-fA-F]:"
    + r"[0-9a-fA-F][0-9a-fA-F])"
)
CONFIG_FILE = "/etc/snmp/linux_iw.json"
INITIAL_REGEX_MAPPER = {
    "interfaces": {
        "regex": r"(?m)\s+Interface (.+)$",
    },
    "stations": {"regex": r"(?m)^Station " + VALID_MAC_ADDR + r" \(on "},
}
SUB_REGEX_MAPPER = {
    "interface_info": {
        "center1": {
            "regex": (
                r"^\s+channel \d+ \(\d+ MHz\), width: \d+ MHz,.*center1: "
                + r"(\d+) MHz"
            ),
            "variable_type": "type_int",
        },
        "center2": {
            "regex": (
                r"^\s+channel \d+ \(\d+ MHz\), width: \d+ MHz,.*center2: "
                + r"(\d+) MHz"
            ),
            "variable_type": "type_int",
        },
        "channel": {
            "regex": r"^\s+channel \d+ \((\d+) MHz\)",
            "variable_type": "type_int",
        },
        "ssid": {
            "regex": r"^\s+ssid (.+)$",
            "variable_type": "type_string",
        },
        "txpower": {
            "regex": r"^\s+txpower (\d+\.\d+) dBm$",
            "variable_type": "type_float",
        },
        "type": {
            "regex": r"^\s+type (.+)$",
            "variable_type": "type_string",
        },
        "width": {
            "regex": r"^\s+channel \d+ \(\d+ MHz\), width: (\d+) MHz",
            "variable_type": "type_int",
        },
    },
    "station_get": {
        "beacon_interval": {
            "regex": r"^\s+beacon interval:\s*(\d+)$",
            "variable_type": "type_int",
        },
        "connected_time": {
            "regex": r"^\s+connected time:\s*(\d+) seconds$",
            "variable_type": "type_int",
        },
        "dtim_interval": {
            "regex": r"^\s+DTIM period:\s*(\d+)$",
            "variable_type": "type_int",
        },
        "inactive_time": {
            "regex": r"^\s+inactive time:\s*(\d+) ms$",
            "variable_type": "type_int",
        },
        "rx_bitrate": {
            "regex": r"^\s+rx bitrate:\s*(\d+\.\d+) MBit\/s.*",
            "variable_type": "type_float",
        },
        "rx_bytes": {
            "regex": r"^\s+rx bytes:\s*(\d+)$",
            "variable_type": "type_int",
        },
        "rx_drop_misc": {
            "regex": r"^\s+rx drop misc:\s*(\d+)$",
            "variable_type": "type_int",
        },
        "rx_duration": {
            "regex": r"^\s+rx duration:\s*(\d+) us$",
            "variable_type": "type_int",
        },
        "rx_packets": {
            "regex": r"^\s+rx packets:\s*(\d+)$",
            "variable_type": "type_int",
        },
        "signal": {
            "regex": r"^\s+signal:\s*(-?\d+) \[-?\d+, -?\d+\] dBm$",
            "variable_type": "type_int",
        },
        "tx_bitrate": {
            "regex": r"^\s+tx bitrate:\s*(\d+\.\d+) MBit\/s.*",
            "variable_type": "type_float",
        },
        "tx_bytes": {
            "regex": r"^\s+tx bytes:\s*(\d+)$",
            "variable_type": "type_int",
        },
        "tx_failed": {
            "regex": r"^\s+tx failed:\s*(\d+)$",
            "variable_type": "type_int",
        },
        "tx_packets": {
            "regex": r"^\s+tx packets:\s*(\d+)$",
            "variable_type": "type_int",
        },
        "tx_retries": {
            "regex": r"^\s+tx retries:\s*(\d+)$",
            "variable_type": "type_int",
        },
    },
    "survey_dump": {
        "noise": {
            "regex": r"^\s+noise:\s*(-?\d+) dBm$",
            "variable_type": "type_int",
        },
        "channel_active_time": {
            "regex": r"^\s+channel active time:\s*(\d+) ms$",
            "variable_type": "type_int",
        },
        "channel_busy_time": {
            "regex": r"^\s+channel busy time:\s*(\d+) ms$",
            "variable_type": "type_int",
        },
        "channel_receive_time": {
            "regex": r"^\s+channel receive time:\s*(\d+) ms$",
            "variable_type": "type_int",
        },
        "channel_transmit_time": {
            "regex": r"^\s+channel transmit time:\s*(\d+) ms$",
            "variable_type": "type_int",
        },
    },
}
IW_CMD = "/usr/sbin/iw"


def error_handler(error_name, err):
    """
    error_handler(): Common error handler for config/output parsing and command execution.
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
        "data": {},
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
        iw_cmd: The full iw binary as a string in a list to execute.
        mac_addr_to_friendly_name: Dictionary mapping of mac addresses to friendly, arbitrary names.
    """
    linux_iw_cap_lifetime = None
    iw_cmd = [IW_CMD]
    mac_addr_to_friendly_name = {}

    # Load configuration file if it exists
    try:
        with open(CONFIG_FILE, "r") as json_file:
            config_file = json.load(json_file)
            if "linux_iw_cap_lifetime" in config_file:
                linux_iw_cap_lifetime = config_file["linux_iw_cap_lifetime"]
            if "iw_cmd" in config_file:
                iw_cmd = [config_file["iw_cmd"]]
            if "mac_addr_to_friendly_name" in config_file:
                # Convert all mac addresses to lower case.
                mac_addr_to_friendly_name = dict(
                    (k.lower(), v)
                    for k, v in config_file["mac_addr_to_friendly_name"].items()
                )
    except FileNotFoundError:
        pass
    except (KeyError, PermissionError, OSError, json.decoder.JSONDecodeError) as err:
        error_handler("Config File Error", err)

    # Create and return full iw command.
    return linux_iw_cap_lifetime, iw_cmd, mac_addr_to_friendly_name


def command_executor(iw_cmd, iw_args, command_output_regex):
    """
    command_executor(): Execute the iw command and return the output.

    Inputs:
        iw_cmd: The full iw binary as a string in a list.
        iw_args: Args to pass to the iw command.
        command_output_refex: Regex to filter output after command execution.
    Outputs:
        poutput: The utf-8-encoded stdout of the executed command.
    """
    try:
        # Execute iw command
        poutput = subprocess.check_output(
            iw_cmd + iw_args,
            stdin=None,
            stderr=subprocess.PIPE,
        )
    except (subprocess.CalledProcessError, OSError) as err:
        error_handler("Command Execution Error", err)

    # Filter stdout with regex if it was passed.
    if command_output_regex:
        regex_search = re.search(command_output_regex, poutput.decode("utf-8"))
        poutput = regex_search.group().encode("utf-8") if regex_search else None

    return poutput


def output_parser(iw_output, iw_regex_dict):
    """
    output_parser(): Parses the iw command output and returns a dictionary
                     of PSU metrics.

    Inputs:
        iw_output: The iw command stdout
        iw_regex_dict: A dictionary of regex and variable type values.
    Outputs:
        iw_data: A dictionary of iw metics.
    """
    iw_data = {}

    if not iw_output:
        return iw_data

    for line in iw_output.decode("utf-8").split("\n"):
        for metric_type, regex_dict in iw_regex_dict.items():
            regex_search = re.search(regex_dict["regex"], line)

            if not regex_search:
                continue

            try:
                metric_value = regex_search.groups()[0]

                if regex_dict["variable_type"] == "type_int":
                    iw_data[metric_type] = int(metric_value)
                if regex_dict["variable_type"] == "type_float":
                    iw_data[metric_type] = float(metric_value)
                if regex_dict["variable_type"] == "type_string":
                    iw_data[metric_type] = str(metric_value)
            except (IndexError, ValueError) as err:
                error_handler("Command Output Parsing Error", err)

    return iw_data


def main():
    """
    main(): main function performs iw command execution and output parsing.

    Inputs:
        None
    Outputs:
        None
    """
    # Parse configuration file.
    linux_iw_cap_lifetime, iw_cmd, mac_addr_to_friendly_name = config_file_parser()

    output_data = {
        "errorString": "",
        "error": 0,
        "version": 1,
        "data": {
            "linux_iw_cap_lifetime": int(linux_iw_cap_lifetime)
            if linux_iw_cap_lifetime
            else None,
            "friendly_names": mac_addr_to_friendly_name,
            "interfaces": {},
        },
    }

    # Get list of interfaces
    interfaces = re.findall(
        INITIAL_REGEX_MAPPER["interfaces"]["regex"],
        command_executor(iw_cmd, ["dev"], None).decode("utf-8"),
    )

    # Get operational mode of each interface.

    # Get interface commands output
    for interface in interfaces:
        output_data["data"]["interfaces"][interface] = {}

        # Get interface info
        output_data["data"]["interfaces"][interface].update(
            output_parser(
                command_executor(iw_cmd, ["dev", interface, "info"], None),
                SUB_REGEX_MAPPER["interface_info"],
            )
        )

        survey_dump_command_output_regex = (
            r"(?m)Survey data from "
            + interface
            + r"\s+frequency:\s*\d+ MHz \[in use\]\n(\s+.*\n)+"
        )
        # Get survey info
        output_data["data"]["interfaces"][interface].update(
            output_parser(
                command_executor(
                    iw_cmd,
                    [interface, "survey", "dump"],
                    survey_dump_command_output_regex,
                ),
                SUB_REGEX_MAPPER["survey_dump"],
            )
        )

        # Get list of stations connected to interface
        stations = re.findall(
            INITIAL_REGEX_MAPPER["stations"]["regex"] + interface + r"\)$",
            command_executor(
                iw_cmd, ["dev", interface, "station", "dump"], None
            ).decode("utf-8"),
        )

        # Get station info
        output_data["data"]["interfaces"][interface]["caps"] = {}
        for station in stations:
            output_data["data"]["interfaces"][interface]["caps"][station] = {}
            output_data["data"]["interfaces"][interface]["caps"][station].update(
                output_parser(
                    command_executor(
                        iw_cmd, ["dev", interface, "station", "get", station], None
                    ),
                    SUB_REGEX_MAPPER["station_get"],
                )
            )

            # Calculate SNR
            if (
                "noise" not in output_data["data"]["interfaces"][interface]
                or "signal"
                not in output_data["data"]["interfaces"][interface]["caps"][station]
            ):
                continue
            output_data["data"]["interfaces"][interface]["caps"][station]["snr"] = (
                output_data["data"]["interfaces"][interface]["caps"][station]["signal"]
                - output_data["data"]["interfaces"][interface]["noise"]
            )

    print(json.dumps(output_data))


if __name__ == "__main__":
    main()
