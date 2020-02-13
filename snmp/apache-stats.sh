#!/usr/bin/env sh

# This script produces LibreNMS apache-stats output.  The only dependency is curl.

# 20200102, joseph.tingiris@gmail.com

PATH=/sbin:/bin:/usr/sbin:/usr/bin

#
# Functions
#

function debugecho() {
    if [ ${#Debug} -gt 0 ]; then
        echo debug: $@
    fi
}

#
# Globals
#

Tmp_File=/tmp/apache_status

# Debug=on; use environment, i.e. Debug=on apache-stats.sh
if [ "${DEBUG}" != "" ]; then
    Debug=${DEBUG}
else
    if [ "${Debug}" != "" ]; then
        Debug=${Debug}
    fi
fi

# set default values to U; not all apache's have all stats
Total_Accesses="U"
Total_kBytes="U"
CPULoad="U"
Uptime="U"
ReqPerSec="U"
BytesPerSec="U"
BytesPerReq="U"
BusyWorkers="U"
IdleWorkers="U"
Scoreboard="U"

# set default scoreboard counters to 0
let Scoreboard_=0
let ScoreboardDot=0
let ScoreboardC=0
let ScoreboardD=0
let ScoreboardG=0
let ScoreboardI=0
let ScoreboardK=0
let ScoreboardL=0
let ScoreboardR=0
let ScoreboardS=0
let ScoreboardW=0

#
# Main
#

curl --silent --fail "http://localhost/server-status?auto" -o ${Tmp_File} &> /dev/null
if [ $? -ne 0 ]; then
    # curl failed
    exit 1
fi

if [ ! -s ${Tmp_File} ]; then
    # empty output
    exit 1
fi

while read Line; do
    Field=${Line%:*}
    Value=${Line#*: }

    debugecho "Line: ${Line}"
    debugecho "Field: ${Field}"
    debugecho "Value: ${Value}"
    debugecho

    if [ "${Field}" == "Total Accesses" ]; then
        Total_Accesses=${Value}
    fi

    if [ "${Field}" == "Total kBytes" ]; then
        Total_kBytes=${Value}
    fi

    if [ "${Field}" == "CPULoad" ]; then
        CPULoad=${Value}
    fi

    if [ "${Field}" == "Uptime" ]; then
        Uptime=${Value}
    fi

    if [ "${Field}" == "ReqPerSec" ]; then
        ReqPerSec=${Value}
    fi

    if [ "${Field}" == "BytesPerSec" ]; then
        BytesPerSec=${Value}
    fi

    if [ "${Field}" == "BytesPerReq" ]; then
        BytesPerReq=${Value}
    fi

    if [ "${Field}" == "BusyWorkers" ]; then
        BusyWorkers=${Value}
    fi

    if [ "${Field}" == "IdleWorkers" ]; then
        IdleWorkers=${Value}
    fi

    if [ "${Field}" == "Scoreboard" ]; then
        Scoreboard=${Value}
    fi

done < ${Tmp_File}

# value output order must be this ...
echo "${Total_Accesses}"
echo "${Total_kBytes}"
echo "${CPULoad}"
echo "${Uptime}"
echo "${ReqPerSec}"
echo "${BytesPerSec}"
echo "${BytesPerReq}"
echo "${BusyWorkers}"
echo "${IdleWorkers}"

debugecho "Scoreboard = ${Scoreboard}"
for (( c=0; c<${#Scoreboard}; c++ )); do

  if [ "${Scoreboard:$c:1}" == "_" ]; then
      let Scoreboard_=${Scoreboard_}+1
      continue
  fi

  if [ "${Scoreboard:$c:1}" == "." ]; then
      let ScoreboardDot=${ScoreboardDot}+1
      continue
  fi

  if [ "${Scoreboard:$c:1}" == "C" ]; then
      let ScoreboardC=${ScoreboardC}+1
      continue
  fi

  if [ "${Scoreboard:$c:1}" == "D" ]; then
      let ScoreboardD=${ScoreboardD}+1
      continue
  fi

  if [ "${Scoreboard:$c:1}" == "G" ]; then
      let ScoreboardG=${ScoreboardG}+1
      continue
  fi

  if [ "${Scoreboard:$c:1}" == "I" ]; then
      let ScoreboardI=${ScoreboardI}+1
      continue
  fi

  if [ "${Scoreboard:$c:1}" == "K" ]; then
      let ScoreboardK=${ScoreboardK}+1
      continue
  fi

  if [ "${Scoreboard:$c:1}" == "L" ]; then
      let ScoreboardL=${ScoreboardL}+1
      continue
  fi

  if [ "${Scoreboard:$c:1}" == "R" ]; then
      let ScoreboardR=${ScoreboardR}+1
      continue
  fi

  if [ "${Scoreboard:$c:1}" == "S" ]; then
      let ScoreboardS=${ScoreboardS}+1
      continue
  fi

  if [ "${Scoreboard:$c:1}" == "W" ]; then
      let ScoreboardW=${ScoreboardW}+1
      continue
  fi

  debugecho "${Scoreboard:$c:1}"
done

# scoreboard output order must be this ...
echo ${Scoreboard_}
echo ${ScoreboardS}
echo ${ScoreboardR}
echo ${ScoreboardW}
echo ${ScoreboardK}
echo ${ScoreboardD}
echo ${ScoreboardC}
echo ${ScoreboardL}
echo ${ScoreboardG}
echo ${ScoreboardI}
echo ${ScoreboardDot}

# clean up
if [ -f ${Tmp_File} ]; then
    rm -f ${Tmp_File} &> /dev/null
fi
