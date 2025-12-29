#!/bin/sh

BASE_OID=".1.3.6.1.4.1.2021.255"

# WL => ascii => 87 76
WLAP_OID="$BASE_OID.87.76.1"
WLCLIENT_OID="$BASE_OID.87.76.2"
WLFRQ_OID="$BASE_OID.87.76.3"
WLNOISE_OID="$BASE_OID.87.76.4"
WLRATE_OID="$BASE_OID.87.76.5"
WLRATE_TX_SUM_OID="$WLRATE_OID.1.1"
WLRATE_TX_AVG_OID="$WLRATE_OID.1.2"
WLRATE_TX_MIN_OID="$WLRATE_OID.1.3"
WLRATE_TX_MAX_OID="$WLRATE_OID.1.4"
WLRATE_RX_SUM_OID="$WLRATE_OID.2.1"
WLRATE_RX_AVG_OID="$WLRATE_OID.2.2"
WLRATE_RX_MIN_OID="$WLRATE_OID.2.3"
WLRATE_RX_MAX_OID="$WLRATE_OID.2.3"
WLSNR_OID="$BASE_OID.87.76.6"
WLSNR_OID_SUM="$WLSNR_OID.1"
WLSNR_OID_AVG="$WLSNR_OID.2"
WLSNR_OID_MIN="$WLSNR_OID.3"
WLSNR_OID_MAX="$WLSNR_OID.4"
WL_ENTRIES=""
WL_LASTREFRESH=0

get_wlinfo() {
  refresh=$(($(date +%s)-$WL_LASTREFRESH))
  if [ $refresh -lt 30 ]; then
    return
  fi

  WL_LASTREFRESH=$(date +%s)

  interfaces=$(iwinfo | grep ESSID | cut -s -d " " -f 1)
  id=1
  for interface in $interfaces; do
    ssid=$(iwinfo $interface info | grep ESSID | cut -s -d ":" -f 2 | sed 's/ //g' | sed 's/"//g')
    channel=$(iwinfo $interface info | grep Mode | grep Channel | cut -s -d"(" -f 2 | cut -s -d")" -f 1 | sed 's/ //g')
    clients=$(/usr/sbin/iw dev $interface station dump 2>/dev/null | grep Station | cut -f 2 -s -d" " | wc -l)
    frequency=$(/usr/sbin/iw dev $interface info 2>/dev/null | grep channel | cut -f 2- -s -d" " | cut -f 2- -s -d"(" | cut -f 1 -s -d" ")
    noise=$(iwinfo $interface assoclist 2>/dev/null | grep -v "^$" | cut -s -d "/" -f 2 | cut -s -d "(" -f 1 | cut -s -d " " -f 2 | tail -1)

    for dir in "tx" "rx"; do
      ratelist=$(/usr/sbin/iw dev $interface station dump 2>/dev/null | grep "$dir bitrate" | cut -f 2 -s -d" ")
      eval rate_${dir}_sum="$(echo "${ratelist}" | awk -F ':' '{sum += $dir} END {printf "%d\n", 1000000*sum}')"
      eval rate_${dir}_avg="$(echo "${ratelist}" | awk -F ':' '{sum += $dir} END {printf "%d\n", 1000000*sum/NR}')"
      eval rate_${dir}_min="$(echo "${ratelist}" | awk -F ':' 'NR == 1 || $dir < min {min = $dir} END {printf "%d\n", 1000000*min}')"
      eval rate_${dir}_max="$(echo "${ratelist}" | awk -F ':' 'NR == 1 || $dir > max {max = $dir} END {printf "%d\n", 1000000*max}')"
    done

    snrlist=$(iwinfo $interface assoclist 2>/dev/null | cut -s -d "/" -f 2 | cut -s -d "(" -f 2 | cut -s -d " " -f 2 | cut -s -d ")" -f 1)
    snr_sum=$(echo $snrlist | awk -F ':' '{sum += $interface} END {printf "%d\n", sum}')
    snr_avg=$(echo $snrlist | awk -F ':' '{sum += $interface} END {printf "%d\n", sum/NR}')
    snr_min=$(echo $snrlist | awk -F ':' 'NR == 1 || $interface < min {min = $interface} END {printf "%d\n", min}')
    snr_max=$(echo $snrlist | awk -F ':' 'NR == 1 || $interface > max {max = $interface} END {printf "%d\n", max}')

    WL_ENTRIES="$WL_ENTRIES
$WLAP_OID.$id|string|$ssid($channel)
$WLCLIENT_OID.$id|integer|$clients
$WLFRQ_OID.$id|integer|$frequency
$WLNOISE_OID.$id|integer|$noise
$WLRATE_TX_SUM_OID.$id|integer|${rate_tx_sum:-}
$WLRATE_RX_SUM_OID.$id|integer|${rate_rx_sum:-}
$WLRATE_TX_AVG_OID.$id|integer|${rate_tx_avg:-}
$WLRATE_RX_AVG_OID.$id|integer|${rate_rx_avg:-}
$WLRATE_TX_MIN_OID.$id|integer|${rate_tx_min:-}
$WLRATE_RX_MIN_OID.$id|integer|${rate_rx_min:-}
$WLRATE_TX_MAX_OID.$id|integer|${rate_tx_max:-}
$WLRATE_RX_MAX_OID.$id|integer|${rate_rx_max:-}
$WLSNR_OID_SUM.$id|integer|$snr_sum
$WLSNR_OID_AVG.$id|integer|$snr_avg
$WLSNR_OID_MIN.$id|integer|$snr_min
$WLSNR_OID_MAX.$id|integer|$snr_max"

    id=$(($id+1))
  done
}

while read CMD; do
  case "$CMD" in		
    PING)
      echo PONG
      ;;
    get)
      read REQ
      found=0
      get_wlinfo
      for entry in $WL_ENTRIES; do
        entry_oid=$(echo "$entry" | cut -d'|' -f1)
        if [ "$REQ" = "$entry_oid" ]; then
          echo "$entry_oid"
          echo "$entry" | cut -d'|' -f2
          echo "$entry" | cut -d'|' -f3-
          found=1
          break
        fi
      done
      [ "$found" = "0" ] && echo "NONE"
      ;;
    getnext)
      read REQ
      get_wlinfo
      oids=$(printf '%s\n', "$WL_ENTRIES" | cut -d'|' -f1 | sort)
      next_req=""
      for oid in $oids; do
        if expr "$oid" \> "$REQ" > /dev/null; then
          next_req=$oid
          break
        fi
      done
      if [ -n "$next_req" ]; then
        for entry in $WL_ENTRIES; do
          entry_oid=$(echo "$entry" | cut -d'|' -f1)
          if [ "$next_req" = "$entry_oid" ]; then
            echo "$entry_oid"
            echo "$entry" | cut -d'|' -f2
            echo "$entry" | cut -d'|' -f3-
            break
          fi
        done
      else
        echo "NONE"
      fi
      ;;
    *)
      echo "NONE"
      ;;
  esac
done

