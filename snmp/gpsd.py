#!/usr/bin/env python
"""
Name: GPSD Script
Author: bnerickson <bnerickson87@gmail.com> w/SourceDoctor's certificate.py script forming
        the base of the vast majority of this one
Version: 1.0
Description: This script emulates the functionality of the gpsd bash script using native python;
             it outputs the mode, hdop, vdop, latitude, longitude, altitude, number of total
             satellites, and number of satellites used parsed from gpsd using gpspipe; it also
             supports caching gpspipe data into a cache file to speed up the snmp transaction
Installation:
    1. Copy this script to /etc/snmp/ and make it executable:
           chmod +x /etc/snmp/gpsd.py
    2. Edit your snmpd.conf and include:
            extend ss /etc/snmp/gpsd.py
    3. (Optional) Create a /etc/snmp/gpsd.json file and specify:
            a.) "cache_file"    - String path to the cache file: ["/var/cache/librenms/gpsd.json"]
            b.) "gpspipe_cmd"   - String path to the gpspipe binary: ["/usr/bin/gpspipe"]
            c.) "packet_count"  - An integer specifying the number of packets to receive from gpsd
                                  before terminating: [20]
            d.) Example file format
                {
                    "cache_file": "/var/cache/librenms/gpsd.json",
                    "gpspipe_cmd": "/usr/bin/gpspipe",
                    "packet_count": 20
                }
    4. (Optional, but recommended) Create an /etc/cron.d/gpsd file to build the cache file every
       5 minutes with the following contents:
           */5 * * * * root /etc/snmp/gpsd.py -m
    5. Restart snmpd and activate the app for desired host
"""

import argparse
import json
import subprocess
import sys

CACHE_FILE = "/var/cache/librenms/gpsd.json"
CACHE_TIME = 30
DEFAULT_CONFIG_FILE = "/etc/snmp/gpsd.json"
PACKET_COUNT = 20
GLOBAL_ARGS = ["--json", "--count"]
GPSPIPE = ["/usr/bin/gpspipe"]


