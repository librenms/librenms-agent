#!/usr/bin/env python3

# i2pd-stats.py
#   SNMP Extend-agent for exporting I2Pd statistics to LibreNMS
#
#   Inspired from i2pdctl:
#       https://github.com/PurpleI2P/i2pd-tools
#
#   Run script and it will print JSON-blob into stdout
#   Set I2P Control socket params below!
#
#   Installation:
#       1. copy this file to /etc/snmp/i2pd-stats.py
#       2. chmod +x /etc/snmp/i2pd-stats.py
#       3. edit /etc/snmp/snmpd.conf and add following line:
#           extend i2pd /etc/snmp/i2pd-stats.py
#       4. systemctl restart snmpd.service
#
#   author: Kossusukka <kossusukka@kossulab.net>

import json
import os
import ssl
import urllib.error
import urllib.parse
import urllib.request

######### CONFIGURATION ##############
I2PC_URL = "https://127.0.0.1:7650/"
I2PC_PASS = "itoopie"
##### END OF CONFIGURATION ###########


# Do not change! Must match LibreNMS version
JSONVER = "1"


class I2PControl(object):
    """Talk to I2PControl API"""

    def __init__(self, url, password):
        self.url = url
        self.password = password
        self._token = None

    @property
    def token(self):
        """Cached authentication token"""
        if not self._token:
            try:
                self._token = self.do_post(
                    self.url,
                    json.dumps(
                        {
                            "id": 1,
                            "method": "Authenticate",
                            "params": {"API": 1, "Password": self.password},
                            "jsonrpc": "2.0",
                        }
                    ),
                )["result"]["Token"]
            except KeyError:
                post_error("1", "Invalid I2PControl password or token!")
                exit(1)
        return self._token

    def do_post(self, url, data):
        """HTTP(S) handler"""
        req = urllib.request.Request(url, data=data.encode())
        try:
            with urllib.request.urlopen(
                req, context=ssl._create_unverified_context(), timeout=5
            ) as f:
                resp = f.read().decode("utf-8")
        except urllib.error.URLError:
            post_error("2", "Unable to connect I2PControl socket!")
            exit(1)
        except TimeoutError:
            post_error("3", "Connection timed out to I2PControl socket!")
            exit(1)
        return json.loads(resp)

    def request(self, method, params):
        """Execute authenticated request"""
        params["Token"] = self.token
        return self.do_post(
            self.url,
            json.dumps({"id": 1, "method": method, "params": params, "jsonrpc": "2.0"}),
        )


def post_error(code: str, message: str):
    """Post error code+message as JSON for LibreNMS"""
    resp_err = {"data": "", "version": JSONVER, "error": code, "errorString": message}

    print(json.dumps(resp_err))


def main():
    # Craft JSON request for I2PC
    JSON_REQUEST = json.loads(
        '{ "i2p.router.uptime": "", "i2p.router.net.status": "", "i2p.router.net.bw.inbound.1s": "", "i2p.router.net.bw.inbound.15s": "", "i2p.router.net.bw.outbound.1s": "", "i2p.router.net.bw.outbound.15s": "", "i2p.router.net.tunnels.participating": "", "i2p.router.net.tunnels.successrate": "", "i2p.router.netdb.knownpeers": "", "i2p.router.netdb.activepeers": "", "i2p.router.net.total.received.bytes": "", "i2p.router.net.total.sent.bytes": "" }'
    )

    ctl = I2PControl(I2PC_URL, I2PC_PASS)

    resp = ctl.request("RouterInfo", JSON_REQUEST)["result"]
    resp_full = {"data": resp, "version": JSONVER, "error": "0", "errorString": ""}

    print(json.dumps(resp_full))


if __name__ == "__main__":
    main()
