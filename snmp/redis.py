#!/usr/bin/env python3

import json
import subprocess

shell_cmd = "redis-cli info"
all_data = (
    subprocess.Popen(shell_cmd, shell=True, stdout=subprocess.PIPE)
    .stdout.read()
    .split(b"\n")
)

version = 1
error = 0
error_string = ""
redis_data = {}

# stdout list to json
try:
    category = ""
    for d in all_data:
        d = d.replace(b"\r", b"")

        if d in [b""]:
            continue

        if d.startswith(b"#"):
            category = d.replace(b"# ", b"").decode("utf-8")
            redis_data[category] = {}
            continue

        if not len(category):
            error = 2
            error_string = "category not defined"
            break

        k, v = d.split(b":")
        k = k.decode("utf-8")
        v = v.decode("utf-8")

        redis_data[category][k] = v

except:
    error = 1
    error_string = "data extracting error"

output = {
    "version": version,
    "error": error,
    "errorString": error_string,
    "data": redis_data,
}

print(json.dumps(output))
