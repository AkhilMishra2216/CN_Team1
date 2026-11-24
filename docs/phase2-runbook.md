# Phase 2 runbook - Harden, Recover, Troubleshoot

Every command for Phase 2, in the order we run it. Phase 1 services must
already be up (backends on Mac 3 and Mac 4, nginx on Mac 2, dnsmasq on
Mac 1). Run order: **A -> C -> D -> E setup -> B + E -> F**.

| Mac | Owner | IP | Phase 2 role |
| --- | --- | --- | --- |
| Mac 1 | Harshita | 10.7.18.129 | Primary DNS, TTL / cutover client |
| Mac 2 | Yashi | 10.7.31.128 | Primary edge (nginx) |
| Mac 3 | Manan | 10.7.10.192 | Backend A, **backup DNS**, **standby edge** |
| Mac 4 | Akhil | 10.7.12.3 | Backend B, main test client |

On clients, `tcurl` = `curl --cacert ~/team1-rootCA.pem` (real certificate
validation, never `-k`). Screenshot names refer to the evidence folders.

## Ext A - Backup DNS resolver

**Mac 3** - install and run the backup (same records as Mac 1):

```bash
cp dns/backup-dnsmasq.conf /opt/homebrew/etc/dnsmasq.conf
sudo brew services stop dnsmasq 2>/dev/null          # nothing else may hold port 53
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /opt/homebrew/Cellar/dnsmasq/2.93/sbin/dnsmasq
sudo /opt/homebrew/sbin/dnsmasq -d -C /opt/homebrew/etc/dnsmasq.conf
```

`A1_backup_dns_running_mac3.png`

**Mac 1 and Mac 4** - list both resolvers, primary first:

```bash
sudo networksetup -setdnsservers Wi-Fi 10.7.18.129 10.7.10.192
networksetup -getdnsservers Wi-Fi
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

`A2_client_two_dns_servers_mac4.png`

**Mac 4** - `dig @10.7.10.192 app.team1.test` -> `10.7.31.128` (`A3_dig_backup_direct_mac4.png`)

**Mac 1** - stop the primary: `sudo brew services stop dnsmasq` (`A4_primary_dns_stopped_mac1.png`)

**Mac 4** - names still resolve, now from Mac 3:

```bash
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
dig app.team1.test          # SERVER: 10.7.10.192#53
tcurl https://app.team1.test/api/status
```

`A5_failover_dig_curl_mac4.png`, and on Mac 3 the query in the dnsmasq log: `A6_backup_dns_log_mac3.png`

**Mac 1** - restore: `sudo brew services start dnsmasq`

## Ext C - Service isolation (backend firewall)

**Mac 1** - before: `curl -sS --max-time 5 http://10.7.10.192:3001/api/status` returns JSON (`C1_direct_access_before_mac1.png`)

**Mac 3 and Mac 4** - keep a rollback copy, load the rules into their own anchor:

```bash
sudo cp /etc/pf.conf ~/pf.conf.backup
sudo pfctl -a com.apple/cnproject -f firewall/pf-backend.conf
sudo pfctl -E
sudo pfctl -a com.apple/cnproject -s rules
```

`C2_pf_rules_mac3.png`, `C2_pf_rules_mac4.png`

**Mac 1** - direct access refused, the edge still works:

```bash
curl -sS --max-time 5 http://10.7.10.192:3001/api/status   # Connection refused
curl -sS --max-time 5 http://10.7.12.3:3002/api/status     # Connection refused
tcurl https://app.team1.test/api/status                    # JSON
```

`C3_direct_blocked_edge_ok_mac1.png`

**Mac 2** - the edge is allowed: `curl -s http://10.7.10.192:3001/api/status` (`C4_edge_allowed_mac2.png`)

**Mac 3 and Mac 4** - rollback:

```bash
sudo pfctl -a com.apple/cnproject -F all
sudo pfctl -d
diff /etc/pf.conf ~/pf.conf.backup && echo "pf.conf unchanged"
```

`C5_rollback_mac3.png`, `C5_rollback_mac4.png`

## Ext D - High-availability failover

