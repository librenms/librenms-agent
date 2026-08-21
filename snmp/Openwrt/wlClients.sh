#!/bin/sh
set -e

# wlClients.sh - OpenWrt wireless client count via ubus or fallback
# Usage: wlClients.sh [interface]  # outputs integer count, always exit 0 for SNMP

scriptdir="$(cd "$(dirname "$0")" && pwd)"
interfaces_script="$scriptdir/wlInterfaces.sh"

normalize_iface() {
  # Keep only expected interface characters and strip CR/LF noise.
  printf '%s' "$1" | tr -d '\r\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed 's/[^A-Za-z0-9._:-]//g'
}

count_iface_clients() {
  iface="$1"
  new=0

  if ubus call "hostapd.$iface" get_clients >/dev/null 2>&1; then
    new=$(list_assoc_macs_ubus "$iface" | awk 'NF' | sort -u | wc -l | awk '{print $1}')
  else
    # Fallback: iwinfo for generic OpenWrt
    new=$(list_assoc_macs_iwinfo "$iface" | awk 'NF' | sort -u | wc -l | awk '{print $1}')
  fi

  # Normalize to a single integer token to avoid arithmetic parse errors.
  new=$(printf '%s\n' "$new" | awk 'NF {print $1; exit}')
  case "$new" in
    ''|*[!0-9]*) new=0 ;;
  esac

  printf '%s\n' "$new"
}

list_assoc_macs_ubus() {
  iface="$1"
  ubus call "hostapd.$iface" get_clients 2>/dev/null | awk '
    BEGIN { IGNORECASE=1; mac=""; mld="" }
    /^[[:space:]]*"([0-9a-f]{2}:){5}[0-9a-f]{2}"[[:space:]]*:[[:space:]]*\{/ {
      if (mac != "") {
        if (mld != "" && mld != "00:00:00:00:00:00") {
          print mld
        } else {
          print mac
        }
      }
      if (match($0, /"([0-9a-f]{2}:){5}[0-9a-f]{2}"/)) {
        mac=tolower(substr($0, RSTART+1, RLENGTH-2))
        mld=""
      }
    }
    /"mld_addr"[[:space:]]*:[[:space:]]*"([0-9a-f]{2}:){5}[0-9a-f]{2}"/ {
      if (match($0, /"([0-9a-f]{2}:){5}[0-9a-f]{2}"[[:space:]]*$/)) {
        val=tolower(substr($0, RSTART+1, RLENGTH-2))
        if (val != "00:00:00:00:00:00") {
          mld=val
        }
      } else if (match($0, /"([0-9a-f]{2}:){5}[0-9a-f]{2}"/)) {
        val=tolower(substr($0, RSTART+1, RLENGTH-2))
        if (val != "00:00:00:00:00:00") {
          mld=val
        }
      }
    }
    END {
      if (mac != "") {
        if (mld != "" && mld != "00:00:00:00:00:00") {
          print mld
        } else {
          print mac
        }
      }
    }
  '
}

list_assoc_macs_iwinfo() {
  iface="$1"
  iwinfo "$iface" assoclist 2>/dev/null | awk '
    BEGIN { IGNORECASE=1 }
    /^[[:space:]]*([0-9a-f]{2}:){5}[0-9a-f]{2}[[:space:]]/ {
      print tolower($1)
    }
  '
}

count_aggregate_unique_clients() {
  interfaces="$1"

  if [ -z "$interfaces" ]; then
    echo 0
    return
  fi

  tmp="/tmp/wlClients.macs.$$"
  trap 'rm -f "$tmp"' EXIT
  : > "$tmp"

  for iface in $interfaces; do
    iface=$(normalize_iface "$iface")
    [ -n "$iface" ] || continue

    if ubus call "hostapd.$iface" get_clients >/dev/null 2>&1; then
      list_assoc_macs_ubus "$iface" >> "$tmp" || true
    else
      list_assoc_macs_iwinfo "$iface" >> "$tmp" || true
    fi
  done

  awk 'NF' "$tmp" | sort -u | wc -l | awk '{print $1}'
}

get_live_interfaces() {
  # Reuse wlInterfaces.sh so we only count interfaces currently exported to LibreNMS.
  if [ -x "$interfaces_script" ]; then
    "$interfaces_script" 2>/dev/null | while IFS= read -r line; do
      iface=$(printf '%s' "$line" | cut -d',' -f1)
      iface=$(normalize_iface "$iface")
      [ -n "$iface" ] && printf '%s\n' "$iface"
    done | awk '!seen[$0]++'
  fi
}

# Args: single iface or all
if [ "${1:-}" ]; then
  interfaces="$(normalize_iface "$1")"
else
  interfaces=$(get_live_interfaces)
fi

count=0

if [ "${1:-}" ]; then
  # Per-interface mode (used by clients-<iface>)
  for iface in $interfaces; do
    iface=$(normalize_iface "$iface")
    [ -n "$iface" ] || continue
    new=$(count_iface_clients "$iface")
    count=$((count + new))
  done
else
  # Aggregate mode (clients-wlan): dedupe MACs to avoid MLO/MLD double-counting.
  count=$(count_aggregate_unique_clients "$interfaces")
fi

# Output count first line for nsExtendOutput1Line queries.
echo "$count"
echo "# wlClients for $interfaces"
exit 0
