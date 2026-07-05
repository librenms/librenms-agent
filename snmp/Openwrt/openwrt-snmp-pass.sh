#!/bin/sh
#
# openwrt-snmp-pass.sh
#
# net-snmp pass_persist handler that serves the OpenWrt wireless subtree
# openwrtWireless = OPENWRT-WIRELESS-MIB { openwrtObjects 10 } from a SINGLE snmpd line
# (UCI: config pass / option miboid / option persist '1'):
#
#   pass_persist .1.3.6.1.4.1.60652.102.1.10 /usr/libexec/openwrt-snmp/openwrt-snmp-pass.sh
#
# Radios/VAPs are discovered live at request time (no per-interface or
# per-metric configuration). Rows are indexed by the kernel ifIndex, so the
# table joins onto IF-MIB ifTable/ifXTable.
#
# Object layout (relative to the wireless base .102.1.10):
#   .1.0                         openwrtWirelessInterfaceCount   (gauge)
#   .2.0                         openwrtWirelessClientCount      (gauge, AP-side)
#   .3.1.<col>.<ifIndex>         openwrtWirelessInterfaceTable columns:
#       col 2  Name        string     col10  RxRateMin    gauge
#       col 3  Label       string     col11  RxRateAvg    gauge
#       col 4  Clients     gauge      col12  RxRateMax    gauge
#       col 5  Frequency   gauge      col13  SnrMin       integer
#       col 6  NoiseFloor  integer    col14  SnrAvg       integer
#       col 7  TxRateMin   gauge      col15  SnrMax       integer
#       col 8  TxRateAvg   gauge      col16  ChannelUtil  gauge   (percent)
#       col 9  TxRateMax   gauge      col17  TxPower      integer (dBm)
#   (col 1, openwrtWlIfaceIfIndex, is the not-accessible table index.)
#
# Modes:
#   pass_persist (default): read PING/get/getnext on stdin (snmpd uses this).
#   one-shot for testing:   openwrt-snmp-pass.sh -g <OID>
#                           openwrt-snmp-pass.sh -n <OID>
#
# Testing without a device: set OPENWRT_WL_MOCK=<file> to a TSV of pre-built
# interface records (see collect_records() for the field order); the metric
# collectors and iwinfo are then bypassed.

BASE=".1.3.6.1.4.1.60652.102"
WL="$BASE.1.10"       # openwrtWireless = { openwrtObjects 10 }
IFCOUNT_OID="$WL.1.0"
CLIENTS_OID="$WL.2.0"
ENTRY="$WL.3.1"

# Snapshot cache TTL (seconds). A single SNMP walk issues many getnext calls;
# caching avoids re-running iwinfo/iw for every OID in the walk.
TTL="${OPENWRT_WL_TTL:-20}"

SCRIPTDIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo .)
TAB=$(printf '\t')

SNAP_FILE="/tmp/openwrt-snmp-pass.$$.snap"
SNAP_TS=0
trap 'rm -f "$SNAP_FILE"' EXIT INT TERM

now() { date +%s 2>/dev/null || echo 0; }

# --------------------------------------------------------------------------
# Data collection
# --------------------------------------------------------------------------
# collect_records: one tab-separated record per wireless interface, fields:
#   1 ifIndex   2 name    3 label    4 clients  5 freqMHz  6 noiseDbm
#   7 txMin  8 txAvg  9 txMax  10 rxMin 11 rxAvg 12 rxMax
#   13 snrMin 14 snrAvg 15 snrMax
# Interfaces without a readable /sys ifindex are skipped (cannot be indexed).

sanitize_int() {
    # First signed integer token, decimals truncated; default 0.
    printf '%s' "$1" | awk '
        { if (match($0, /-?[0-9]+/)) print substr($0, RSTART, RLENGTH) + 0; else print 0; exit }
        END { if (NR == 0) print 0 }'
}

