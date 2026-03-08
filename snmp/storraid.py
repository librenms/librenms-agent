#!/usr/bin/env python3
"""
LibreNMS SNMP Extend Agent -- StorCLI RAID Monitor
===================================================
Monitors MegaRAID/StorCLI controllers:
  - Controller status, memory, temperature & BBU/CacheVault
  - Virtual Disk (RAID array) state & rebuild progress
  - Physical Disk health, error counts, SMART alerts

Requires: Python >= 3.7, storcli64 installed

----------------------------------------------------------------------
Deployment model
----------------------------------------------------------------------
This script is NOT called directly by snmpd.  Instead:

  1. A cron job runs this script every 5 minutes and writes the output
     to /var/run/storraid.json (atomic write).

  2. snmpd serves that file via extend + cat — response is instant.

snmpd.conf:
  extend storraid /bin/cat /var/run/storraid.json

/etc/cron.d/storraid:
4,9,14,19,24,29,34,39,44,49,54,59 * * * * root /etc/snmp/storraid.py > storraid.tmp; mv -f storraid.tmp /var/run/storraid.json

This eliminates SNMP timeouts and graph gaps entirely — snmpd never
blocks waiting for storcli.  Data is at most ~60 s old.
----------------------------------------------------------------------

Call sequence:
  1. /call show all           -> inventory + health + mem + temp for all ctrlrs
  2. /call/vALL show          -> VD detail (name, access, cache, consist, state)
  3. /call/eALL/sALL show all -> PD summary + per-disk detail in one call
  + /call/bbu show + /call/cv show  (only if BBU present, ~1 s each)

storcli64 is NOT concurrency-safe — all calls are sequential.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime
from typing import Any, Dict, List, Optional, Tuple

# ── Config ─────────────────────────────────────────────────────────────────────
STORCLI_PATHS = [
    "/opt/MegaRAID/storcli/storcli64",
    "/usr/local/sbin/storcli64",
    "/usr/local/sbin/storcli",
    "/usr/sbin/storcli64",
    "/usr/sbin/storcli",
    "/opt/storcli/storcli64",
]

OUTPUT_PATH = "/var/run/storraid.json"

# Severity: 0=OK, 1=warn, 2=crit
CTRL_STATE_MAP = {
    "optimal": 0,
    "degraded": 2,
    "failed": 2,
    "offline": 2,
    "partially degraded": 1,
    "needs attention": 1,
}

VD_STATE_MAP = {
    "optl": 0,  # Optimal
    "dgrd": 2,  # Degraded
    "pdgd": 1,  # Partially Degraded
    "offln": 2,  # Offline
    "recov": 1,  # Recovery
    "init": 1,  # Initializing
    "check": 0,  # Consistency Check (normal)
    "bkgdi": 0,  # Background Init (normal)
}

PD_STATE_MAP = {
    "onln": 0,  # Online
    "ugood": 0,  # Unconfigured Good
    "uhsp": 0,  # Unconfigured Hot Spare
    "dhs": 0,  # Dedicated Hot Spare
    "ghs": 0,  # Global Hot Spare
    "rbld": 1,  # Rebuilding
    "cfgd": 0,  # Configured
    "offln": 2,  # Offline
    "failed": 2,  # Failed
    "miss": 2,  # Missing
    "shld": 0,  # Shielded
}

BBU_STATE_MAP = {
    "optimal": 0,
    "failed": 2,
    "degraded": 2,
    "learning": 1,
    "charging": 1,
    "discharging": 1,
    "replacing": 1,
    "absent": 1,
    "unknown": 1,
}


# ── Helpers ────────────────────────────────────────────────────────────────────


def find_storcli():
    # type: () -> Optional[str]
    for path in STORCLI_PATHS:
        if os.path.isfile(path) and os.access(path, os.X_OK):
            return path
    for name in ("storcli64", "storcli"):
        try:
            r = subprocess.run(
                ["which", name], stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            if r.returncode == 0:
                return r.stdout.decode("utf-8", errors="replace").strip()
        except Exception:
            pass
    return None


def run_storcli(storcli, *args):
    # type: (str, *str) -> Dict[str, Any]
    """Run storcli with the given args plus 'J' and return parsed JSON.
    Returns {"error": "..."} on any failure."""
    cmd = [storcli] + list(args) + ["J"]
    try:
        r = subprocess.run(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        out = r.stdout.decode("utf-8", errors="replace")
        if not out.strip():
            err = r.stderr.decode("utf-8", errors="replace").strip()
            return {"error": "storcli exit {}: {}".format(r.returncode, err)}
        return json.loads(out)
    except subprocess.TimeoutExpired:
        return {"error": "storcli command timed out"}
    except (ValueError, KeyError) as exc:
        return {"error": "JSON parse error: {}".format(exc)}
    except Exception as exc:
        return {"error": str(exc)}


def cleanup_storcli_log():
    # type: () -> None
    """Remove the storcli.log file that storcli unconditionally creates in the
    current working directory, even when called with nolog."""
    for name in ("storcli.log", "storcli64.log"):
        try:
            os.unlink(os.path.join(os.getcwd(), name))
        except OSError:
            pass  # Already gone or never created — not an error


def map_severity(state_map, state_str):
    # type: (Dict[str, int], str) -> int
    return state_map.get(str(state_str).lower().strip(), 1)


def safe_int(value, default=0):
    # type: (Any, int) -> int
    try:
        return int(value or default)
    except (TypeError, ValueError):
        return default


def ctrl_ok(entry):
    # type: (Dict[str, Any]) -> bool
    return str(entry.get("Command Status", {}).get("Status", "")).lower() == "success"


def get_resp(entry):
    # type: (Dict[str, Any]) -> Dict[str, Any]
    return entry.get("Response Data", {})


def _deep_find(obj, keys, bad=("N/A", "")):
    # type: (Any, Tuple[str, ...], Tuple[str, ...]) -> Any
    """Recursively search a nested structure for the first non-bad value
    matching any of *keys*."""
    if isinstance(obj, dict):
        for k in keys:
            v = obj.get(k)
            if v is not None and str(v) not in bad:
                return v
        for v in obj.values():
            r = _deep_find(v, keys, bad)
            if r is not None:
                return r
    elif isinstance(obj, list):
        for item in obj:
            r = _deep_find(item, keys, bad)
            if r is not None:
                return r
    return None


# ── Controller parsing ─────────────────────────────────────────────────────────


def parse_controllers(raw):
    # type: (Dict[str, Any]) -> List[Dict[str, Any]]
    """Build controller list from a /call show all J response."""
    if "error" in raw:
        return [{"error": raw["error"]}]

    controllers = []
    for entry in raw.get("Controllers", []):
        cid = int(entry.get("Command Status", {}).get("Controller", 0))

        if not ctrl_ok(entry):
            controllers.append(
                {
                    "id": cid,
                    "model": "Unknown",
                    "serial": "N/A",
                    "firmware": "N/A",
                    "memory_mb": "N/A",
                    "state": "Failed",
                    "severity": 2,
                    "temperature": None,
                    "vd_count": 0,
                    "pd_count": 0,
                    "bbu": None,
                    "is_hba": True,
                }
            )
            continue

        resp = get_resp(entry)
        basics = resp.get("Basics", {})
        version = resp.get("Version", {})
        status = resp.get("Status", {})

        # Newer storcli (>= ~007.17) nests fields under Basics/Version/Status;
        # older firmware puts them flat in Response Data.
        model = (basics.get("Model") or resp.get("Product Name", "Unknown")).strip()
        serial = (
            basics.get("Serial Number") or resp.get("Serial Number", "N/A")
        ).strip()
        firmware = (
            version.get("Firmware Version")
            or resp.get("FW Version")
            or version.get("Firmware Package Build")
            or resp.get("FW Package Build", "N/A")
        ).strip()

        vd_count = safe_int(resp.get("Virtual Drives", 0))
        pd_count = safe_int(resp.get("Physical Drives", 0))
        is_hba = vd_count == 0 and "TOPOLOGY" not in resp and "VD LIST" not in resp

        if is_hba:
            ctrl_state, ctrl_sev = "N/A (HBA)", 0
        else:
            ctrl_state_raw = status.get("Controller Status") or resp.get(
                "Controller Status", ""
            )
            if ctrl_state_raw:
                ctrl_state = ctrl_state_raw
                ctrl_sev = map_severity(CTRL_STATE_MAP, ctrl_state_raw)
            else:
                found = None
                for section in (resp.get("Basics", {}), resp.get("HwCfg", {})):
                    if not found and isinstance(section, dict):
                        for key in ("Controller Status", "Health", "Status"):
                            val = section.get(key)
                            if val and isinstance(val, str):
                                found = val
                                break
                ctrl_state = found or "Optimal"
                ctrl_sev = map_severity(CTRL_STATE_MAP, ctrl_state)

        mem_val = _deep_find(
            resp, ("On Board Memory Size", "Memory Size", "Memory"), bad=("N/A", "")
        )
        mem = str(mem_val) if mem_val is not None else ("0MB" if is_hba else "N/A")

        temp_val = _deep_find(
            resp,
            (
                "ROC temperature(Degree Celsius)",
                "ROC temperature(Degree Celcius)",
                "Ctrl Temp",
                "ROC Temp",
            ),
            bad=("N/A", ""),
        )
        try:
            temp_c = (
                int(temp_val) if temp_val is not None else None
            )  # type: Optional[int]
        except (TypeError, ValueError):
            temp_c = None

        controllers.append(
            {
                "id": cid,
                "model": model,
                "serial": serial,
                "firmware": firmware,
                "memory_mb": mem,
                "state": ctrl_state,
                "severity": ctrl_sev,
                "temperature": temp_c,
                "vd_count": vd_count,
                "pd_count": pd_count,
                "bbu": None,  # filled after BBU pass
                "is_hba": is_hba,
            }
        )

    return controllers or [{"error": "No controllers found"}]


# ── BBU / CacheVault ───────────────────────────────────────────────────────────


def fetch_bbu(storcli):
    # type: (str) -> Dict[int, Dict[str, Any]]
    """Fetch BBU and CacheVault info for all controllers.
    Returns {controller_id: bbu_dict}."""
    bbu_by_ctrl = {}  # type: Dict[int, Dict[str, Any]]
    for sub, bbu_type in (("/call/bbu", "BBU"), ("/call/cv", "CacheVault")):
        raw = run_storcli(storcli, sub, "show")
        if "error" in raw:
            continue
        for entry in raw.get("Controllers", []):
            if not ctrl_ok(entry):
                continue
            cid = int(entry.get("Command Status", {}).get("Controller", -1))
            if cid < 0 or cid in bbu_by_ctrl:
                continue
            resp = get_resp(entry)
            info_list = (
                resp.get("BBU_Info")
                or resp.get("BBU Info")
                or resp.get("Cachevault_Info")
                or resp.get("CacheVault_Info")
                or resp.get("Cachevault Info")
                or []
            )
            if not isinstance(info_list, list) or not info_list:
                if isinstance(resp, dict) and resp.get("State"):
                    info_list = [resp]
                else:
                    continue
            b = info_list[0]
            state = b.get("State", b.get("Status", "Unknown"))
            bbu_by_ctrl[cid] = {
                "type": bbu_type,
                "state": state,
                "temperature": str(b.get("Temp", b.get("Temperature", "N/A"))),
                "charge_pct": str(
                    b.get(
                        "Charge",
                        b.get(
                            "Relative State of Charge",
                            b.get("Replacement required", "N/A"),
                        ),
                    )
                ),
                "severity": map_severity(BBU_STATE_MAP, state),
            }
    return bbu_by_ctrl


# ── Virtual Disks ──────────────────────────────────────────────────────────────


def parse_virtual_disks(storcli, raid_ctrl_ids, raw):
    # type: (str, List[int], Dict[str, Any]) -> List[Dict[str, Any]]
    if "error" in raw:
        return []
    vds = []
    for entry in raw.get("Controllers", []):
        cid = int(entry.get("Command Status", {}).get("Controller", -1))
        if cid not in raid_ctrl_ids or not ctrl_ok(entry):
            continue
        for row in get_resp(entry).get("Virtual Drives", []):
            dg_vd = str(row.get("DG/VD", "?"))
            state_raw = row.get("State", "Unknown")
            state_sev = map_severity(VD_STATE_MAP, state_raw)
            vd_idx = dg_vd.split("/")[-1] if "/" in dg_vd else dg_vd
            progress = (
                _get_vd_progress(storcli, cid, vd_idx) if state_sev == 1 else None
            )
            vds.append(
                {
                    "controller": cid,
                    "id": dg_vd,
                    "name": row.get("Name", "").strip() or "VD{}".format(dg_vd),
                    "raid_level": row.get("TYPE", row.get("Type", "Unknown")),
                    "state": state_raw,
                    "severity": state_sev,
                    "size": row.get("Size", "N/A"),
                    "access": row.get("Access", "N/A"),
                    "cache": row.get("Cache", "N/A"),
                    "consist": row.get("Consist", "N/A"),
                    "progress_pct": progress,
                }
            )
    return vds


def _get_vd_progress(storcli, cid, vd_idx):
    # type: (str, int, str) -> Optional[float]
    """Fetch rebuild/init progress % for a degraded VD."""
    for subcmd in ("show", "show rebuild", "show init"):
        raw = run_storcli(storcli, "/c{}/v{}".format(cid, vd_idx), subcmd)
        if "error" in raw:
            continue
        for entry in raw.get("Controllers", []):
            for val in get_resp(entry).values():
                if isinstance(val, dict):
                    for k, v in val.items():
                        if "progress" in k.lower():
                            try:
                                return float(v)
                            except (TypeError, ValueError):
                                pass
    return None


# ── Physical Disks ─────────────────────────────────────────────────────────────


def parse_physical_disks(ctrl_ids, raw):
    # type: (List[int], Dict[str, Any]) -> List[Dict[str, Any]]
    """Parse PD summary and detail from a /call/eALL/sALL show all J response."""
    if "error" in raw:
        return []
    pds = []
    for entry in raw.get("Controllers", []):
        cid = int(entry.get("Command Status", {}).get("Controller", -1))
        if cid not in ctrl_ids or not ctrl_ok(entry):
            continue

        resp = get_resp(entry)
        pd_rows = resp.get("Drive Information") or resp.get("PD LIST")
        if not isinstance(pd_rows, list) or not pd_rows:
            pd_rows = []
            for k, v in resp.items():
                if (
                    k.startswith("Drive /c")
                    and "Detailed" not in k
                    and isinstance(v, list)
                    and v
                ):
                    pd_rows.extend(v)
        if not pd_rows:
            continue

        detail_by_key = {
            k: v
            for k, v in resp.items()
            if isinstance(v, dict) and "Detailed Information" in k
        }

        for row in pd_rows:
            eid_slot = str(row.get("EID:Slt", "?"))
            state_raw = row.get("State", "Unknown")
            state_sev = map_severity(PD_STATE_MAP, state_raw)

            parts = eid_slot.split(":")
            eid = parts[0] if len(parts) > 0 else "0"
            slot = parts[1] if len(parts) > 1 else "0"

            attrs, drv_state = _extract_pd_detail(resp, detail_by_key, cid, eid, slot)

            media_err = safe_int(drv_state.get("Media Error Count", 0))
            other_err = safe_int(drv_state.get("Other Error Count", 0))
            pred_fail = str(drv_state.get("Predictive Failure Count", "0"))
            smart_raw = (
                str(
                    drv_state.get(
                        "S.M.A.R.T alert flagged by drive",
                        drv_state.get("SMART alert", "No"),
                    )
                )
                .strip()
                .lower()
            )

            if smart_raw == "yes" or media_err > 0:
                state_sev = max(state_sev, 2)
            elif other_err > 5 or pred_fail not in ("0", "N/A", "", "None"):
                state_sev = max(state_sev, 1)

            temp_raw = (
                drv_state.get("Drive Temperature")
                or attrs.get("Drive Temperature")
                or attrs.get("Temperature", "")
            )
            try:
                temp_c = int(
                    str(temp_raw).strip().split("C")[0].strip()
                )  # type: Optional[int]
            except (ValueError, IndexError):
                temp_c = None

            pds.append(
                {
                    "controller": cid,
                    "eid_slot": eid_slot,
                    "vd": str(row.get("DG", "N/A")),
                    "state": state_raw,
                    "severity": state_sev,
                    "size": row.get("Size", "N/A"),
                    "media_type": row.get("Med", "Unknown"),
                    "interface": row.get("Intf", "Unknown"),
                    "model": (
                        attrs.get("Model Number")
                        or attrs.get("Model")
                        or row.get("Model", "Unknown")
                    ),
                    "serial": (
                        attrs.get("Serial Number")
                        or attrs.get("SN")
                        or row.get("SN", "N/A")
                    ).strip(),
                    "firmware": (
                        attrs.get("Firmware Revision")
                        or attrs.get("Firmware")
                        or row.get("Fw", "N/A")
                    ),
                    "temperature": temp_c,
                    "media_errors": media_err,
                    "other_errors": other_err,
                    "pred_failure": pred_fail,
                    "smart_alert": smart_raw == "yes",
                }
            )
    return pds


def _extract_pd_detail(resp, detail_by_key, cid, eid, slot):
    # type: (Dict[str, Any], Dict[str, Dict[str, Any]], int, str, str) -> Tuple[Dict[str, Any], Dict[str, Any]]
    base = "Drive /c{}/e{}/s{}".format(cid, eid, slot)
    detail = (
        detail_by_key.get("{} - Detailed Information".format(base))
        or detail_by_key.get("{} Detailed Information".format(base))
        or resp.get("{} - Detailed Information".format(base), {})
        or resp.get("{} Detailed Information".format(base), {})
    )
    if not isinstance(detail, dict) or not detail:
        return {}, {}

    attrs_key = "{} Device attributes".format(base)
    state_key = "{} State".format(base)
    attrs = detail.get(attrs_key, {})
    drv_state = detail.get(state_key, {})

    if not attrs or not drv_state:
        for k, v in detail.items():
            if not isinstance(v, dict):
                continue
            kl = k.lower()
            if not attrs and ("device attr" in kl or "attributes" in kl):
                attrs = v
            elif not drv_state and kl.endswith("state"):
                drv_state = v

    return attrs, drv_state


# ── Output ─────────────────────────────────────────────────────────────────────


def _envelope(error, error_string, data):
    # type: (int, str, Any) -> str
    return json.dumps(
        {
            "error": error,
            "errorString": error_string,
            "version": "1",
            "data": data,
        }
    )


def write_output(text):
    # type: (str) -> None
    """Print to stdout (for manual runs) and atomically update the output file
    so snmpd's cat always reads a complete JSON document."""
    print(text)
    try:
        dir_ = os.path.dirname(OUTPUT_PATH) or "/tmp"
        fd, tmp = tempfile.mkstemp(dir=dir_, prefix=".storraid_out_")
        os.fchmod(fd, 0o644)
        try:
            with os.fdopen(fd, "w") as f:
                f.write(text + "\n")
            os.replace(tmp, OUTPUT_PATH)
        except Exception:
            try:
                os.unlink(tmp)
            except OSError:
                pass
    except Exception:
        pass  # Non-fatal: stdout is the authoritative output


