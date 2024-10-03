#!/usr/bin/python3
#
# Copyright(C) 2021 Ben Carbery yrebrac@upaya.net.au
#
# LICENSE - GPLv3
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# version 3. See https://www.gnu.org/licenses/gpl-3.0.txt
#
# DESCRIPTION
#
# The script attempts to determine the current power consumption of the host via
# one or more methods. The scripts should make it easier to add your own methods
# if no included one is suitable for your host machine.
#
# The script should be called by the snmpd daemon on the host machine. This is
# achieved via the 'extend' functionality in snmpd. For example, in
# /etc/snmp/snmpd.conf:
#       extend      powermon   /usr/local/bin/powermon-snmp.py
#
# CUSTOMISING RESULTS
#
# The results can be accessed via the nsExtend MIBs from another host, e.g.
#   snmpwalk -v 2c -c <community_string> <host> \
#       <nsExtendConfigTable|nsExtendOutputFull|nsExtendOutput1Table>
#
# The results are returned in a JSON format suitable for graphing in LibreNMS.
# A LibreNMS 'application' is available for this purpose.
#
# The application expects to see a single top-level reading in the results in
# terms of Watts. This can be derived from a reading from one of the sub-
# components, currently the ACPI 'meter' or 'psus'. But you must tell the script
# which is the top-level or final reading you want to use in the results. This
# allows you to sum results from dual PSUs or apply your own power factor for
# example.   To achieve this see the definition of 'data["reading"]' at the end
# of the script, and modify as required. Two examples are provided.
#
# If you want to track your electricity cost you should also update the cost
# per kWh value below. When you cost changes you can update the value. The
# supply rate will be returned in the results
#
# COMPATIBILITY
#
# - Linux, not tested on other OS
# - Tested on python 3.6, 3.8
#
# INSTALLATION
#
# - Sensors method: pip install PySensors
# - hpasmcli method: install hp-health package for your distribution
# - Copy this script somewhere, e.g. /usr/local/bin
# - Uncomment costPerkWh and change the value
# - Test then customise top-level reading
# - Add the 'extend' config to snmpd.conf
# - https://docs.librenms.org/Extensions/Applications/#powermon
#
# CHANGELOG
#
# 20210130 - v1.0 - initial, implemented PySensors method
# 20210131 - v1.1 - implemented hpasmcli method
# 20210204 - v1.2 - added top-level reading, librenms option
# 20210205 - v1.3 - added cents per kWh
# 20210205 - v1.4 - improvement to UI
# 20220513 - v1.5 - Add inital IPMItool method

version = 1.5

### Libraries

import getopt
import json
import os
import re
import shutil
import subprocess
import sys

### Option defaults

method = ""  # must be one of methods array
verbose = False
warnings = False
librenms = True  # Return results in a JSON format suitable for Librenms
# Set to false to return JSON data only
pretty = False  # Pretty printing

### Globals

error = 0
errorString = ""
data = {}
result = {}
usage = (
    "USAGE: "
    + os.path.basename(__file__)
    + " [-h|--help] |"
    + " [-m|--method <method>] [-N|--no-librenms] [-p|--pretty]"
    + " [-v|--verbose] [-w|--warnings] | -l|--list-methods | -h|--help"
)
methods = ["sensors", "hpasmcli", "ipmitool"]
# costPerkWh = 0.15  # <<<< CHANGE

### General functions


def errorMsg(message):
    sys.stderr.write("ERROR: " + message + "\n")


def usageError(message="Invalid argument"):
    errorMsg(message)
    sys.stderr.write(usage + "\n")
    sys.exit(1)


def warningMsg(message):
    if verbose or warnings:
        sys.stderr.write("WARN:  " + message + "\n")


def verboseMsg(message):
    if verbose:
        sys.stderr.write("INFO:  " + message + "\n")


def listMethods():
    global verbose
    verbose = True
    verboseMsg("Available methods are: " + str(methods).strip("[]"))


### Data functions


