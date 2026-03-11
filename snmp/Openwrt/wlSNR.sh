#!/bin/sh

# wlSNR.sh
# Returns wlSNR, Signal-to-Noise ratio in dB
# Arguments:
#  $1: targeted interface
#  $2: desired result (sum, avg, min, max)

# Check number of arguments
if [ $# -ne 2 ]; then
	/bin/echo "Usage: wlSNR.sh interface result"
	/bin/echo "Incorrect script usage, exiting."
	exit 1
fi

# Calculate result. Sum just for debug, and return integer (safest / easiest)
snrlist=$(/usr/bin/iwinfo "$1" assoclist 2>/dev/null | /usr/bin/cut -s -d "/" -f 2 | /usr/bin/cut -s -d "(" -f 2 | /usr/bin/cut -s -d " " -f 2 | /usr/bin/cut -s -d ")" -f 1)

# Fallback for client-mode interfaces where assoclist is empty.
if [ -z "$snrlist" ]; then
  snrlist=$(/usr/bin/iwinfo "$1" info 2>/dev/null | awk '
    /Signal:[[:space:]]*-?[0-9]+[[:space:]]*dBm/ && /Noise:[[:space:]]*-?[0-9]+[[:space:]]*dBm/ {
      signal = ""
      noise = ""
      for (i = 1; i <= NF; i++) {
        if ($i == "Signal:") {
          signal = $(i+1)
        }
        if ($i == "Noise:") {
          noise = $(i+1)
        }
      }
      if (signal != "" && noise != "") {
        print signal - noise
      }
      exit
    }
  ')
fi

min_snr=$(/bin/echo "$snrlist" | awk 'NR==1{min=$1} $1<min{min=$1} END{printf "%d\n", (min=="" ? 0 : min)}')
avg_snr=$(/bin/echo "$snrlist" | awk '{sum+=$1; n++} END{printf "%d\n", (n>0 ? sum/n : 0)}')
max_snr=$(/bin/echo "$snrlist" | awk '$1>max{max=$1} END{printf "%d\n", (max=="" ? 0 : max)}')

case "$2" in
  min) echo "$min_snr" ;;
  avg) echo "$avg_snr" ;;
  max) echo "$max_snr" ;;
  *)   echo "0" ;;
esac

# Second line for nsExtendOutputFull compatibility
echo "# wlSNR $1 $2"
exit 0