# Helper command paths (overridable for testing).
WLIFACES="${OPENWRT_WL_IFACES_CMD:-$SCRIPTDIR/wlInterfaces.sh}"
WLCLIENTS="${OPENWRT_WL_CLIENTS_CMD:-$SCRIPTDIR/wlClients.sh}"

to_lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

iface_ifindex() {
    if [ -n "${OPENWRT_WL_IFINDEX_MAP:-}" ]; then
        awk -v k="$1" '$1==k {print $2; exit}' "$OPENWRT_WL_IFINDEX_MAP"
        return
    fi
    cat "/sys/class/net/$1/ifindex" 2>/dev/null
}

iface_associated() {
    # For client/STA interfaces with an empty assoc list: 1 when associated, else 0.
    ap=$(iwinfo "$1" info 2>/dev/null | sed -n 's/.*Access Point:[[:space:]]*\([^ ]\+\).*/\1/p' | head -1)
    case "$ap" in
        ''|Not-Associated|00:00:00:00:00:00) echo 0 ;;
        *) echo 1 ;;
    esac
}

# --------------------------------------------------------------------------
# Per-interface metric collection. ubus-first (the OpenWrt-native, structured
# path) with an iwinfo-CLI fallback. Both emit the SAME tagged block so a single
# aggregator handles either source. This replaces the previous ~15 iwinfo/iw
# invocations per interface (which risked exceeding snmpd's pass timeout on a
# cold cache) with one ubus call-set (or two iwinfo CLI calls) per interface.
#
# Tagged block (line order irrelevant):
#   MODE <s>  FREQ <mhz>  NOISE <dbm>  ASSOC <n>
#   RX <mbit>   TX <mbit>   SNR <db>      (one set per associated station)
# --------------------------------------------------------------------------

stats_via_ubus() {
    _if="$1"
    command -v ubus >/dev/null 2>&1 || return 1
    command -v jsonfilter >/dev/null 2>&1 || return 1
    ubus list iwinfo >/dev/null 2>&1 || return 1

    _info=$(ubus call iwinfo info "{\"device\":\"$_if\"}" 2>/dev/null)
    _assoc=$(ubus call iwinfo assoclist "{\"device\":\"$_if\"}" 2>/dev/null)
    [ -n "$_info$_assoc" ] || return 1

    printf 'MODE %s\n'    "$(printf '%s' "$_info" | jsonfilter -e '@.mode' 2>/dev/null)"
    printf 'FREQ %s\n'    "$(printf '%s' "$_info" | jsonfilter -e '@.frequency' 2>/dev/null)"
    printf 'NOISE %s\n'   "$(printf '%s' "$_info" | jsonfilter -e '@.noise' 2>/dev/null)"
    printf 'TXPOWER %s\n' "$(printf '%s' "$_info" | jsonfilter -e '@.txpower' 2>/dev/null)"

    # Associated-station count from a field that always exists per station
    # (iwinfo's assoclist JSON has no top-level "snr").
    printf 'ASSOC %s\n' "$(printf '%s' "$_assoc" | jsonfilter -e '@.results[*].signal' 2>/dev/null | awk 'NF' | wc -l | awk '{print $1}')"
    # iwinfo ubus rates are kbit/s -> Mbit/s.
    printf '%s' "$_assoc" | jsonfilter -e '@.results[*].rx.rate' 2>/dev/null | awk 'NF{printf "RX %d\n", $1/1000}'
    printf '%s' "$_assoc" | jsonfilter -e '@.results[*].tx.rate' 2>/dev/null | awk 'NF{printf "TX %d\n", $1/1000}'
    # No "snr" field in the JSON: compute SNR = per-station signal - noise,
    # pairing the two arrays by index. Skip stations whose noise floor is
    # unavailable (0), e.g. radios that do not report survey noise.
    { printf '%s' "$_assoc" | jsonfilter -e '@.results[*].signal' 2>/dev/null | sed 's/^/S /'
      printf '%s' "$_assoc" | jsonfilter -e '@.results[*].noise'  2>/dev/null | sed 's/^/N /'
    } | awk '
        $1=="S" { s[++a]=$2 }
        $1=="N" { n[++b]=$2 }
        END { for (i=1; i<=a; i++) if (n[i]+0 != 0) printf "SNR %d\n", s[i]-n[i] }'
    return 0
}

