#!/bin/sh
#
# lm-sensors-pass.sh
#
# net-snmp pass_persist handler that emulates the LM-SENSORS-MIB temperature
# and fan tables from sysfs, from a SINGLE snmpd line
# (UCI: config pass / option miboid / option persist '1'):
#
#   pass_persist .1.3.6.1.4.1.2021.13.16 /usr/libexec/openwrt-snmp/lm-sensors-pass.sh
#
# Temperatures come from /sys/devices/virtual/thermal/thermal_zone*, fans from
# /sys/class/hwmon/*/fan*_input (a tachometer input is required — e.g.
# kmod-hwmon-pwmfan; PWM-only fans with no readback expose nothing here).
# Sensors are discovered live at request time; both tables re-index
# sequentially from 1.
#
# Object layout (LM-SENSORS-MIB, .1.3.6.1.4.1.2021.13.16):
#   .2.1.1.<i>   lmTempSensorsIndex    integer
#   .2.1.2.<i>   lmTempSensorsDevice   string   (thermal zone type)
#   .2.1.3.<i>   lmTempSensorsValue    gauge    (milli-degrees C)
#   .3.1.1.<i>   lmFanSensorsIndex     integer
#   .3.1.2.<i>   lmFanSensorsDevice    string   (fan label, or hwmon name)
#   .3.1.3.<i>   lmFanSensorsValue     gauge    (RPM)
#
# Modes:
#   pass_persist (default): read PING/get/getnext on stdin (snmpd uses this).
#   one-shot for testing:   lm-sensors-pass.sh -g <OID>
#                           lm-sensors-pass.sh -n <OID>
#
# Testing without a device: set OPENWRT_LMS_THERMAL_DIR / OPENWRT_LMS_HWMON_DIR
# to directories mimicking the sysfs layout.

BASE=".1.3.6.1.4.1.2021.13.16"
TEMP_ENTRY="$BASE.2.1"
FAN_ENTRY="$BASE.3.1"

THERMAL_DIR="${OPENWRT_LMS_THERMAL_DIR:-/sys/devices/virtual/thermal}"
HWMON_DIR="${OPENWRT_LMS_HWMON_DIR:-/sys/class/hwmon}"

# Snapshot cache TTL (seconds). A single SNMP walk issues many getnext calls;
# caching avoids re-reading every sysfs node for every OID in the walk.
TTL="${OPENWRT_LMS_TTL:-5}"

SNAP_FILE="/tmp/lm-sensors-pass.$$.snap"
SNAP_TS=0
trap 'rm -f "$SNAP_FILE"' EXIT INT TERM

now() { date +%s 2>/dev/null || echo 0; }

# --------------------------------------------------------------------------
# Data collection: one "index<TAB>device<TAB>value" record per sensor,
# re-indexed sequentially from 1. Device strings are stripped of tabs so they
# cannot break the record format.
# --------------------------------------------------------------------------
get_zones() {
    idx=0
    for zone in "$THERMAL_DIR"/thermal_zone*; do
        [ -d "$zone" ] || continue
        idx=$((idx + 1))
        zone_type=$(cat "$zone/type" 2>/dev/null | tr -d '\t')
        zone_temp=$(cat "$zone/temp" 2>/dev/null)
        printf '%d\t%s\t%s\n' "$idx" "${zone_type:-unknown}" "${zone_temp:-0}"
    done
}

get_fans() {
    idx=0
    for input in "$HWMON_DIR"/hwmon*/fan*_input; do
        [ -r "$input" ] || continue
        idx=$((idx + 1))
        hw=$(dirname "$input")
        label_file="${input%_input}_label"
        name=$(cat "$label_file" 2>/dev/null || cat "$hw/name" 2>/dev/null)
        name=$(printf '%s' "${name:-fan}" | tr -d '\t')
        rpm=$(cat "$input" 2>/dev/null)
        printf '%d\t%s\t%s\n' "$idx" "$name" "${rpm:-0}"
    done
}

# --------------------------------------------------------------------------
# Snapshot: emit all instance OIDs in lexicographic (numeric) order as
# "<oid>\t<type>\t<value>" lines. Order is produced directly (column-major per
# table, tables in OID order) so no post-sort is required.
# --------------------------------------------------------------------------
emit_table() {
    # $1 = entry OID, stdin = index/device/value records
    awk -F '\t' -v entry="$1" '
        { n++; idx[n]=$1; dev[n]=$2; val[n]=$3 }
        END {
            for (i = 1; i <= n; i++) printf "%s.1.%s\tinteger\t%s\n", entry, idx[i], idx[i]
            for (i = 1; i <= n; i++) printf "%s.2.%s\tstring\t%s\n", entry, idx[i], dev[i]
            for (i = 1; i <= n; i++) printf "%s.3.%s\tgauge\t%s\n", entry, idx[i], val[i]
        }'
}

build_snapshot() {
    {
        get_zones | emit_table "$TEMP_ENTRY"
        get_fans | emit_table "$FAN_ENTRY"
    } > "$SNAP_FILE"
}

refresh_snapshot() {
    t=$(now)
    if [ ! -s "$SNAP_FILE" ] || [ "$((t - SNAP_TS))" -ge "$TTL" ]; then
        build_snapshot
        SNAP_TS=$t
    fi
}

# --------------------------------------------------------------------------
# Request handling
# --------------------------------------------------------------------------
handle_get() {
    req="$1"
    refresh_snapshot
    awk -F '\t' -v req="$req" '
        $1 == req { print $1; print $2; print $3; found=1; exit }
        END { if (!found) print "NONE" }
    ' "$SNAP_FILE"
}

handle_getnext() {
    req="$1"
    refresh_snapshot
    # Snapshot is pre-sorted; return the first OID numerically greater than req.
    awk -F '\t' -v req="$req" '
        function oidgt(a, b,   na, nb, m, i, x, y) {
            na = split(a, A, "."); nb = split(b, B, ".")
            m = (na > nb) ? na : nb
            for (i = 1; i <= m; i++) {
                x = (i <= na) ? A[i] + 0 : -1
                y = (i <= nb) ? B[i] + 0 : -1
                if (x > y) return 1
                if (x < y) return -1
            }
            return 0
        }
        oidgt($1, req) > 0 { print $1; print $2; print $3; found=1; exit }
        END { if (!found) print "NONE" }
    ' "$SNAP_FILE"
}

# --------------------------------------------------------------------------
# One-shot CLI (testing / pass-style), or pass_persist stdin loop.
# --------------------------------------------------------------------------
case "${1:-}" in
    -g) handle_get "$2"; exit 0 ;;
    -n) handle_getnext "$2"; exit 0 ;;
    --snapshot) build_snapshot; cat "$SNAP_FILE"; exit 0 ;;  # debug: full OID table
    -h|--help)
        echo "Usage: $0 [-g OID | -n OID | --snapshot]" >&2
        echo "       (no args: pass_persist mode on stdin)" >&2
        exit 0 ;;
esac

# pass_persist protocol
while read -r cmd; do
    case "$cmd" in
        PING|ping) echo "PONG" ;;
        get)     read -r oid; handle_get "$oid" ;;
        getnext) read -r oid; handle_getnext "$oid" ;;
        set)     read -r oid; read -r _val; echo "not-writable" ;;
        "")      : ;;
        *)       : ;;
    esac
done
