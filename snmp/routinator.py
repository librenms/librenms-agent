#!/usr/bin/env python3
"""
LibreNMS SNMP extend script for NLnet Labs Routinator (RPKI validator).

Fetches Routinator's JSON status API (`/api/v1/status`), aggregates it into a
compact, stable shape and prints a single LibreNMS application JSON envelope to
stdout. Designed to be wired into snmpd via:

    extend routinator /etc/snmp/routinator.py

The output is gzip+base64-compressed. LibreNMS detects and decodes this
automatically; it shrinks the payload over SNMP and sidesteps snmpd's mangling
of some characters.

The script is stateless: it reports current values only. Rates (bytes/sec etc.)
are derived by LibreNMS from successive counter samples.

Optional config file (JSON) at /etc/snmp/routinator.json overrides the defaults:

    {
        "url": "http://127.0.0.1:8323/api/v1/status",
        "timeout": 5,
        "include_failed_uris": true,
        "max_failed_uris": 25
    }

`url` may instead be given as separate "host"/"port" keys. If the file is
absent the built-in defaults are used; confirm the real http-listen port with
the Routinator operator (the default 8323 is commonly changed).
"""

import base64
import gzip
import json
import re
import sys
import urllib.request
from datetime import datetime, timezone

CONFIGFILE = "/etc/snmp/routinator.json"

DEFAULTS = {
    "host": "127.0.0.1",
    "port": 8323,
    "path": "/api/v1/status",
    "url": None,  # full override; built from host/port/path when None
    "timeout": 5,
    "include_failed_uris": True,
    "max_failed_uris": 25,
}

# The five production trust anchors. We iterate over whatever the API returns,
# but this guarantees a stable, complete set of keys even if a TAL is absent
# from a given run (e.g. a fresh start or a test environment).
TAL_NAMES = ["afrinic", "apnic", "arin", "lacnic", "ripe"]


def load_config():
    """Return the effective config, merging the optional config file over the
    defaults. A missing file is fine; a malformed file raises."""
    cfg = dict(DEFAULTS)
    try:
        with open(CONFIGFILE, "r") as fh:
            cfg.update(json.load(fh))
    except FileNotFoundError:
        pass
    if not cfg.get("url"):
        cfg["url"] = "http://%s:%s%s" % (cfg["host"], cfg["port"], cfg["path"])
    return cfg


def parse_ts(value):
    """Parse a Routinator RFC3339 timestamp into an aware datetime.

    Routinator emits nanosecond precision (e.g. ...:24.483161221+00:00) which
    datetime cannot handle, so trim the fractional part to microseconds. Returns
    None if the value is missing or unparseable."""
    if not value:
        return None
    value = value.strip()
    # Normalise a trailing Z to an explicit UTC offset.
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    # Trim fractional seconds to at most 6 digits.
    value = re.sub(r"(\.\d{6})\d+", r"\1", value)
    try:
        return datetime.fromisoformat(value)
    except ValueError:
        return None


def seconds_since(now, then):
    """Whole seconds between two datetimes, or None if either is missing."""
    if now is None or then is None:
        return None
    return round((now - then).total_seconds())


def num(value, default=0):
    """Coerce a value to a number, falling back to default on None/garbage."""
    if isinstance(value, bool):
        return default
    if isinstance(value, (int, float)):
        return value
    return default


def build_global(status, now):
    payload = status.get("payload", {}) or {}

    def final(kind):
        return num((payload.get(kind) or {}).get("final"))

    # VRPs delivered to routers = final route-origin payloads (v4 + v6). This
    # sums to the per-TAL vrps_final totals below.
    vrps_final = final("routeOriginsIPv4") + final("routeOriginsIPv6")

    # Routinator has no single "stale objects" figure in the JSON API, so roll
    # up stale manifests + CRLs across all trust anchors.
    stale = 0
    for tal in (status.get("tals") or {}).values():
        stale += num(tal.get("staleManifests")) + num(tal.get("staleCRLs"))

    return {
        "last_update_done": seconds_since(now, parse_ts(status.get("lastUpdateDone"))),
        "last_update_duration": num(status.get("lastUpdateDuration")),
        "serial": num(status.get("serial")),
        "stale_objects": stale,
        "vrps_final": vrps_final,
    }