# ── Main ───────────────────────────────────────────────────────────────────────


def main():
    output = {
        "version": "1",
        "application": "storraid",
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "error": None,
        "controllers": [],
        "virtual_disks": [],
        "physical_disks": [],
        "summary": {
            "overall_severity": 0,
            "ctrl_count": 0,
            "vd_count": 0,
            "pd_count": 0,
            "ctrl_ok": 0,
            "ctrl_warn": 0,
            "ctrl_crit": 0,
            "vd_ok": 0,
            "vd_warn": 0,
            "vd_crit": 0,
            "pd_ok": 0,
            "pd_warn": 0,
            "pd_crit": 0,
        },
    }

    storcli = find_storcli()
    if not storcli:
        err = "storcli not found. Install storcli64 to one of: " + ", ".join(
            STORCLI_PATHS
        )
        output["error"] = err
        write_output(_envelope(1, err, output))
        sys.exit(0)

    # ── Call 1: /call show all ────────────────────────────────────────────────
    # Inventory + health + HwCfg (memory, temperature) for all controllers.
    raw_ctrl = run_storcli(storcli, "/call", "show", "all")
    controllers = parse_controllers(raw_ctrl)
    output["controllers"] = controllers

    raid_ctrl_ids = [
        c["id"] for c in controllers if "error" not in c and not c.get("is_hba")
    ]
    all_ctrl_ids = [c["id"] for c in controllers if "error" not in c]

    if not all_ctrl_ids:
        err = (
            controllers[0].get("error", "No controllers found")
            if controllers
            else "No controllers found"
        )
        output["error"] = err
        cleanup_storcli_log()
        write_output(_envelope(1, err, output))
        sys.exit(0)

    # ── BBU (optional, ~1 s each if present) ─────────────────────────────────
    bbu_needed = any(
        _deep_find(get_resp(e), ("BBU",), bad=("N/A", "", "Absent", "absent"))
        for e in raw_ctrl.get("Controllers", [])
        if ctrl_ok(e)
    )
    if bbu_needed:
        bbu_by_ctrl = fetch_bbu(storcli)
        for ctrl in controllers:
            if not ctrl.get("is_hba"):
                ctrl["bbu"] = bbu_by_ctrl.get(ctrl["id"])

    # ── Call 2: /call/vALL show ───────────────────────────────────────────────
    # Full VD detail: name, access, cache, consist, state for all controllers.
    raw_vd = run_storcli(storcli, "/call/vALL", "show")
    output["virtual_disks"] = parse_virtual_disks(storcli, raid_ctrl_ids, raw_vd)

    # ── Call 3: /call/eALL/sALL show all ─────────────────────────────────────
    # Returns PD summary rows AND per-disk detail (errors, SMART, temp) in one
    # call — replaces N separate /cN/eE/sS show all calls.
    raw_pd = run_storcli(storcli, "/call/eALL/sALL", "show", "all")
    output["physical_disks"] = parse_physical_disks(all_ctrl_ids, raw_pd)

    # ── Summary ───────────────────────────────────────────────────────────────
    s = output["summary"]
    s["ctrl_count"] = len(controllers)
    s["vd_count"] = len(output["virtual_disks"])
    s["pd_count"] = len(output["physical_disks"])

    all_sev = []
    for c in controllers:
        sev = c.get("severity", 0)
        all_sev.append(sev)
        if sev == 0:
            s["ctrl_ok"] += 1
        elif sev == 1:
            s["ctrl_warn"] += 1
        else:
            s["ctrl_crit"] += 1
        if c.get("bbu"):
            all_sev.append(c["bbu"].get("severity", 0))
    for vd in output["virtual_disks"]:
        sev = vd.get("severity", 0)
        all_sev.append(sev)
        if sev == 0:
            s["vd_ok"] += 1
        elif sev == 1:
            s["vd_warn"] += 1
        else:
            s["vd_crit"] += 1
    for pd in output["physical_disks"]:
        sev = pd.get("severity", 0)
        all_sev.append(sev)
        if sev == 0:
            s["pd_ok"] += 1
        elif sev == 1:
            s["pd_warn"] += 1
        else:
            s["pd_crit"] += 1

    s["overall_severity"] = max(all_sev) if all_sev else 0
    cleanup_storcli_log()
    write_output(_envelope(0, "", output))


if __name__ == "__main__":
    main()