def getData(method):
    if method == "sensors":
        data = getSensorData()

    elif method == "hpasmcli":
        data = getHPASMData()

    elif method == "ipmitool":
        data = getIPMIdata()

    else:
        usageError("You must specify a method.")

    return data


def getSensorData():
    global error, errorString
    error = 2
    errorString = "No power sensor found"

    try:
        import sensors

        sensors.init()

    except ModuleNotFoundError as e:
        errorMsg(str(e))
        verboseMsg("Try 'pip install PySensors'")
        sys.exit(1)

    except FileNotFoundError as e:
        errorMsg("Module 'sensors' appears to be missing a dependancy: " + str(e))
        verboseMsg("Try 'dnf install lm_sensors'")
        sys.exit(1)

    except:
        e = sys.exc_info()
        errorMsg("Module sensors is installed but failed to initialise: " + str(e))
        sys.exit(1)

    sdata = {}
    sdata["meter"] = {}
    sdata["psu"] = {}

    re_meter = "^power_meter"

    power_chips = []
    try:
        for chip in sensors.iter_detected_chips():
            chip_name = str(chip)
            verboseMsg("Found chip: " + chip_name)

            if re.search(re_meter, chip_name):
                verboseMsg("Found power meter: " + chip_name)
                error = 0
                errorString = ""

                junk, meter_id = chip_name.split("acpi-", 1)
                sdata["meter"][meter_id] = {}

                for feature in chip:
                    feature_label = str(feature.label)
                    verboseMsg("Found feature: " + feature_label)

                    if re.search("^power", feature_label):
                        sdata["meter"][meter_id]["reading"] = feature.get_value()

                        if feature.get_value() == 0:
                            # warning as downstream may try to divide by 0
                            warningMsg("Sensors returned a zero value")

                    else:
                        # store anything else in case label is something unexpected
                        sdata[chip_name][feature_label] = feature.get_value()

    except:
        es = sys.exc_info()
        error = 1
        errorString = "Unable to get data: General exception: " + str(es)

    finally:
        sensors.cleanup()
        return sdata


def getHPASMData():
    global error, errorString

    exe = shutil.which("hpasmcli")
    # if not os.access(candidate, os.W_OK):
    cmd = [exe, "-s", "show powermeter; show powersupply"]
    warningMsg("hpasmcli only runs as root")

    try:
        output = subprocess.run(
            cmd, capture_output=True, check=True, text=True, timeout=2
        )

    except subprocess.CalledProcessError as e:
        errorMsg(str(e) + ": " + str(e.stdout).strip("\n"))
        sys.exit(1)

    rawdata = str(output.stdout).replace("\t", " ").replace("\n ", "\n").split("\n")

    hdata = {}
    hdata["meter"] = {}
    hdata["psu"] = {}

    re_meter = "^Power Meter #([0-9]+)"
    re_meter_reading = "^Power Reading  :"
    re_psu = "^Power supply #[0-9]+"
    re_psu_present = "^Present  :"
    re_psu_redundant = "^Redundant:"
    re_psu_condition = "^Condition:"
    re_psu_hotplug = "^Hotplug  :"
    re_psu_reading = "^Power    :"

    for line in rawdata:
        if re.match(re_meter, line):
            verboseMsg("found power meter: " + line)
            junk, meter_id = line.split("#", 1)
            hdata["meter"][meter_id] = {}

        elif re.match(re_meter_reading, line):
            verboseMsg("found power meter reading: " + line)
            junk, meter_reading = line.split(":", 1)
            hdata["meter"][meter_id]["reading"] = meter_reading.strip()

        elif re.match(re_psu, line):
            verboseMsg("found power supply: " + line)
            junk, psu_id = line.split("#", 1)
            hdata["psu"][psu_id] = {}

        elif re.match(re_psu_present, line):
            verboseMsg("found power supply present: " + line)
            junk, psu_present = line.split(":", 1)
            hdata["psu"][psu_id]["present"] = psu_present.strip()

        elif re.match(re_psu_redundant, line):
            verboseMsg("found power supply redundant: " + line)
            junk, psu_redundant = line.split(":", 1)
            hdata["psu"][psu_id]["redundant"] = psu_redundant.strip()

        elif re.match(re_psu_condition, line):
            verboseMsg("found power supply condition: " + line)
            junk, psu_condition = line.split(":", 1)
            hdata["psu"][psu_id]["condition"] = psu_condition.strip()

        elif re.match(re_psu_hotplug, line):
            verboseMsg("found power supply hotplug: " + line)
            junk, psu_hotplug = line.split(":", 1)
            hdata["psu"][psu_id]["hotplug"] = psu_hotplug.strip()

        elif re.match(re_psu_reading, line):
            verboseMsg("found power supply reading: " + line)
            junk, psu_reading = line.split(":", 1)
            hdata["psu"][psu_id]["reading"] = psu_reading.replace("Watts", "").strip()

    return hdata


