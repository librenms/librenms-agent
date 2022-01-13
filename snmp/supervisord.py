#!/usr/bin/env python

import json
import sys

from supervisor import xmlrpc

if sys.version_info.major < 3:
    from xmlrpclib import ServerProxy
else:
    from xmlrpc.client import ServerProxy

unix_socket_path = "/var/run/supervisor/supervisor.sock"

error = 0
error_string = 0
processes = []

total = {
    "STOPPED": 0,
    "STARTING": 0,
    "RUNNING": 0,
    "BACKOFF": 0,
    "STOPPING": 0,
    "EXITED": 0,
    "FATAL": 0,
    "UNKNOWN": 0,
}

try:
    server = ServerProxy(
        "http://127.0.0.1",
        transport=xmlrpc.SupervisorTransport(None, None, "unix://" + unix_socket_path),
    )

    state = server.supervisor.getState()["statename"]

    if state != "RUNNING":
        error = 1
        error_string = "Not running"

    for process in server.supervisor.getAllProcessInfo():
        if process["statename"] == "RUNNING":
            uptime = process["now"] - process["start"]
        else:
            uptime = process["stop"] - process["start"]

        uptime = 0 if uptime < 0 else uptime

        processes.append(
            {
                "name": process["name"],
                "group": process["group"],
                "statename": process["statename"],
                "state": process["state"],
                "error": process["spawnerr"] if process["spawnerr"] else None,
                "start": process["start"],
                "stop": process["stop"],
                "now": process["now"],
                "uptime": uptime,
            }
        )

        total[process["statename"]] += 1

except Exception as e:
    error = 1
    error_string = repr(e)

print(
    json.dumps(
        {
            "version": 1,
            "error": error,
            "errorString": error_string,
            "data": {
                "total": total,
                "processes": processes,
            },
        }
    )
)
