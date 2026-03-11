#!/bin/sh
set -eu

# wlInterfaces.sh - Emit OpenWrt wireless interfaces for LibreNMS.
# Output format: <interface>,<display-name>
#
# Display name behavior:
# - Prefer SSID (ex: bmg)
# - If multiple interfaces share SSID, append band suffix (ex: moodsy24, moodsy5, moodsy6)

tmp="/tmp/wlInterfaces.$$.tmp"
trap 'rm -f "$tmp"' EXIT

get_json_value() {
  key="$1"
  if command -v jsonfilter >/dev/null 2>&1; then
    jsonfilter -e "@.$key" 2>/dev/null || true
  else
    sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
  fi
}

get_ssid_from_hostapd() {
  iface="$1"
  hapd="hostapd.$iface"

  status_json=$(ubus call "$hapd" get_status 2>/dev/null || true)
  ssid=$(printf '%s' "$status_json" | get_json_value ssid)
  if [ -n "$ssid" ]; then
    printf '%s' "$ssid"
    return
  fi

  config_json=$(ubus call "$hapd" get_config 2>/dev/null || true)
  ssid=$(printf '%s' "$config_json" | get_json_value ssid)
  if [ -n "$ssid" ]; then
    printf '%s' "$ssid"
  fi
}

is_iface_active_hostapd() {
  iface="$1"
  hapd="hostapd.$iface"
  status_json=$(ubus call "$hapd" get_status 2>/dev/null || true)

  # Accept common active states across OpenWrt variants.
  up=$(printf '%s' "$status_json" | get_json_value up)
  state=$(printf '%s' "$status_json" | get_json_value state)
  status=$(printf '%s' "$status_json" | get_json_value status)

  case "$up" in
    1|true|TRUE|True) return 0 ;;
  esac
  case "$state" in
    ENABLED|enabled|RUNNING|running) return 0 ;;
  esac
  case "$status" in
    ENABLED|enabled|RUNNING|running) return 0 ;;
  esac

  return 1
}

get_ssid_from_iwinfo() {
  iface="$1"
  iwinfo "$iface" info 2>/dev/null | sed -n 's/.*ESSID:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

get_iwinfo_info() {
  iface="$1"
  iwinfo "$iface" info 2>/dev/null || true
}

get_mode_from_iwinfo() {
  printf '%s\n' "$1" | awk '/^[[:space:]]*Mode:[[:space:]]/ {print $2; exit}'
}

get_signal_from_iwinfo() {
  printf '%s\n' "$1" | sed -n 's/.*Signal:[[:space:]]*\([^ ]\+\)[[:space:]]*dBm.*/\1/p' | head -1
}

get_bitrate_from_iwinfo() {
  printf '%s\n' "$1" | sed -n 's/.*Bit Rate:[[:space:]]*\([^ ]\+\).*/\1/p' | head -1
}

get_access_point_from_iwinfo() {
  printf '%s\n' "$1" | sed -n 's/.*Access Point:[[:space:]]*\([^ ]\+\).*/\1/p' | head -1
}

should_include_iwinfo_iface() {
  iface="$1"
  info=$(get_iwinfo_info "$iface")
  [ -n "$info" ] || return 1

  ssid=$(printf '%s\n' "$info" | sed -n 's/.*ESSID:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
  case "$ssid" in
    ''|unknown) return 1 ;;
  esac

  # Skip synthetic VLAN helper interfaces.
  printf '%s\n' "$info" | grep -q '(VLAN)' && return 1

  mode=$(get_mode_from_iwinfo "$info")
  access_point=$(get_access_point_from_iwinfo "$info")

  case "$mode" in
    Client)
      case "$access_point" in
        ''|Not-Associated|00:00:00:00:00:00) return 1 ;;
      esac
      return 0
      ;;
    Master)
      # Master-mode AP: include if ESSID is valid (checked above).
      # Signal/bitrate at the AP interface level report 0/unknown when
      # no clients are associated, so they cannot be used as filters.
      return 0
      ;;
  esac

  return 1
}

is_clearly_inactive_master_iface() {
  iface="$1"
  info=$(get_iwinfo_info "$iface")
  [ -n "$info" ] || return 1

  mode=$(get_mode_from_iwinfo "$info")
  [ "$mode" = "Master" ] || return 1

  signal=$(get_signal_from_iwinfo "$info")
  bitrate=$(get_bitrate_from_iwinfo "$info")

  # Some idle/placeholder VAPs report Signal=0 and unknown bitrate.
  # Treat only this exact combination as inactive.
  [ "$signal" = "0" ] || return 1
  [ "$bitrate" = "unknown" ] || return 1
  return 0
}

is_hostapd_managed_iface() {
  iface="$1"
  ubus list "hostapd.$iface" >/dev/null 2>&1
}

# Enumerate wireless interface names using iw (nl80211) or sysfs.
# More reliable than parsing `iwinfo` without arguments.
enum_wireless_ifaces() {
  if command -v iw >/dev/null 2>&1; then
    iw dev 2>/dev/null | awk '/[[:space:]]Interface[[:space:]]/{print $2}'
    return
  fi
  for p in /sys/class/net/*/phy80211 /sys/class/net/*/wireless; do
    [ -d "$p" ] || continue
    basename "$(dirname "$p")"
  done | sort -u
}