stats_via_cli() {
    _if="$1"
    command -v iwinfo >/dev/null 2>&1 || return 1
    _info=$(iwinfo "$_if" info 2>/dev/null)
    _assoc=$(iwinfo "$_if" assoclist 2>/dev/null)
    [ -n "$_info$_assoc" ] || return 1

    _mode=$(printf '%s\n' "$_info" | awk '{for(i=1;i<=NF;i++) if($i=="Mode:"){print $(i+1); exit}}')
    _freq=$(printf '%s\n' "$_info" | sed -n 's/.*(\([0-9]\{3,\}\)[[:space:]]*MHz).*/\1/p' | head -1)
    if [ -z "$_freq" ]; then
        _ghz=$(printf '%s\n' "$_info" | sed -n 's/.*[ (]\([0-9]\+\.[0-9]\+\)[[:space:]]*GHz.*/\1/p' | head -1)
        [ -n "$_ghz" ] && _freq=$(awk -v g="$_ghz" 'BEGIN{printf "%d", g*1000}')
    fi
    _noise=$(printf '%s\n' "$_info" | awk '{for(i=1;i<=NF;i++) if($i=="Noise:"){print $(i+1); exit}}')
    # "Tx-Power: 23 dBm"
    _txpower=$(printf '%s\n' "$_info" | sed -n 's/.*Tx-Power:[[:space:]]*\(-\{0,1\}[0-9]\{1,\}\).*/\1/p' | head -1)

    printf 'MODE %s\nFREQ %s\nNOISE %s\nTXPOWER %s\n' "$_mode" "$_freq" "$_noise" "$_txpower"

    printf '%s\n' "$_assoc" | awk '
        BEGIN { IGNORECASE=1; n=0 }
        /^[[:space:]]*([0-9a-f]{2}:){5}[0-9a-f]{2}[[:space:]]/ {
            n++
            if (match($0, /SNR[[:space:]]*-?[0-9]+/)) { s=substr($0,RSTART,RLENGTH); gsub(/[^0-9-]/,"",s); print "SNR " s }
            next
        }
        /^[[:space:]]*RX:[[:space:]]*[0-9]/ { print "RX " ($2 + 0) }
        /^[[:space:]]*TX:[[:space:]]*[0-9]/ { print "TX " ($2 + 0) }
        END { print "ASSOC " n }
    '

    # Fallback for client/STA where assoclist is empty: single current values.
    if ! printf '%s\n' "$_assoc" | grep -qiE '([0-9a-f]{2}:){5}[0-9a-f]{2}'; then
        _br=$(printf '%s\n' "$_info" | awk '{for(i=1;i<=NF;i++) if($i=="Rate:"){print $(i+1); exit}}')
        _sig=$(printf '%s\n' "$_info" | awk '{for(i=1;i<=NF;i++) if($i=="Signal:"){print $(i+1); exit}}')
        _br=$(sanitize_int "$_br")
        if [ "$_br" -gt 0 ] 2>/dev/null; then printf 'RX %s\nTX %s\n' "$_br" "$_br"; fi
        # Derive SNR only from a real signal reading (not absent / 0 / "unknown");
        # sanitize_int defaults to 0, so guard on the RAW value first.
        case "$_sig" in
            ''|0|unknown|*[!0-9-]*) ;;
            *)
                _nz=$(sanitize_int "$_noise")
                [ "$_nz" != 0 ] && printf 'SNR %s\n' "$(( $(sanitize_int "$_sig") - _nz ))"
                ;;
        esac
    fi
    return 0
}

