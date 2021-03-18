#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# https://download.seafile.com/published/web-api/v2.1-admin

# user -> libraries (count)
# user -> trash-libraries (count)
# user -> space consumption (count)
# user -> is activated (bool)

# connected_devices (count)
# groups (count)

# Clients -> plattform (count)
# Clients -> version (count)

import json

import requests

# Configfile content example:
# {"url": "https://seafile.mydomain.org",
#  "username": "some_admin_login@mail.address",
#  "password": "password",
#  "account_identifier": "name",
#  "hide_monitoring_account": true
# }

CONFIGFILE = "/etc/snmp/seafile.json"
error = 0
error_string = ""
version = 1


def get_data(url_path, data=None, token=None):
    complete_url = "%s/%s" % (url, url_path)
    headers = {"Accept": "application/json"}
    if token:
        headers["Authorization"] = "Token %s" % token

    try:
        if token:
            r = requests.get(complete_url, data=data, headers=headers)
        else:
            r = requests.post(complete_url, data=data, headers=headers)
        try:
            return r.json()
        except json.decoder.JSONDecodeError:
            return "no valid json returned - url correct?"
    except requests.exceptions.RequestException as err:
        return str(err)


def get_devices():
    # get all devices
    url_path = "api/v2.1/admin/devices/"
    return get_data(url_path, token=token)


def get_groups():
    # get all groups
    url_path = "api/v2.1/admin/groups/"
    return get_data(url_path, token=token)


def get_sysinfo():
    # get all groups
    url_path = "api/v2.1/admin/sysinfo/"
    return get_data(url_path, token=token)


def get_account_information():
    # get all accounts withs details
    account_list = []
    for account in get_data("api2/accounts/", token=token):

        # get account details
        url_path = "api2/accounts/%s/" % account["email"]
        account_data = get_data(url_path, token=token)

        # get libraries by owner
        url_path = "api/v2.1/admin/libraries/?owner=%s" % account["email"]
        account_data["repos"] = get_data(url_path, token=token)["repos"]

        # get deleted libraries by owner
        url_path = "api/v2.1/admin/trash-libraries/?owner=%s" % account["email"]
        account_data["trash_repos"] = get_data(url_path, token=token)["repos"]

        account_list.append(account_data)
    return account_list


def resort_devices(device_list):
    data = {}
    platform = {}
    client_version = {}
    for device in device_list:
        # don't list information assigned to monitor account
        if hide_monitoring_account:
            if device["user"] == configfile["username"]:
                continue

        if device["platform"] not in platform.keys():
            platform[device["platform"]] = 1
        else:
            platform[device["platform"]] += 1

        if device["client_version"] not in client_version.keys():
            client_version[device["client_version"]] = 1
        else:
            client_version[device["client_version"]] += 1

    data["platform"] = []
    for k, v in platform.items():
        data["platform"].append({"os_name": k, "clients": v})
    data["client_version"] = []
    for k, v in client_version.items():
        data["client_version"].append({"client_version": k, "clients": v})

    return data


def resort_groups(group_list):
    data = {"count": len(group_list)}
    return data


def resort_accounts(account_list):
    if account_identifier in ["name", "email"]:
        identifier = account_identifier
    else:
        identifier = "name"

    accepted_key_list = ["is_active", "usage"]

    data = []
    for user_account in account_list:
        # don't list information assigned to monitor account
        if hide_monitoring_account:
            if user_account["email"] == configfile["username"]:
                continue

        new_account = {}
        new_account["owner"] = user_account[identifier]
        new_account["repos"] = len(user_account["repos"])
        new_account["trash_repos"] = len(user_account["trash_repos"])

        for k in user_account.keys():
            if k not in accepted_key_list:
                continue
            new_account[k] = user_account[k]
        data.append(new_account)

    return sorted(data, key=lambda k: k["owner"].lower())


# ------------------------ MAIN --------------------------------------------------------
with open(CONFIGFILE, "r") as json_file:
    try:
        configfile = json.load(json_file)
    except json.decoder.JSONDecodeError as e:
        error = 1
        error_string = "Configfile Error: '%s'" % e

if not error:
    url = configfile["url"]
    username = configfile["username"]
    password = configfile["password"]
    try:
        account_identifier = configfile["account_identifier"]
    except KeyError:
        account_identifier = None
    try:
        hide_monitoring_account = configfile["hide_monitoring_account"]
    except KeyError:
        hide_monitoring_account = False

    # get token
    login_data = {"username": username, "password": password}
    ret = get_data("api2/auth-token/", data=login_data)
    if type(ret) != str:
        if "token" in ret.keys():
            token = ret["token"]
        else:
            error = 1
            try:
                error_string = json.dumps(ret)
            except:
                error_string = ret
    else:
        error = 1
        error_string = ret

data = {}
if not error:
    ret = get_account_information()
if not error:
    data["accounts"] = resort_accounts(ret)
    data["devices"] = resort_devices(get_devices()["devices"])
    data["groups"] = resort_groups(get_groups()["groups"])
    data["sysinfo"] = get_sysinfo()

output = {"error": error, "errorString": error_string, "version": version, "data": data}

print(json.dumps(output))
