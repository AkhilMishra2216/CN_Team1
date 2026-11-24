# Phase 2 · Harden, Recover, and Troubleshoot

Phase 2 extends the Phase 1 network; nothing is rebuilt. Phase 1 services
must be running first (backends on Mac 3 and Mac 4, nginx on Mac 2,
dnsmasq on Mac 1). Run order: **A → C → D → E setup → B + E → F**.

- [Phase 2 report (IEEE format, PDF)](report/phase2-report.pdf) · [summary](REPORT.md)
- [Evidence checklist](../evidence/README.md)
- [Phase 2 architecture](../docs/phase2-architecture.md)
- [IP inventory](../docs/IP-inventory.md)

| Mac | Owner | IP | Phase 2 role |
| --- | --- | --- | --- |
| Mac 1 | Harshita | 10.7.18.129 | Primary DNS, TTL / cutover client |
| Mac 2 | Yashi | 10.7.31.128 | Primary edge (nginx) |
| Mac 3 | Manan | 10.7.10.192 | Backend A, **backup DNS**, **standby edge** |
| Mac 4 | Akhil | 10.7.12.3 | Backend B, main test client |

## Layout

| Path | Purpose |
| --- | --- |
| `config/backup-dnsmasq.conf` | Backup resolver on Mac 3, same records as Mac 1 |
| `config/pf-backend.conf` | Backend isolation rules for Mac 3 and Mac 4 |
| `config/standby-edge.conf` | Standby nginx edge on Mac 3 |
| `standby-certificate.md` | Standby certificate: key on Mac 3, signed by the team CA on Mac 2 |
| `scripts/lb-loop.sh` | Client loop: status code and backend once per second (Ext D) |
| `scripts/watch-edge.sh` | Client loop: resolver answer and answering edge every 3 s (Ext B, E) |
| `scripts/capture.sh` | Runs one test step and saves its real output with timestamps |
| `REPORT.md`, `report/` | Results summary and the IEEE-format report |

Run commands from the repository root. On clients, `--cacert` points at
the team root CA (real validation, never `-k`).

## Capturing evidence

`scripts/capture.sh <step>` runs one test step and saves exactly what the
terminal printed, with the Mac, its IP and timestamps, to
`~/cn/evidence/<step>-<mac>.txt`. Copy those files into the matching
`evidence/Phase-2/` folder. `./phase2/scripts/capture.sh help` lists the steps.

## Ext A · Backup DNS resolver

**Mac 3**: install and run the backup (port 53 must be free, firewall must allow dnsmasq):

```bash
cp phase2/config/backup-dnsmasq.conf /opt/homebrew/etc/dnsmasq.conf
sudo brew services stop dnsmasq 2>/dev/null
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /opt/homebrew/Cellar/dnsmasq/2.93/sbin/dnsmasq
sudo /opt/homebrew/sbin/dnsmasq -d -C /opt/homebrew/etc/dnsmasq.conf
```

**Clients (Mac 1, Mac 3, Mac 4)**: primary first, backup second:

```bash
sudo networksetup -setdnsservers Wi-Fi 10.7.18.129 10.7.10.192
networksetup -getdnsservers Wi-Fi
sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder
```

| Step | Where | Evidence | Status |
| --- | --- | --- | --- |
| Backup running, firewall allows it, answers both names and external names; client resolver order | Mac 3 | `A-Backup-DNS/backup-resolver-mac3.txt` | captured |
| Normal lookup answered by the primary (`SERVER: 10.7.18.129`) | Mac 3 | `A-Backup-DNS/primary-answering-mac3.jpg` | captured |
| `dig @10.7.10.192 app.team1.test` from another Mac | Mac 4 | `A-Backup-DNS/backup-direct-query-mac4.jpg` | captured |
| Mac 4 resolver order: `networksetup -getdnsservers Wi-Fi` | Mac 4 | `A-Backup-DNS/client-dns-mac4.jpg` | to capture |
| Primary stopped: `sudo brew services stop dnsmasq`, later `start` | Mac 1 | `A-Backup-DNS/primary-stop-restore-mac1.jpg` | to capture |
| During the outage: flush, `dig app.team1.test` shows `SERVER: 10.7.10.192#53`, curl succeeds | Mac 4 | `A-Backup-DNS/failover-mac4.jpg` | to capture |
| Query from Mac 4 in the backup's live log | Mac 3 | `A-Backup-DNS/backup-query-log-mac3.jpg` | to capture |

## Ext C · Service isolation (backend firewall)

**Mac 3 and Mac 4**:

```bash
sudo cp /etc/pf.conf ~/cn/pf.conf.backup
sudo pfctl -a com.apple/cnproject -f phase2/config/pf-backend.conf
sudo pfctl -E
sudo pfctl -a com.apple/cnproject -s rules
```

Tests: Mac 1 `curl -sS --max-time 5 http://10.7.10.192:3001/api/status` (and `10.7.12.3:3002`),
Mac 1 through the edge `curl --cacert ~/cn/rootCA.pem https://app.team1.test/api/status`,
Mac 2 `curl -s http://10.7.10.192:3001/api/status`.

Rollback on **Mac 3 and Mac 4**:

```bash
sudo pfctl -a com.apple/cnproject -F all
sudo pfctl -d
diff /etc/pf.conf ~/cn/pf.conf.backup && echo "pf.conf unchanged"
```

