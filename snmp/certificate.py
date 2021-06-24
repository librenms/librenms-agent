#!/usr/bin/env python3

import datetime
import json
import socket
import ssl

CONFIGFILE = "/etc/snmp/certificate.json"
# {"domains": [
#     {"fqdn": "www.mydomain.com"},
#     {"fqdn": "www2.mydomain.com"}
# ]
# }


def get_certificate_data(domain, port=443):

    context = ssl.create_default_context()
    conn = context.wrap_socket(
        socket.socket(socket.AF_INET),
        server_hostname=domain,
    )
    # 3 second timeout because Lambda has runtime limitations
    conn.settimeout(3.0)

    error_msg = None
    ssl_info = {}
    try:
        conn.connect((domain, port))
        ssl_info = conn.getpeercert()
    except ConnectionRefusedError as e:
        error_msg = e
    # Manage expired certificates
    except ssl.SSLCertVerificationError as e:
        # Arbitrary start date
        ssl_info["notBefore"] = "Jan 1 00:00:00 2020 GMT"
        # End date is now (we don't have the real one but the certificate is expired)
        one_minute_further = datetime.datetime.now() + datetime.timedelta(minutes=1)
        ssl_info["notAfter"] = one_minute_further.strftime("%b %d %H:%M:%S %Y GMT")

    return ssl_info, error_msg


output = {}
output["error"] = 0
output["errorString"] = ""
output["version"] = 1

with open(CONFIGFILE, "r") as json_file:
    try:
        configfile = json.load(json_file)
    except json.decoder.JSONDecodeError as e:
        output["error"] = 1
        output["errorString"] = "Configfile Error: '%s'" % e

if not output["error"]:
    output_data_list = []
    for domain in configfile["domains"]:
        output_data = {}

        if "port" not in domain.keys():
            domain["port"] = 443
        certificate_data, error_msg = get_certificate_data(
            domain["fqdn"], domain["port"]
        )

        output_data["cert_name"] = domain["fqdn"]

        if not error_msg:
            ssl_date_format = r"%b %d %H:%M:%S %Y %Z"
            validity_end = datetime.datetime.strptime(
                certificate_data["notAfter"], ssl_date_format
            )
            validity_start = datetime.datetime.strptime(
                certificate_data["notBefore"], ssl_date_format
            )
            cert_age = datetime.datetime.now() - validity_start
            cert_still_valid = validity_end - datetime.datetime.now()

            output_data["age"] = cert_age.days
            output_data["remaining_days"] = cert_still_valid.days

        else:
            output_data["age"] = None
            output_data["remaining_days"] = None
            output["error"] = 1
            output["errorString"] = "%s: %s" % (domain["fqdn"], error_msg)

        output_data_list.append(output_data)

    output["data"] = output_data_list

print(json.dumps(output))