def error_handler(error_name, err):
    """
    error_handler(): Common error handler for config/output parsing and
                     command execution
    Inputs:
        error_name: String describing the error handled
        err: The error message in its entirety
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


def parse_args():
    """
    parse_args(): Handles script arguments
    Inputs:
        None
    Outputs:
        parser: argparse.ArgumentParser object
    """
    parser = argparse.ArgumentParser(
        description="Socket Statistics Script for LibreNMS"
    )
    parser.add_argument(
        "-m",
        "--make-cache",
        action="store_true",
        default=False,
        dest="make_cache",
        help="Create cache file of latest gpspipe output",
        required=False,
    )
    parser.add_argument(
        "-r",
        "--config",
        default=DEFAULT_CONFIG_FILE,
        dest="config",
        help="Path to configuration JSON file (default: /etc/snmp/ss.json)",
        required=False,
        type=str,
    )
    return parser.parse_args()


def config_file_parser(config_path):
    """
    config_file_parser(): Parses the config file (if it exists) and extracts the
                          necessary parameters

    Inputs:
        None
    Outputs:
        cache_file: String full path to the cache file
        cmd: String full path of the command to execute
        packet_count: Integer count of packets to grab from gpspipe
    """
    cmd = GPSPIPE.copy()
    packet_count = PACKET_COUNT
    cache_file = CACHE_FILE

    # Load configuration file if it exists
    try:
        with open(config_path, "r", encoding="utf-8") as f:
            config_file = json.load(f)
            if "cache_file" in config_file:
                cache_file = config_file["cache_file"]
            if "gpspipe_cmd" in config_file:
                cmd = [config_file["gpspipe_cmd"]]
            if "packet_count" in config_file:
                packet_count = int(config_file["packet_count"])
    except FileNotFoundError:
        pass
    except (KeyError, PermissionError, OSError, json.decoder.JSONDecodeError) as err:
        error_handler("Config File Error", err)

    # Create and return full command and packet count
    return cache_file, cmd, packet_count


def command_executor(cmd, packet_count):
    """
    command_executor(): Execute the ss command and return the output

    Inputs:
        cmd: String full path of the command to execute
        packet_count: Integer count of packets to grab from gpspipe
    Outputs:
        poutput: The stdout of the executed command (empty byte-string if error)
    """
    final_cmd = cmd.copy()
    final_cmd.extend(GLOBAL_ARGS)
    final_cmd.append(str(packet_count))

    try:
        # Execute command
        poutput = subprocess.check_output(
            final_cmd,
            stdin=None,
            stderr=subprocess.PIPE,
        )
    except (subprocess.CalledProcessError, OSError) as err:
        error_handler("Command Execution Error", err)
    return poutput


def gpspipe_parser(cmd, packet_count):
    """
    gpspipe_parser():  Executes gpspipe waiting for the specified packet_count, merged the output
                       into a single dictionary, and returns it to the calling function

    Inputs:
        cmd: String full path of the command to execute
        packet_count: Integer count of packets to grab from gpspipe
    Outputs:
        merged_dictionary: Dictionary of all fields merged from gpspipe output
    """
    merged_dictionary = {}

    # Run the gpspipe command, because this iterates from top-to-bottom, only the LATEST data
    # within the packet count window will be processed
    for line in command_executor(cmd, packet_count).decode("utf-8").split("\n"):
        if not line:
            continue

        gpspipe_line_dict = json.loads(line)

        # Sometimes, gpspipe outputs SKY values that have no satellite information whatsoever,
        # this exception ignores those lines if-any-only-if a SKY value with satellite information
        # already exists in the output we have grabbed so far
        if (
            gpspipe_line_dict["class"] == "SKY"
            and "SKY" in merged_dictionary
            and "satellites" in merged_dictionary["SKY"]
            and "satellites" not in gpspipe_line_dict
        ):
            continue

        # Set the latest class key values to the values in the given line
        merged_dictionary[gpspipe_line_dict["class"]] = gpspipe_line_dict

    return merged_dictionary


def gpspipe_handler(cache_file, cmd, packet_count):
    """
    gpspipe_handler(): Grabs gpspipe output from the cache file if it exists and if it does not,
                       then grab the gpspipe data in a JIT; parse the output before returning it
                       to the main function in the proper format

    Inputs:
        cache_file: String full path to the cache file
        cmd: String full path of the command to execute
        packet_count: Integer count of packets to grab from gpspipe
    Outputs:
        final_dictionary: Dictionary that will be in the output["data"] field printed to stdout
        version: String version that will be in the output["version"] field printed to stdout
    """
    merged_dictionary = {}

    # Try to load cached data first
    try:
        with open(cache_file, "r", encoding="utf-8") as f:
            merged_dictionary = json.load(f)
    except FileNotFoundError:
        pass
    except (PermissionError, OSError, json.decoder.JSONDecodeError) as err:
        error_handler("Cache File Error", err)

    # If there is no cached data, pull it JIT
    if not merged_dictionary:
        merged_dictionary = gpspipe_parser(cmd, packet_count)

    # If there is still no data, create the default expected data structure
    if not merged_dictionary or type(merged_dictionary) is not dict:
        merged_dictionary = {"TPV": {}, "SKY": {}}
    if "TPV" not in merged_dictionary:
        merged_dictionary["TPV"] = {}
    if "SKY" not in merged_dictionary:
        merged_dictionary["SKY"] = {}

    # Format the parsed data into the values expected by librenms
    final_dictionary = {
        "mode": (
            merged_dictionary["TPV"]["mode"]
            if "mode" in merged_dictionary["TPV"]
            else ""
        ),
        "hdop": (
            merged_dictionary["SKY"]["hdop"]
            if "hdop" in merged_dictionary["SKY"]
            else ""
        ),
        "vdop": (
            merged_dictionary["SKY"]["vdop"]
            if "vdop" in merged_dictionary["SKY"]
            else ""
        ),
        "latitude": (
            merged_dictionary["TPV"]["lat"] if "lat" in merged_dictionary["TPV"] else ""
        ),
        "longitude": (
            merged_dictionary["TPV"]["lon"] if "lon" in merged_dictionary["TPV"] else ""
        ),
        "altitude": (
            merged_dictionary["TPV"]["alt"] if "alt" in merged_dictionary["TPV"] else ""
        ),
        "satellites": (
            str(merged_dictionary["SKY"]["nSat"])
            if "nSat" in merged_dictionary["SKY"]
            else "0"
        ),
        "satellites_used": (
            str(merged_dictionary["SKY"]["uSat"])
            if "uSat" in merged_dictionary["SKY"]
            else "0"
        ),
    }
    version = merged_dictionary["VERSION"]["release"]

    return final_dictionary, version


def make_cache(cache_file, cmd, packet_count):
    """
    make_cache(): Executes gpspipe and creates a cache json file out from the results

    Inputs:
        cache_file: String full path to the cache file
        cmd: String full path of the command to execute
        packet_count: Integer count of packets to grab from gpspipe
    Outputs:
        None
    """
    merged_dictionary = gpspipe_parser(cmd, packet_count)

    with open(cache_file, "w", encoding="utf-8") as f:
        f.write(json.dumps(merged_dictionary))


def main():
    """
    main(): main function that delegates config file parsing, delegates gpspipe command exection
            and results parsing, delegates cache file creation, and outputs the json expected by
            librenms

    Inputs:
        None
    Outputs:
        None
    """
    # Parse configuration file
    args = parse_args()
    cache_file, cmd, packet_count = config_file_parser(args.config)

    # Create the cache file if requested and exit
    if args.make_cache:
        make_cache(cache_file, cmd, packet_count)
        sys.exit(0)

    output_data = {"errorString": "", "error": 0, "version": "", "data": {}}
    # Execute gpspipe command and parse output
    output_data["data"], output_data["version"] = gpspipe_handler(
        cache_file, cmd, packet_count
    )

    print(json.dumps(output_data))


if __name__ == "__main__":
    main()
