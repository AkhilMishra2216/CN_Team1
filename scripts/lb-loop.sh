#!/usr/bin/env bash
# Run on a client. One request per second; prints which backend and edge answered.
# Used for Ext D (stop Backend A, watch only B answer, start A again). Ctrl+C to stop.
CA="$HOME/team1-rootCA.pem"
while true; do
  h=$(curl -s -i --max-time 3 --cacert "$CA" https://app.team1.test/api/status | tr -d '\r')
  code=$(echo "$h" | awk 'NR==1{print $2}')
  be=$(echo "$h" | awk -F': ' 'tolower($1)=="x-backend"{print $2}')
  echo "$(date +%T)  HTTP ${code:-fail}  x-backend=${be:--}"
  sleep 1
done
