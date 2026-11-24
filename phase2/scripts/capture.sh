#!/usr/bin/env bash
# Runs one Phase 2 test step and saves exactly what the terminal printed,
# with the Mac, its IP and timestamps, to ~/cn/evidence/<step>-<mac>.txt.
# Usage (from the repo root):  ./phase2/scripts/capture.sh <step> [args]
# Steps are listed with:       ./phase2/scripts/capture.sh help
set -u

PRIMARY=10.7.18.129; BACKUP=10.7.10.192; EDGE=10.7.31.128; STANDBY=10.7.10.192
NAME=app.team1.test
CA="${CA:-$HOME/cn/rootCA.pem}"; [ -f "$CA" ] || CA="$HOME/team1-rootCA.pem"
CONF=/opt/homebrew/etc/dnsmasq.conf
IF=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
MYIP=$(ipconfig getifaddr "${IF:-en0}")
case "$MYIP" in
  "$PRIMARY") MAC=mac1 ;; "$EDGE") MAC=mac2 ;; "$BACKUP") MAC=mac3 ;; *) MAC=mac4 ;;
esac
STEP="${1:-help}"; shift || true
OUTDIR="${OUTDIR:-$HOME/cn/evidence}"; mkdir -p "$OUTDIR"
OUT="$OUTDIR/$STEP-$MAC.txt"

run() {                       # print the command like a prompt, then its real output
  echo "[$(date +%T)] $USER@$(scutil --get LocalHostName) % $*"
  eval "$@" 2>&1
  echo
}
flush() { run "sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"; }
edge_header() { curl -s -I --max-time 3 --cacert "$CA" "https://$NAME/api/status" | tr -d '\r' | awk -F': ' 'tolower($1)=="x-edge"{print $2}'; }
os_ip() { dscacheutil -q host -a name "$NAME" | awk '/ip_address/{print $2; exit}'; }

body() {
  case "$STEP" in
  a-client)        # Ext A, any client: resolver order and who answers now
    run "networksetup -getdnsservers Wi-Fi"
    run "dig $NAME +noall +answer +stats | grep -E 'IN|SERVER|Query time'" ;;
  a-primary-stop)  # Ext A, Mac 1
    run "sudo brew services stop dnsmasq"
    run "dig @$PRIMARY $NAME +time=2 +tries=1 | tail -3" ;;
  a-failover)      # Ext A, Mac 4 while the primary is stopped
    flush
    run "dig $NAME +noall +answer +stats | grep -E 'IN|SERVER|Query time'"
    run "curl -sS --max-time 8 --cacert $CA https://$NAME/api/status" ;;
  a-primary-start) # Ext A, Mac 1
    run "sudo brew services start dnsmasq"
    run "dig @$PRIMARY $NAME +short" ;;
  d-loop)          # Ext D, client: N requests, one per second (default 15)
    for i in $(seq 1 "${1:-15}"); do
      r=$(curl -sS -i --max-time 3 --cacert "$CA" "https://$NAME/api/status" 2>&1 | tr -d '\r' | grep -iE '^HTTP|^x-backend|^curl:' | tr '\n' ' ')
      echo "[$(date +%T)] ${r:-request failed}"
      sleep 1
    done ;;
  e-standby-check) # Ext E, any Mac: standby answers directly
    run "curl -sI --cacert $CA --resolve $NAME:443:$STANDBY https://$NAME/api/status | grep -iE '^HTTP|x-edge|x-backend'" ;;
  dns-set)         # Ext B/E, Mac 1 (primary, Homebrew service): dns-set <ip>
    run "sed -i '' 's/^host-record=$NAME,.*/host-record=$NAME,${1:?ip}/' $CONF"
    run "grep host-record $CONF"
    run "sudo brew services restart dnsmasq"
    run "sleep 2; dig @$PRIMARY $NAME +short" ;;
  b-watch)         # Ext B/E, client: start BEFORE dns-set; N rounds every 3 s (default 20)
    run "dig $NAME +noall +answer | grep IN"
    for i in $(seq 1 "${1:-20}"); do
      echo "[$(date +%T)] os-cache=$(os_ip)  dig=$(dig +short $NAME | head -1)  x-edge=$(e=$(edge_header); echo "${e:-none}")"
      sleep 3
    done ;;
  b-flush)         # Ext B, client: right after the record is changed back
    run "dscacheutil -q host -a name $NAME | grep ip_address"
    flush
    run "dscacheutil -q host -a name $NAME | grep ip_address"
    echo "[$(date +%T)] x-edge=$(e=$(edge_header); echo "${e:-none}")" ;;
  e-fresh)         # Ext E, a second client after the cutover
    flush
    run "curl -sI --cacert $CA https://$NAME/api/status | grep -iE '^HTTP|x-edge|x-backend'" ;;
  *)
    sed -n '2,5p' "$0"
    echo "Steps: a-client a-primary-stop a-failover a-primary-start d-loop [n]"
    echo "       e-standby-check dns-set <ip> b-watch [n] b-flush e-fresh"
    exit 0 ;;
  esac
}

{
  echo "== Phase 2 step: $STEP   Mac: $MAC ($MYIP)   $(date '+%a %d %b %Y %H:%M:%S %Z')"
  echo
  body "$@"
} | tee "$OUT"
echo "Saved: $OUT"