# iface_airtime <iface>: channel airtime utilisation (percent) from hostapd ubus,
# or empty when unavailable (no ubus/jsonfilter, or client/STA without hostapd).
iface_airtime() {
    command -v ubus >/dev/null 2>&1 || return 0
    command -v jsonfilter >/dev/null 2>&1 || return 0
    ubus call "hostapd.$1" get_status 2>/dev/null | jsonfilter -e '@.airtime.utilization' 2>/dev/null
}

# iface_stats <iface>: emit the 14 numeric metric fields (tab-separated) in
# record column order 4..17: clients freq noise tx{min,avg,max} rx{min,avg,max}
# snr{min,avg,max} channelUtil txPower, plus a 15th trailing mode tag (used by
# build_snapshot for the AP-side aggregate, not an OID column).
iface_stats() {
    _if="$1"
    _block=$(stats_via_ubus "$_if") || _block=""
    [ -n "$_block" ] || _block=$(stats_via_cli "$_if") || _block=""
    # Channel utilisation is hostapd-only; append it to the block.
    _block="$_block
UTIL $(iface_airtime "$_if")"

    _mode=$(printf '%s\n' "$_block" | awk '$1=="MODE"{print $2; exit}')
    _agg=$(printf '%s\n' "$_block" | awk '
        $1=="FREQ"    {freq=$2}
        $1=="NOISE"   {noise=$2}
        $1=="ASSOC"   {assoc=$2}
        $1=="UTIL"    {util=$2}
        $1=="TXPOWER" {txpower=$2}
        $1=="RX"  {v=$2+0; rc++; rsum+=v; if(rmin==""||v<rmin)rmin=v; if(v>rmax)rmax=v}
        $1=="TX"  {v=$2+0; tc++; tsum+=v; if(tmin==""||v<tmin)tmin=v; if(v>tmax)tmax=v}
        $1=="SNR" {v=$2+0; sc++; ssum+=v; if(smin==""||v<smin)smin=v; if(v>smax)smax=v}
        END {
            printf "%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d|%d\n",
                (assoc==""?0:assoc), (freq==""?0:freq), (noise==""?0:noise),
                (tmin==""?0:tmin),(tc?tsum/tc:0),(tmax==""?0:tmax),
                (rmin==""?0:rmin),(rc?rsum/rc:0),(rmax==""?0:rmax),
                (smin==""?0:smin),(sc?ssum/sc:0),(smax==""?0:smax),
                (util==""?0:util), (txpower==""?0:txpower)
        }')
    IFS='|' read -r _assoc _freq _noise _tmin _tavg _tmax _rmin _ravg _rmax _smin _savg _smax _util _txpower <<EOF
$_agg
EOF

    # clients: AP -> validated hostapd dedup via wlClients.sh; client/STA -> peer
    # count (assoc list usually holds the upstream AP; 0/1 link-up otherwise).
    case "$(to_lower "$_mode")" in
        client|sta|mesh*|adhoc|ad-hoc)
            if [ "${_assoc:-0}" -gt 0 ] 2>/dev/null; then
                _clients="$_assoc"
            else
                _clients=$(iface_associated "$_if")
            fi
            ;;
        *)
            _clients=$("$WLCLIENTS" "$_if" 2>/dev/null </dev/null | awk 'NF{print $1; exit}')
            case "$_clients" in ''|*[!0-9]*) _clients="${_assoc:-0}" ;; esac
            ;;
    esac

    # 14 metric fields (record columns 4..17) + a trailing mode tag (field 18,
    # not an OID column) used only by build_snapshot to compute the AP-side
    # aggregate client count without re-running discovery.
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(sanitize_int "$_clients")" "$(sanitize_int "$_freq")" "$(sanitize_int "$_noise")" \
        "$(sanitize_int "$_tmin")" "$(sanitize_int "$_tavg")" "$(sanitize_int "$_tmax")" \
        "$(sanitize_int "$_rmin")" "$(sanitize_int "$_ravg")" "$(sanitize_int "$_rmax")" \
        "$(sanitize_int "$_smin")" "$(sanitize_int "$_savg")" "$(sanitize_int "$_smax")" \
        "$(sanitize_int "$_util")" "$(sanitize_int "$_txpower")" "$(to_lower "$_mode")"
}

