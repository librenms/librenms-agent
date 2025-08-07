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
WL_ENTRIES=""
WL_LASTREFRESH=0

get_wlinfo() {
  refresh=$(($(date +%s)-$WL_LASTREFRESH))
  if [ $refresh -lt 30 ]; then
    return
  fi

  WL_LASTREFRESH=$(date +%s)

  interfaces=$(/usr/bin/iwinfo | /bin/grep ESSID | /usr/bin/cut -s -d " " -f 1)
  id=1
  for interface in $interfaces; do
    ssid=$(/usr/bin/iwinfo $interface info | /bin/grep ESSID | /usr/bin/cut -s -d ":" -f 2 | /bin/sed 's/ //g' | /bin/sed 's/"//g')
    channel=$(/usr/bin/iwinfo $interface info | /bin/grep Mode | /bin/grep Channel | /usr/bin/cut -s -d"(" -f 2 | /usr/bin/cut -s -d")" -f 1 | /bin/sed 's/ //g')
    clients=$(/usr/sbin/iw dev "$interface" station dump 2>/dev/null | /bin/grep Station | /usr/bin/cut -f 2 -s -d" " | /usr/bin/wc -l)
    frequency=$(/usr/sbin/iw dev "$interface" info 2>/dev/null | /bin/grep channel | /usr/bin/cut -f 2- -s -d" " | /usr/bin/cut -f 2- -s -d"(" | /usr/bin/cut -f 1 -s -d" ")
    noise=$(/usr/bin/iwinfo "$interface" assoclist 2>/dev/null | grep -v "^$" | /usr/bin/cut -s -d "/" -f 2 | /usr/bin/cut -s -d "(" -f 1 | /usr/bin/cut -s -d " " -f 2 | /usr/bin/tail -1)

    for dir in "tx" "rx"; do
      ratelist=$(/usr/sbin/iw dev "$interface" station dump 2>/dev/null | /bin/grep "$dir bitrate" | /usr/bin/cut -f 2 -s -d" ")
      eval rate_${dir}_sum=$(/bin/echo "$ratelist" | /usr/bin/awk -F ':' '{sum += $dir} END {printf "%d\n", 1000000*sum}')
      eval rate_${dir}_avg=$(/bin/echo "$ratelist" | /usr/bin/awk -F ':' '{sum += $dir} END {printf "%d\n", 1000000*sum/NR}')
      eval rate_${dir}_min=$(/bin/echo "$ratelist" | /usr/bin/awk -F ':' 'NR == 1 || $dir < min {min = $dir} END {printf "%d\n", 1000000*min}')
      eval rate_${dir}_max=$(/bin/echo "$ratelist" | /usr/bin/awk -F ':' 'NR == 1 || $dir > max {max = $dir} END {printf "%d\n", 1000000*max}')
    done

    WL_ENTRIES="$WL_ENTRIES
$WLAP_OID.$id|string|$ssid($channel)
$WLCLIENT_OID.$id|integer|$clients
$WLFRQ_OID.$id|integer|$frequency
$WLNOISE_OID.$id|integer|$noise
$WLRATE_TX_SUM_OID.$id|integer|$rate_tx_sum
$WLRATE_RX_SUM_OID.$id|integer|$rate_rx_sum
$WLRATE_TX_AVG_OID.$id|integer|$rate_tx_avg
$WLRATE_RX_AVG_OID.$id|integer|$rate_rx_avg
$WLRATE_TX_MIN_OID.$id|integer|$rate_tx_min
$WLRATE_RX_MIN_OID.$id|integer|$rate_rx_min
$WLRATE_TX_MAX_OID.$id|integer|$rate_tx_max
$WLRATE_RX_MAX_OID.$id|integer|$rate_rx_max"

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

