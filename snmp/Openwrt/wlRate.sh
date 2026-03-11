#!/bin/sh

# wlRate.sh
# Returns wlRate, bit rate in Mbit/s
# Arguments:
#  $1: targeted interface
#  $2: direction (tx or rx)
#  $3: desired result (sum, avg, min, max)

# Check number of arguments
if [ $# -ne 3 ]; then
	/bin/echo "Usage: wlRate.sh interface direction result"
	/bin/echo "Incorrect script usage, exiting."
	exit 1
fi

iface="$1"
dir="$2"

IW_BIN=$(command -v iw 2>/dev/null || true)
IWINFO_BIN=$(command -v iwinfo 2>/dev/null || true)

# Extract numeric bitrate values from "tx bitrate:" / "rx bitrate:" lines.
# Example input line:
#   tx bitrate:     1201.0 MBit/s HE-MCS 11 HE-NSS 2 HE-GI 0 HE-DCM 0
ratelist=""
if [ -n "$IW_BIN" ]; then
  ratelist=$($IW_BIN dev "$iface" station dump 2>/dev/null | awk -v d="$dir" '
    {
      key1 = tolower($1)
      key2 = tolower($2)
      if (key1 == d && key2 == "bitrate:") {
        for (i = 3; i <= NF; i++) {
          if ($i ~ /^[0-9]+(\.[0-9]+)?$/) {
            print $i
            break
          }
        }
      }
    }
  ')
fi

# Fallback for devices where iw station dump is unavailable or differently formatted.
if [ -z "$ratelist" ] && [ -n "$IWINFO_BIN" ]; then
  if [ "$dir" = "tx" ]; then
    ratelist=$($IWINFO_BIN "$iface" assoclist 2>/dev/null | awk '
      /TX:[[:space:]]*[0-9]+(\.[0-9]+)?[[:space:]]*MBit\/s/ {
        if (match($0, /TX:[[:space:]]*([0-9]+(\.[0-9]+)?)[[:space:]]*MBit\/s/, m)) {
          print m[1]
        }
      }
    ')
  else
    ratelist=$($IWINFO_BIN "$iface" assoclist 2>/dev/null | awk '
      /RX:[[:space:]]*[0-9]+(\.[0-9]+)?[[:space:]]*MBit\/s/ {
        if (match($0, /RX:[[:space:]]*([0-9]+(\.[0-9]+)?)[[:space:]]*MBit\/s/, m)) {
          print m[1]
        }
      }
    ')
  fi
fi

# Calculate min/avg/max rates
min_rate=$(/bin/echo "$ratelist" | awk 'NR==1{min=$1} $1<min{min=$1} END{printf "%d\n", (min=="" ? 0 : min)}')
avg_rate=$(/bin/echo "$ratelist" | awk '{sum+=$1; n++} END{printf "%d\n", (n>0 ? sum/n : 0)}')
max_rate=$(/bin/echo "$ratelist" | awk '$1>max{max=$1} END{printf "%d\n", (max=="" ? 0 : max)}')

case "$3" in
  min) echo "$min_rate" ;;
  avg) echo "$avg_rate" ;;
  max) echo "$max_rate" ;;
  *)   echo "0" ;;
esac

# Second line for nsExtendOutputFull compatibility
echo "# wlRate $1 $2 $3"
exit 0