**Mac 4** - `./scripts/lb-loop.sh` (A and B alternate)

**Mac 3** - Ctrl+C in the Backend A terminal. Loop shows only B, no errors: `D1_only_b_serving_mac4.png`

**Mac 2** - `tail -n 5 /opt/homebrew/var/log/nginx/error.log` shows `connect() failed (61: Connection refused) while connecting to upstream`: `D2_nginx_error_log_mac2.png`

**Mac 3** - `./backend/run-backend-a.sh`. Within 10 s (`fail_timeout`) A is back: `D3_a_back_in_rotation_mac4.png`

Remaining single point of failure: the edge on Mac 2. Ext E shows a
DNS-based way around it.

## Ext E setup - standby edge on Mac 3

Certificate first: [`tls/standby-certificate.md`](../tls/standby-certificate.md). Then on **Mac 3**:

```bash
cp nginx/standby-edge.conf /opt/homebrew/etc/nginx/servers/team1-standby.conf
sudo nginx -t && sudo nginx
tcurl -sI --resolve app.team1.test:443:10.7.10.192 https://app.team1.test/api/status | grep -i x-edge
# x-edge: mac3-standby
```

`E1_standby_edge_ready.png`

## Ext B + E - TTL, record change, edge cutover

One record change shows both TTL caching (B) and the DNS-based cutover (E).

1. **Mac 1** - `dig app.team1.test | grep -A1 'ANSWER SECTION'` shows TTL 30 (`B1_ttl_30.png`).
2. **Mac 1** - new tab: `./scripts/watch-edge.sh` -> `resolver=10.7.31.128  x-edge=mac2-nginx`.
3. **Mac 1** - point the name at the standby edge:

   ```bash
   sed -i '' 's/^host-record=app.team1.test,.*/host-record=app.team1.test,10.7.10.192/' /opt/homebrew/etc/dnsmasq.conf
   grep host-record /opt/homebrew/etc/dnsmasq.conf
   sudo brew services restart dnsmasq
   ```

   `B2_record_changed_mac1.png`, `E2_dns_cutover_record.png`.
   **Mac 3** does the same on the backup (Ctrl+C, same `sed`, start again) so both resolvers agree.
4. **Mac 1** - the loop keeps showing `mac2-nginx` until the cached answer's 30 s run out, then switches to `mac3-standby` (`B3_cache_until_ttl.png`, `E3_cutover_with_ttl.png`). Meanwhile `dig +short app.team1.test` already returns `10.7.10.192`, while `dscacheutil -q host -a name app.team1.test` still returns the old address (`B4_dig_vs_os_cache.png`).
5. **Mac 4** - a fresh client goes straight to the standby:

   ```bash
   sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
   tcurl -sI https://app.team1.test/api/status | grep -i x-edge
   ```

   `E4_new_client_new_edge.png`
6. **Mac 1 and Mac 3** - put the record back to `10.7.31.128` (same `sed`, restart). **Mac 1** flushes at once and the loop switches back without waiting for the TTL (`B5_manual_flush.png`):

   ```bash
   sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
   ```

## Ext F - Faculty-injected fault

On the client (Mac 4), one layer at a time; the first step that fails names the broken layer:

```bash
dig app.team1.test                                    # DNS
ping -c 2 10.7.31.128                                 # IP
nc -vz app.team1.test 443                             # TCP
openssl s_client -connect app.team1.test:443 -servername app.team1.test \
  -CAfile ~/team1-rootCA.pem </dev/null 2>/dev/null | grep 'Verify return'   # TLS
tcurl -i https://app.team1.test/api/status            # HTTP / application
```

Screenshots `F1_dns_check.png` ... `F6_fixed.png` in `evidence/14_TROUBLESHOOTING`.

## After the demo

```bash
sudo networksetup -setdnsservers Wi-Fi empty      # Mac 1 and Mac 4
sudo nginx -s stop                                 # Mac 2 and Mac 3
sudo pfctl -a com.apple/cnproject -F all; sudo pfctl -d   # Mac 3 and Mac 4, if still loaded
```
