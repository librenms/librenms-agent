#!/bin/sh

BASE_OID=".1.3.6.1.4.1.2021.255"

# WL => ascii => 87 76
WLAP_OID="$BASE_OID.87.76.1"
WLCLIENT_OID="$BASE_OID.87.76.2"
WLFRQ_OID="$BASE_OID.87.76.3"
WLNOISE_OID="$BASE_OID.87.76.4"
WL_ENTRIES=""
WL_LASTREFRESH=0

get_wlinfo() {
  let refresh=$(date +%s)-$WL_LASTREFRESH
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

    WL_ENTRIES="$WL_ENTRIES
$WLAP_OID.$id|string|$ssid($channel)
$WLCLIENT_OID.$id|integer|$clients
$WLFRQ_OID.$id|integer|$frequency
$WLNOISE_OID.$id|integer|$noise"

    let id=$id+1
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
          echo $(echo "$entry" | cut -d'|' -f2)
          echo $(echo "$entry" | cut -d'|' -f3-)
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
        if [ "$oid" \> "$REQ" ]; then
          next_req=$oid
          break
        fi
      done
      if [ -n "$next_req" ]; then
        for entry in $WL_ENTRIES; do
          entry_oid=$(echo "$entry" | cut -d'|' -f1)
          if [ "$next_req" = "$entry_oid" ]; then
            echo "$entry_oid"
            echo $(echo "$entry" | cut -d'|' -f2)
            echo $(echo "$entry" | cut -d'|' -f3-)
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