def getIPMIdata():
    global error, errorString
    error = 2
    errorString = "No power sensor found"

    exe = shutil.which("ipmitool")
    # if not os.access(candidate, os.W_OK):
    cmd = [exe, "dcmi", "power", "reading"]
    warningMsg("ipmitool only runs as root")

    try:
        output = subprocess.run(
            cmd, capture_output=True, check=True, text=True, timeout=2
        )

    except subprocess.CalledProcessError as e:
        errorMsg(str(e) + ": " + str(e.stdout).strip("\n"))
        sys.exit(1)

    psu_reading = "^\s+Instantaneous power reading:\s+"

    rawdata = str(output.stdout).replace("\t", " ").replace("\n ", "\n").split("\n")

    hdata = {}
    hdata["psu"] = {}  # Init PSU data structure
    hdata["psu"][0] = {}  # Only one value is returned.

    for line in rawdata:
        if re.match(psu_reading, line):
            verboseMsg("found power meter reading: " + line)
            junk, meter_reading = line.split(":", 1)
            hdata["psu"][0]["reading"] = psu_reading.replace("Watts", "").strip()

    return hdata


# Argument Parsing
try:
    opts, args = getopt.gnu_getopt(
        sys.argv[1:],
        "m:hlNpvw",
        [
            "method",
            "help",
            "list-methods",
            "no-librenms",
            "pretty",
            "verbose",
            "warnings",
        ],
    )
    if len(args) != 0:
        usageError("Unknown argument")

except getopt.GetoptError as e:
    usageError(str(e))

for opt, val in opts:
    if opt in ["-h", "--help"]:
        print(usage)
        sys.exit(0)

    elif opt in ["-l", "--list-methods"]:
        listMethods()
        sys.exit(0)

    elif opt in ["-m", "--method"]:
        if val not in methods:
            usageError("Invalid method: '" + val + "'")
        else:
            method = val

    elif opt in ["-N", "--no-librenms"]:
        librenms = False

    elif opt in ["-p", "--pretty"]:
        pretty = True

    elif opt in ["-v", "--verbose"]:
        verbose = True

    elif opt in ["-w", "--warnings"]:
        warnings = True

    else:
        continue

# Electricity Cost
try:
    costPerkWh

except NameError:
    errorMsg("cost per kWh is undefined (uncomment in script)")
    sys.exit(1)

# Get data
data = getData(method)
data["supply"] = {}
data["supply"]["rate"] = costPerkWh  # pylint: disable=E0602

# Top-level reading
#   CUSTOMISE THIS FOR YOUR HOST
#   i.e. by running with -p -n -m and see what you get and then updating where
#   in the JSON data the top-level reading is sourced from
try:
    # Example 1 - take reading from ACPI meter id 1
    data["reading"] = data["meter"]["1"]["reading"]

    # Example 2 - sum the two power supplies and apply a power factor
    # pf = 0.95
    # data["reading"] = str( float(data["psu"]["1"]["reading"]) \
    #    + float(data["psu"]["2"]["reading"]) / pf )

except:
    data["reading"] = 0.0

# Build result
if librenms:
    result["version"] = version
    result["error"] = error
    result["errorString"] = errorString
    result["data"] = data

else:
    result = data

# Print result
if pretty:
    print(json.dumps(result, indent=2))

else:
    print(json.dumps(result))