collect_records() {
    if [ -n "${OPENWRT_WL_MOCK:-}" ]; then
        cat "$OPENWRT_WL_MOCK"
        return
    fi

    # Discovery + labelling is delegated to the validated wlInterfaces.sh,
    # which emits "<iface>,<iface> (<label>)" (or "<iface>,<iface>").
    # </dev/null so the helper can't read the pass_persist protocol pipe.
    "$WLIFACES" 2>/dev/null </dev/null | while IFS= read -r line; do
        iface=$(printf '%s' "$line" | cut -d',' -f1)
        [ -n "$iface" ] || continue

        ifindex=$(iface_ifindex "$iface")
        case "$ifindex" in
            ''|*[!0-9]*) continue ;;   # no usable ifIndex -> cannot index row
        esac

        # Label = text inside the trailing "(...)", else the interface name.
        label=$(printf '%s' "$line" | sed -n 's/.*(\(.*\))$/\1/p')
        [ -n "$label" ] || label="$iface"

        # iface_stats emits 14 metric fields (record cols 4..17) + a mode tag.
        printf '%s\t%s\t%s\t%s\n' "$ifindex" "$iface" "$label" "$(iface_stats "$iface")"
    done
}

# --------------------------------------------------------------------------
# Snapshot: emit all instance OIDs in lexicographic (numeric) order as
# "<oid>\t<type>\t<value>" lines. Order is produced directly (scalars, then
# column-major over the table) so no post-sort is required.
# --------------------------------------------------------------------------
build_snapshot() {
    records=$(collect_records)
    ifcount=$(printf '%s\n' "$records" | awk 'NF' | wc -l | awk '{print $1}')
    # AP-side aggregate client count, computed from the records we already
    # collected (no second discovery pass). Field 18 is the per-iface mode tag;
    # client/STA/mesh/adhoc uplinks are excluded. Mock records have no field 18,
    # so an empty mode counts as AP.
    clients=$(printf '%s\n' "$records" | awk -F '\t' '
        NF { m = tolower($18); if (m !~ /client|sta|mesh|adhoc|ad-hoc/) s += $4 }
        END { print s + 0 }')

    {
        printf '%s\t%s\t%s\n' "$IFCOUNT_OID" "gauge" "$(sanitize_int "$ifcount")"
        printf '%s\t%s\t%s\n' "$CLIENTS_OID" "gauge" "$(sanitize_int "$clients")"

        printf '%s\n' "$records" | awk 'NF' | sort -t"$TAB" -k1,1n | awk -F '\t' -v entry="$ENTRY" '
            { n++; idx[n]=$1; for (f=1; f<=17; f++) v[n,f]=$f }
            END {
                for (c = 2; c <= 17; c++) {
                    type = (c==2 || c==3) ? "string" : ((c==6 || (c>=13 && c<=15) || c==17) ? "integer" : "gauge")
                    for (i = 1; i <= n; i++) {
                        printf "%s.%d.%s\t%s\t%s\n", entry, c, idx[i], type, v[i,c]
                    }
                }
            }'
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
emit_none() { echo "NONE"; }

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
    --collect)     collect_records; exit 0 ;;       # debug: print interface records
    --stats)       iface_stats "$2"; exit 0 ;;      # debug: print one iface's metrics
    --snapshot)    build_snapshot; cat "$SNAP_FILE"; exit 0 ;;  # debug: full OID table
    -h|--help)
        echo "Usage: $0 [-g OID | -n OID | --collect | --stats IFACE | --snapshot]" >&2
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