def build_repos(status, cfg):
    rrdp = status.get("rrdp") or {}
    rsync = status.get("rsync") or {}

    rrdp_ok = rrdp_failed = rrdp_unreachable = 0
    rrdp_duration_max = 0.0
    rrdp_failed_uris = []
    for uri, entry in rrdp.items():
        code = num((entry or {}).get("status"), default=None)
        # 200 = fetched, 304 = not modified (healthy). -1 = server unreachable
        # (a distinct failure class). Anything else is a genuine HTTP failure.
        if code in (200, 304):
            rrdp_ok += 1
        elif code == -1:
            rrdp_unreachable += 1
            rrdp_failed_uris.append(uri)
        else:
            rrdp_failed += 1
            rrdp_failed_uris.append(uri)
        rrdp_duration_max = max(rrdp_duration_max, num((entry or {}).get("duration")))

    rsync_failed = 0
    rsync_duration_max = 0.0
    rsync_failed_uris = []
    for uri, entry in rsync.items():
        # rsync exit code: 0 = success, non-zero = failure.
        if num((entry or {}).get("status")) != 0:
            rsync_failed += 1
            rsync_failed_uris.append(uri)
        rsync_duration_max = max(rsync_duration_max, num((entry or {}).get("duration")))

    repos = {
        "rrdp_total": len(rrdp),
        "rrdp_ok": rrdp_ok,
        "rrdp_failed": rrdp_failed,
        "rrdp_unreachable": rrdp_unreachable,
        "rrdp_duration_max": round(rrdp_duration_max, 3),
        "rsync_total": len(rsync),
        "rsync_failed": rsync_failed,
        "rsync_duration_max": round(rsync_duration_max, 3),
    }

    if cfg["include_failed_uris"]:
        cap = cfg["max_failed_uris"]
        repos["rrdp_failed_uris"] = sorted(rrdp_failed_uris)[:cap]
        repos["rsync_failed_uris"] = sorted(rsync_failed_uris)[:cap]

    return repos


def build_tal(status):
    tals = status.get("tals") or {}
    # Union of the known five and whatever the API actually returned.
    names = list(TAL_NAMES)
    for name in tals:
        if name not in names:
            names.append(name)

    out = {}
    for name in names:
        tal = tals.get(name) or {}
        invalid = (
            num(tal.get("invalidManifests"))
            + num(tal.get("invalidCRLs"))
            + num(tal.get("invalidCerts"))
            + num(tal.get("invalidROAs"))
            + num(tal.get("invalidASPAs"))
            + num(tal.get("invalidGBRs"))
        )
        out[name] = {
            "total_vrps": num(tal.get("vrpsFinal")),
            "valid_roas": num(tal.get("validROAs")),
            "pub_points_valid": num(tal.get("validPublicationPoints")),
            "pub_points_rejected": num(tal.get("rejectedPublicationPoints")),
            "objects_invalid": invalid,
            "roa_invalid": num(tal.get("invalidROAs")),
            "manifests_missing": num(tal.get("missingManifests")),
            "manifests_stale": num(tal.get("staleManifests")),
        }
    return out


def build_rtr(status, serial, now):
    rtr = status.get("rtr") or {}
    out_rtr = {
        "current_connections": num(rtr.get("currentConnections")),
        "bytes_written": num(rtr.get("bytesWritten")),
        "bytes_read": num(rtr.get("bytesRead")),
    }

    # Per-client metrics are only present when Routinator runs with
    # --rtr-client-metrics. Absent -> empty map, never an error.
    clients = {}
    for addr, client in (rtr.get("clients") or {}).items():
        client = client or {}
        client_serial = num(client.get("serial"))
        clients[addr] = {
            "connections": num(client.get("connections")),
            "serial": client_serial,
            "serial_lag": serial - client_serial,
            "last_update_seconds": seconds_since(now, parse_ts(client.get("updated"))),
            "reset_queries": num(client.get("resetQueries")),
            "serial_queries": num(client.get("serialQueries")),
            "written_bytes": num(client.get("written")),
            "read_bytes": num(client.get("read")),
            "last_reset_seconds": seconds_since(now, parse_ts(client.get("lastReset"))),
        }
    return out_rtr, clients


def build_data(status, cfg):
    now = parse_ts(status.get("now")) or datetime.now(timezone.utc)
    serial = num(status.get("serial"))
    rtr, clients = build_rtr(status, serial, now)
    return {
        "global": build_global(status, now),
        "rtr": rtr,
        "repos": build_repos(status, cfg),
        "tal": build_tal(status),
        "client": clients,
    }


def emit(output):
    """Serialise the envelope, gzip + base64 it, and print to stdout. LibreNMS
    auto-detects and decodes this."""
    text = json.dumps(output)
    print(base64.b64encode(gzip.compress(text.encode("utf-8"))).decode("ascii"))


def main():
    output = {"version": 1, "error": 0, "errorString": "", "data": {}}

    try:
        cfg = load_config()
    except (ValueError, OSError) as err:
        output["error"] = 1
        output["errorString"] = "config error: %s" % err
        emit(output)
        return

    # A failed fetch is itself the most important signal (Routinator's HTTP
    # server, or the whole process, is likely down). Emit the error envelope.
    try:
        with urllib.request.urlopen(cfg["url"], timeout=cfg["timeout"]) as resp:
            status = json.loads(resp.read().decode("utf-8"))
    except Exception as err:  # noqa: BLE001 - any failure becomes the signal
        output["error"] = 1
        output["errorString"] = "fetch %s failed: %s" % (cfg["url"], err)
        emit(output)
        return

    try:
        output["data"] = build_data(status, cfg)
    except Exception as err:  # noqa: BLE001 - never emit partial/garbage JSON
        output["error"] = 2
        output["errorString"] = "parse error: %s" % err
        output["data"] = {}

    emit(output)


if __name__ == "__main__":
    sys.exit(main())
