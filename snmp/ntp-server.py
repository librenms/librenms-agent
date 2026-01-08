#!/usr/bin/env python3

import json
import subprocess


def run_command(command_list):

    result = subprocess.run(
        command_list, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL
    )

    return result.stdout.decode("utf-8")


def time_since_reset_to_seconds(part):
    # time since reset:        3D 08:06:47
    _part = part.split(":")
    k = _part[0]

    # calc seconds
    try:
        v_h = _part[1]
    except IndexError:
        v_h = "0"
    try:
        v_m = _part[2]
    except IndexError:
        v_m = "0"
    try:
        v_s = _part[3]
    except IndexError:
        v_s = "0"

    v = 0

    if "D" in v_h:
        v_h_part = v_h.split()
        v += int(v_h_part[0].replace("D", "")) * 86400
        v += int(v_h_part[1]) * 3600
    else:
        v += int(v_h) * 3600

    v += int(v_m) * 60

    v += int(v_s)

    v = str(v)

    return k, v


# -------- first command ---------------------------

output = run_command(["ntpq", "-c rv"])

parts = output.replace("\n", "").split(",")

data_dict = {}

for part in parts:
    if part.count("=") != 1:
        continue

    k, v = part.split("=")

    data_dict[k.strip()] = v.replace('"', "")

# -------- second command ---------------------------

output2 = run_command(["ntpq", "-c iostats 127.0.0.1"])

parts = output2.split("\n")

for part in parts:
    if part.count(":") < 1:
        continue

    if "time since reset" in part:
        k, v = time_since_reset_to_seconds(part)

    elif part.count(":") > 1:
        continue

    else:
        k, v = part.split(":")

    k = k.strip().replace(" ", "_")

    data_dict[k] = v.strip().split()[0]

# ----------------------------------------------------

result_dict = {"error": 0, "errorString": "", "version": 1, "data": data_dict}

print(json.dumps(result_dict, indent=4, sort_keys=True))
