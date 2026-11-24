#!/usr/bin/env bash
# Run on a client. Every 3 s: the address the OS resolver (with its cache)
# returns for app.team1.test, and which edge actually answered.
# Used for Ext B (TTL) and Ext E (edge cutover). Ctrl+C to stop.
CA="$HOME/team1-rootCA.pem"
while true; do
  ip=$(dscacheutil -q host -a name app.team1.test | awk '/ip_address/{print $2; exit}')
  edge=$(curl -s -I --max-time 3 --cacert "$CA" https://app.team1.test/api/status \
         | tr -d '\r' | awk -F': ' 'tolower($1)=="x-edge"{print $2}')
  echo "$(date +%T)  resolver=${ip:--}  x-edge=${edge:-none}"
  sleep 3
done