| Step | Where | Evidence | Status |
| --- | --- | --- | --- |
| Before: direct access to Backend A works | Mac 1 | `C-Isolation/direct-access-before-mac1.jpg` | captured |
| Rules loaded, pf enabled | Mac 3, Mac 4 | `C-Isolation/pf-mac3.jpg`, `pf-mac4.jpg` | captured |
| Direct 3001 and 3002 fail, edge still serves | Mac 1 | `C-Isolation/blocked-mac1.jpg` | captured |
| Edge allowed to reach Backend A | Mac 2 | `C-Isolation/allowed-mac2.jpg` | captured |
| Rollback, pf disabled, `pf.conf unchanged` | Mac 3, Mac 4 | `C-Isolation/pf-restore-mac3.jpg`, `pf-restore-mac4.jpg` | captured |

## Ext D · Backend failover

**Mac 4**: `./phase2/scripts/lb-loop.sh` (or a `curl | grep x-backend` loop). **Mac 3**: Ctrl+C in the
Backend A tab, later `./phase1/backend/run-backend-a.sh`. **Mac 2**:
`tail -n 5 /opt/homebrew/var/log/nginx/error.log`.

| Step | Where | Evidence | Status |
| --- | --- | --- | --- |
| A and B alternate, then only B after Backend A stops | Mac 4 | `D-Backend-Failover/backend-a-down-mac4.jpg` | captured |
| nginx logs `connect() failed (61: Connection refused)` for upstream 10.7.10.192:3001 | Mac 2 | `D-Backend-Failover/nginx-error-log-mac2.jpg` | captured |
| Full run: baseline, A stopped (10/10 served by B), A restarted and back in rotation | Mac 3 | `D-Backend-Failover/failover-and-recovery-mac3.txt` | captured |

## Ext E setup · Standby edge on Mac 3

Do this after the Ext C rollback (the firewall only allows Mac 2).
Certificate first: [standby-certificate.md](standby-certificate.md). Then on **Mac 3**:

```bash
cp phase2/config/standby-edge.conf /opt/homebrew/etc/nginx/servers/team1-standby.conf
sudo nginx -t && sudo nginx
curl -sI --cacert ~/cn/rootCA.pem --resolve app.team1.test:443:10.7.10.192 https://app.team1.test/api/status | grep -i x-edge
```

Expected: `x-edge: mac3-standby`.

## Ext B + E · TTL, record change, edge cutover

1. **Mac 1**: `dig app.team1.test | grep -A1 'ANSWER SECTION'` shows TTL 30.
2. **Mac 1**: new tab, `./phase2/scripts/watch-edge.sh`. It prints the OS resolver's answer and the `x-edge` header every 3 s.
3. **Mac 1**: point the name at the standby, then restart dnsmasq:
   ```bash
   sed -i '' 's/^host-record=app.team1.test,.*/host-record=app.team1.test,10.7.10.192/' /opt/homebrew/etc/dnsmasq.conf
   grep host-record /opt/homebrew/etc/dnsmasq.conf
   sudo brew services restart dnsmasq
   ```
   **Mac 3**: same `sed` on the backup, Ctrl+C and start dnsmasq again.
4. **Mac 1**: the loop keeps the old edge until the cached answer expires (≤ 30 s), then switches. At the same moment `dig +short app.team1.test` already shows `10.7.10.192`, while `dscacheutil -q host -a name app.team1.test` still shows the old IP.
5. **Mac 4**: flush, then `curl -sI --cacert ~/cn/rootCA.pem https://app.team1.test/api/status | grep -i x-edge` shows `mac3-standby` at once.
6. **Mac 1 and Mac 3**: put the record back to `10.7.31.128` and restart. **Mac 1**: `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`, and the loop switches back immediately.

| Step | Where | Evidence | Status |
| --- | --- | --- | --- |
| TTL 30 on the answer | Mac 1 | `B-TTL/ttl-30-mac1.jpg` | captured |
| Primary edge answering before cutover (`x-edge: mac2`) | Mac 1 | `E-Edge-Migration/primary-edge-header-mac1.png` | captured |
| Standby ready (`x-edge: mac3-standby`) | Mac 3 | `E-Edge-Migration/standby-preflight-mac3.jpg` | to capture |
| Record changed on both resolvers | Mac 1, Mac 3 | `E-Edge-Migration/dns-cutover-mac1.jpg` | to capture |
| Timestamped loop: old edge until TTL expiry, then standby | Mac 1 | `B-TTL/automatic-expiry-mac1.jpg` | to capture |
| `dig` new IP vs. OS cache old IP | Mac 1 | `B-TTL/dig-vs-os-cache-mac1.jpg` | to capture |
| Fresh client reaches the standby at once | Mac 4 | `E-Edge-Migration/fresh-standby-mac4.jpg` | to capture |
| Rollback + manual flush switches back immediately | Mac 1 | `B-TTL/manual-flush-mac1.jpg` | to capture |

## Ext F · Faculty-injected fault

On the client (Mac 4), one layer at a time; the first failing step names the layer:

```bash
dig app.team1.test                                         # DNS
ping -c 2 10.7.31.128                                      # IP
nc -vz app.team1.test 443                                  # TCP
openssl s_client -connect app.team1.test:443 -servername app.team1.test \
  -CAfile ~/cn/rootCA.pem </dev/null 2>/dev/null | grep 'Verify return'   # TLS
curl -i --cacert ~/cn/rootCA.pem https://app.team1.test/api/status        # HTTP
```

Save as `F-Troubleshooting/faculty-fault-mac4.jpg` (during evaluation).

## After the demo

```bash
sudo networksetup -setdnsservers Wi-Fi empty                 # clients
sudo nginx -s stop                                           # Mac 2, Mac 3
sudo pfctl -a com.apple/cnproject -F all; sudo pfctl -d      # Mac 3, Mac 4, if loaded
```
