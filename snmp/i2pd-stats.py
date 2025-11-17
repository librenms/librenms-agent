#!/usr/bin/env python3

# i2pd-stats.py
#   SNMP Extend-agent for exporting I2Pd statistics to LibreNMS
#
#   Heavily modified from i2pdctl:
#       https://github.com/PurpleI2P/i2pd-tools
#
#   Run script and it will print JSON blob into stdout
#   Set I2P Control socket params using env variables:
#       export I2PCONTROL_URL='https://127.0.0.1:7650/'
#       export I2PCONTROL_PASSWORD='secret'
#   or fallback to defaults...
#
#   Kossusukka <kossusukka@kossulab.net>

import os
import json
import ssl
import urllib.request
import urllib.parse
import urllib.error

# do not muuta
APIVER = "1"

class I2PControl(object):
    """Talk to I2PControl API"""

    def __init__(self, url, password='itoopie'):
        self.url = url
        self.password = password
        self._token = None

    @property
    def token(self):
        """Cached authentication token"""
        if not self._token:
            try:
                self._token = self.do_post(self.url,
                    json.dumps({'id': 1, 'method': 'Authenticate',
                        'params': {'API': 1, 'Password': self.password},
                        'jsonrpc': '2.0'}))["result"]["Token"]
            except KeyError:
                print("Error: I2P Control password invalid!")
                exit(1)
        return self._token

    def do_post(self, url, data):
        """HTTP(S) handler"""
        req = urllib.request.Request(url, data=data.encode())
        try:
            with urllib.request.urlopen(req, context=ssl._create_unverified_context(), timeout=10) as f:
                resp = f.read().decode('utf-8')
        except urllib.error.URLError:
            print("Error: I2P Control socket invalid!")
            exit(1)
        except TimeoutError:
            print("Error: I2P Control socket timeout!")
            exit(1)
        return json.loads(resp)

    def request(self, method, params):
        """Execute authenticated request"""
        params['Token'] = self.token
        return self.do_post(self.url, json.dumps(
            {'id': 1, 'method': method, 'params': params, 'jsonrpc': '2.0'}))

def main():
    URL = os.getenv("I2PCONTROL_URL", "https://127.0.0.1:7650/")
    PASSWORD = os.getenv("I2PCONTROL_PASSWORD", "itoopie")
    JSON_REQUEST = json.loads('{ "i2p.router.uptime": "", "i2p.router.net.status": "", "i2p.router.net.bw.inbound.1s": "", "i2p.router.net.bw.inbound.15s": "", "i2p.router.net.bw.outbound.1s": "", "i2p.router.net.bw.outbound.15s": "", "i2p.router.net.tunnels.participating": "", "i2p.router.net.tunnels.successrate": "", "i2p.router.netdb.knownpeers": "", "i2p.router.netdb.activepeers": "", "i2p.router.net.total.received.bytes": "", "i2p.router.net.total.sent.bytes": "" }')

    ctl = I2PControl(URL, PASSWORD)

    response = ctl.request('RouterInfo', JSON_REQUEST)['result']
    newdata = { "data": response, "version": APIVER, "error": "0", "errorString": "" }

    print(json.dumps(newdata))

if __name__ == "__main__":
    main()