get_freq_mhz_from_hostapd() {
  iface="$1"
  hapd="hostapd.$iface"
  status_json=$(ubus call "$hapd" get_status 2>/dev/null || true)
  printf '%s' "$status_json" | get_json_value freq
}

get_band_suffix() {
  iface="$1"
  freq_mhz_hint="${2:-}"

  # If we already have a hostapd freq (MHz), use it directly.
  if [ -n "$freq_mhz_hint" ]; then
    case "$freq_mhz_hint" in
      *[!0-9]*|'') ;;
      *)
        if [ "$freq_mhz_hint" -ge 5925 ]; then
          printf '6'
          return
        elif [ "$freq_mhz_hint" -ge 4900 ]; then
          printf '5'
          return
        elif [ "$freq_mhz_hint" -ge 2300 ]; then
          printf '24'
          return
        fi
        ;;
    esac
  fi

  info=$(iwinfo "$iface" info 2>/dev/null || true)

  # Prefer explicit frequency in GHz if present.
  freq=$(printf '%s\n' "$info" | sed -n 's/.*Frequency:[[:space:]]*\([0-9.]\+\).*/\1/p' | head -1)
  freq_mhz=''
  if [ -n "$freq" ]; then
    freq_mhz=$(printf '%s\n' "$freq" | awk '{printf "%d", ($1 * 1000)}')
  fi
  # Fall back to channel mapping if frequency wasn't parsed.
  channel=$(printf '%s\n' "$info" | sed -n 's/.*Channel:[[:space:]]*\([0-9]\+\).*/\1/p' | head -1)

  if [ -n "$freq_mhz" ]; then
    if [ "$freq_mhz" -ge 5925 ]; then
      printf '6'
      return
    elif [ "$freq_mhz" -ge 4900 ]; then
      printf '5'
      return
    elif [ "$freq_mhz" -ge 2300 ]; then
      printf '24'
      return
    fi
  fi

  case "$freq" in
    2.*) printf '24' ;;
    5.*) printf '5' ;;
    6.*) printf '6' ;;
    *)
      case "$channel" in
        '' ) printf '' ;;
        [1-9]|1[0-4]) printf '24' ;;
        3[0-9]|4[0-9]|5[0-9]|6[0-9]|7[0-9]|8[0-9]|9[0-9]|1[0-7][0-9]) printf '5' ;;
        2[0-9][0-9]|3[0-9][0-9]) printf '6' ;;
        *) printf '' ;;
      esac
      ;;
  esac
}

emit_iface_records() {
  if ubus list hostapd.* >/dev/null 2>&1; then
    ubus list hostapd.* 2>/dev/null | sed 's/^hostapd\.//' | while IFS= read -r iface; do
      [ -n "$iface" ] || continue
      is_iface_active_hostapd "$iface" || continue
      if command -v iwinfo >/dev/null 2>&1; then
        is_clearly_inactive_master_iface "$iface" && continue
      fi
      ssid=$(get_ssid_from_hostapd "$iface")
      if [ -z "$ssid" ] && command -v iwinfo >/dev/null 2>&1; then
        ssid=$(get_ssid_from_iwinfo "$iface")
      fi
      band=''
      if command -v iwinfo >/dev/null 2>&1; then
        freq_mhz=$(get_freq_mhz_from_hostapd "$iface")
        band=$(get_band_suffix "$iface" "$freq_mhz")
      fi
      [ -n "$ssid" ] || ssid="$iface"
      printf '%s\t%s\t%s\n' "$iface" "$ssid" "$band"
    done
  fi

  if command -v iwinfo >/dev/null 2>&1; then
    enum_wireless_ifaces | while IFS= read -r iface; do
      [ -n "$iface" ] || continue
      is_hostapd_managed_iface "$iface" && continue
      should_include_iwinfo_iface "$iface" || continue
      ssid=$(get_ssid_from_iwinfo "$iface")
      [ -n "$ssid" ] || ssid="$iface"
      band=$(get_band_suffix "$iface")
      printf '%s\t%s\t%s\n' "$iface" "$ssid" "$band"
    done
  fi
}

emit_iface_records > "$tmp"

awk -F '\t' '
  {
    iface=$1
    if (!(iface in seen)) {
      seen[iface]=1
      rows[++row_count]=$0
      ssid=$2
      if (ssid != "") count[ssid]++
    }
  }
  END {
    for (i=1; i<=row_count; i++) {
      split(rows[i], f, "\t")
      iface=f[1]; ssid=f[2]; band=f[3]
      label=ssid
      if (count[ssid] > 1 && band != "" && ssid != iface) {
        label=ssid band
      }
      if (label == "" || label == iface) {
        printf "%s,%s\n", iface, iface
      } else {
        printf "%s,%s (%s)\n", iface, iface, label
      }
    }
  }
' "$tmp"

exit 0
