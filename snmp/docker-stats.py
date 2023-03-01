#!/usr/bin/env python3
import datetime
import json
import subprocess

from dateutil import parser

VERSION = 2
ONLY_RUNNING_CONTAINERS = True


def run(cmd):
    res = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
    return res


def inspectContainer(container):
    raw = run(["docker", "inspect", "-s", container])
    data = json.loads(raw)

    return data


def getStats():
    command = [
        "docker",
        "stats",
        "--no-stream",
        "--no-trunc",
        "--format",
        "{{ json . }}",
    ]
    if not ONLY_RUNNING_CONTAINERS:
        command.append("-a")
    raw = run(command)
    lines = raw.split(b"\n")
    containers = []
    for line in lines[0:-1]:
        containers.append(json.loads(line))

    return containers


def dump():
    containers = []
    try:
        stats_containers = getStats()
    except subprocess.CalledProcessError as e:
        print(
            json.dumps(
                {
                    "version": VERSION,
                    "data": containers,
                    "error": e.returncode,
                    "errorString": e.output.decode("utf-8"),
                }
            )
        )
        return

    for container in stats_containers:
        try:
            inspected_container = inspectContainer(container["Name"])
        except subprocess.CalledProcessError:
            continue

        started_at = parser.parse(inspected_container[0]["State"]["StartedAt"])

        if inspected_container[0]["State"]["Running"]:
            finished_at = datetime.datetime.now(started_at.tzinfo)
        else:
            finished_at = parser.parse(inspected_container[0]["State"]["FinishedAt"])

        uptime = finished_at - started_at

        containers.append(
            {
                "container": container["Name"],
                "pids": container["PIDs"],
                "memory": {
                    "used": container["MemUsage"].split(" / ")[0],
                    "limit": container["MemUsage"].split(" / ")[1],
                    "perc": container["MemPerc"],
                },
                "cpu": container["CPUPerc"],
                "size": {
                    "size_rw": inspected_container[0]["SizeRw"],
                    "size_root_fs": inspected_container[0]["SizeRootFs"],
                },
                "state": {
                    "status": inspected_container[0]["State"]["Status"],
                    "started_at": inspected_container[0]["State"]["StartedAt"],
                    "finished_at": inspected_container[0]["State"]["FinishedAt"],
                    "uptime": round(uptime.total_seconds()),
                },
            }
        )

    print(
        json.dumps(
            {
                "version": VERSION,
                "data": containers,
                "error": "0",
                "errorString": "",
            }
        )
    )


if __name__ == "__main__":
    dump()
