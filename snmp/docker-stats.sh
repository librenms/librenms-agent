#!/usr/bin/env bash

VERSION=1

function dockerStatsFormat() {
  cat <<EOF
{
  "container": "{{.Name}}",
  "pids": {{.PIDs}},
  "memory": {
    "used": "{{ index (split .MemUsage " / ") 0 }}",
    "limit": "{{ index (split .MemUsage " / ") 1 }}",
    "perc": "{{.MemPerc}}"
  },
  "cpu": "{{.CPUPerc}}"
}
EOF
}

function getStats() {
  docker stats \
    --no-stream \
    --format "$(dockerStatsFormat)"
}
STATS=$(getStats 2>&1)
ERROR=$?
if [ $ERROR -ne 0 ];then
  ERROR_STRING=${STATS}
  unset STATS
fi
jq -nMc \
  --slurpfile stats <(echo "${STATS:-}") \
  --arg version "${VERSION:-1}" \
  --arg error "${ERROR:-0}" \
  --arg errorString "${ERROR_STRING:-}" \
  '{"version": $version, "data": $stats, "error": $error, "errorString": $errorString }'

# vim: tabstop=2:shiftwidth=2:expandtab:
