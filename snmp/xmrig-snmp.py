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
# The script accesses an instance of xmrig's API and returns the json data it
# finds. It implements caching to (optionally) prevent too many requests to the
# API in the specified interval. The script should be called by the snmpd daemon
# on the xmrig host machine. This is achieved via the 'extend' functionality in 
# snmpd. For example, in /etc/snmp/snmpd.conf:
#       extend      xmrig   /usr/local/bin/xmrig-snmp.py
#
# The results can be accessed via the nsExtend MIBs from another host, e.g. 
#   snmpwalk -v 2c -c <community_string> <xmrig_host> \
#       <nsExtendConfigTable|nsExtendOutputFull|nsExtendOutput1Table>
#
# The results are returned in a JSON format suitable for graphing in LibreNMS.
# A LibreNMS 'application' is available for this purpose.
#
# COMPATIBILITY
# 
# - Linux, not tested on other OS
# - Single instance of xmrig per host
# - Tested on python 3.6 and xmrig 6.7.2
#
# INSTALLATION
#
# - pip install validators (required python module)
# - Copy this script somewhere, e.g. /usr/local/bin
# - Add the 'extend' config to snmpd.conf
# - Update the worker url in this script, or pass it as an argument in the 
#   extend config
# - mkdir /var/cache/xmrig
# - touch /var/cache/xmrig/summary.json
# - https://docs.librenms.org/Extensions/Applications/#xmrig
#
# CHANGELOG
#
# 2021019 - v1.1 - initial
# 2021022 - v1.2 - returns full api data 
# 2021023 - v1.3 - improved error handling
# 2021205 - v1.4 - improved UI

version = 1.4

### Libraries

import os
import sys
import time
import getopt
import urllib.request 
import json
import validators
import re

### Globals

error = 0
errorString = ""
data = {}
result = {}
usage = "USAGE: " + os.path.basename(__file__) \
    + " -u|--url <url-to-xmrig-api>" \
    + " [-c|--cache-time <seconds>] [-C|--cache-file <path>]" \
    + " [-n|--no-caching] [-N|--no-librenms] [-p|--pretty]" \
    + " [-v|--verbose] [-w|--warnings] | -h|--help"

### Option defaults

url = ""                # usually "<host>:<port>/1/summary"
caching = True
cachetime = 10
cachefile = None
cachefiles = [ "/var/cache/xmrig/summary.json" ]
librenms = True
pretty = False
verbose = False
warnings = False

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

### Data functions

def getAPIData(url):
    verboseMsg("Getting data from worker")
    rawdata = urllib.request.urlopen(url).read().decode('UTF-8')
    data = json.loads(rawdata)
    return data

def getCachedData(cache):
    verboseMsg("Getting data from cache")
    f = open(cache, 'r')
    rawdata = f.read()
    f.close()
    data = json.loads(rawdata)
    return data

def writeCache(rawdata):
    f = open(cachefile, 'w')
    f.write(rawdata)
    f.close()

### Argument Parsing

try:
    opts, args = getopt.gnu_getopt(
        sys.argv[1:], 'cCu:hnNpvw', ['cache-time', 'cache-file', 'url', 'help', 'no-caching', 'no-librenms', 'pretty', 'verbose', 'warnings']
    )
    if len(args) != 0:
        usageError("Unknown argument")

except getopt.GetoptError as e:
    usageError(str(e))

for opt, val in opts:
    if opt in ["-h", "--help"]:
        print(usage)
        sys.exit(0)

    elif opt in ["-c", "--cache-time"]:
        if val.isdigit():
            cachetime = val
        else: 
            usageError("option cachetime expects an integer")

    elif opt in ["-C", "--cache-file"]:
        cachefiles.insert(0, val)

    elif opt in ["-n", "--no-caching"]:
        caching = False

    elif opt in ["-N", "--no-librenms"]:
        librenms = False

    elif opt in ["-p", "--pretty"]:
        pretty = True

    elif opt in ["-u", "--url"]:
        if not validators.url(val):
            usageError("Invalid URL: '" + val + "'")
        else:
            url = val

    elif opt in ["-v", "--verbose"]:
        verbose = True

    elif opt in ["-w", "--warnings"]:
        warnings = True

    else:
        continue
 
# Cache file
if caching:
    for candidate in cachefiles:
        candidate = os.path.realpath(candidate)
        candidir = os.path.dirname(candidate)
        verboseMsg("Validating cache candidate: " + candidate)

        if not os.path.isdir(candidir):
            verboseMsg("Candidate cache directory does not exist: " + candidir)
            try:
                os.path.mkdir(candidir)
                verboseMsg("Created directory: " + candidir)
            except:
                verboseMsg("Unable to create directory: " + candidir)
                continue

        if not os.access(candidate, os.W_OK):
            verboseMsg ("Candidate cache file is not writable: " + candidate)
            continue

        else:
            #verboseMsg ("Using cache file: " + candidate)
            cachefile = candidate
            break

    if cachefile is None:
        errorMsg("No writable cache found, caching will be disabled.")
        caching = False
        
# Get Data
if caching and (os.path.isfile(cachefile) and (time.time() - os.stat(cachefile)[8]) < cachetime):
    try:
        data = getCachedData(cachefile)
    except:
        try:
            data = getAPIData(url)
        except:
            e = sys.exc_info()
            error = 7
            errorString = "Unable to get data: General exception: " + str(e)
else:
    # Turn this into function? called above too
    try:
        data = getAPIData(url)

    except ConnectionRefusedError as e:
        error = 1
        errorString = "Connection refused"

    except urllib.error.URLError as e:
        es = str(e)
        if re.search("Connection refused", es):
            error = 2
            errorString = "Server refused connection"

        elif re.search("HTTP Error 404", es):
            error = 3
            errorString = "HTTP Error: 404 not found"

        else:
            error = 4
            errorString = es

    except json.JSONDecodeError as e:
        error = 5
        errorString = "Invalid JSON retrieved"

    except:
        e = sys.exc_info()
        error = 6
        errorString = "Unable to get data: General exception: " + str(e)
    
# Write cache
if caching and error == 0:
    try:
        writeCache(json.dumps(data, indent=2))
    except:
        warningMsg("Failed to write cache")

# Build result
if librenms:
    result['version']=version
    result['error']=error
    result['errorString']=errorString
    result['data']=data

else:
    result = data

# Print result
if pretty:
    print(json.dumps(result, indent=2))

else:
    print(json.dumps(result))

