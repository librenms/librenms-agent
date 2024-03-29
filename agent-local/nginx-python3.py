#!/usr/bin/env python3
import re
from urllib.request import urlopen

data = urlopen("http://127.0.0.1/nginx-status").read()

params = {}

for line in data.decode().split("\n"):
    smallstat = re.match(r"\s?Reading:\s(.*)\sWriting:\s(.*)\sWaiting:\s(.*)$", line)
    req = re.match(r"\s+(\d+)\s+(\d+)\s+(\d+)", line)
    if smallstat:
        params["Reading"] = smallstat.group(1)
        params["Writing"] = smallstat.group(2)
        params["Waiting"] = smallstat.group(3)
    elif req:
        params["Requests"] = req.group(3)
    else:
        pass

dataorder = ["Active", "Reading", "Writing", "Waiting", "Requests"]

print("<<<nginx>>>")

for param in dataorder:
    if param == "Active":
        Active = (
            int(params["Reading"]) + int(params["Writing"]) + int(params["Waiting"])
        )
        print(Active)
    else:
        print(params[param])
