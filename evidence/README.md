# Evidence

Every file here is an original screenshot, packet capture or terminal
transcript from the four Macs. Nothing is reconstructed: a step that has
not been run yet is listed as **to capture**, with the command to run in
[`phase2/README.md`](../phase2/README.md).

## Phase 1 (complete)

Recorded in October 2026 with the Phase 1 addresses (see
[`docs/IP-inventory.md`](../docs/IP-inventory.md#address-history)).

| Folder | Task |
| --- | --- |
| [`Phase-1/LAN`](Phase-1/LAN) | A · Private LAN, IP inventory, ping |
| [`Phase-1/DNS`](Phase-1/DNS) | B · Private DNS server and client resolvers |
| [`Phase-1/Backends`](Phase-1/Backends) | C · Two REST backends |
| [`Phase-1/NGINX`](Phase-1/NGINX) | D · Reverse proxy and round-robin load balancing |
| [`Phase-1/TLS`](Phase-1/TLS) | E · HTTPS with the team root CA |
| [`Phase-1/Caching`](Phase-1/Caching) | F · Cache-Control, ETag, 304 |
| [`Phase-1/Wireshark`](Phase-1/Wireshark) | G · DNS, TCP, TLS and ports in packet captures |
| [`Phase-1/Failures`](Phase-1/Failures) | 6.3 · Five required failure demonstrations |

Each folder has its own README listing what every file proves.

## Phase 2

Recorded on 24 November 2026 with the current addresses: Mac 1 10.7.18.129,
Mac 2 10.7.31.128, Mac 3 10.7.10.192, Mac 4 10.7.12.3.

### A · Backup DNS

| File | Mac | What it shows | Status |
| --- | --- | --- | --- |
| [`backup-resolver-mac3.txt`](Phase-2/A-Backup-DNS/backup-resolver-mac3.txt) | Mac 3 | Backup dnsmasq running in the foreground, its config, firewall set to allow it, answers for `app`, `api` (10.7.31.128, TTL 30) and an external name; Mac 3's resolver order 10.7.18.129 then 10.7.10.192 | captured |
| [`primary-answering-mac3.jpg`](Phase-2/A-Backup-DNS/primary-answering-mac3.jpg) | Mac 3 | With both resolvers listed, a normal lookup is answered by the primary: `SERVER: 10.7.18.129#53`, TTL 30, then HTTPS returns Backend A | captured |
| [`backup-direct-query-mac4.jpg`](Phase-2/A-Backup-DNS/backup-direct-query-mac4.jpg) | Mac 4 | `dig @10.7.10.192 app.team1.test` from another Mac returns 10.7.31.128 | captured |
| `client-dns-mac4.jpg` | Mac 4 | Resolver order on the main client | to capture |
| `primary-stop-restore-mac1.jpg` | Mac 1 | Primary stopped, later restarted | to capture |
| `failover-mac4.jpg` | Mac 4 | During the outage: `SERVER: 10.7.10.192#53`, HTTPS still works | to capture |
| `backup-query-log-mac3.jpg` | Mac 3 | That query in the backup's live log | to capture |

### B · TTL

| File | Mac | What it shows | Status |
| --- | --- | --- | --- |
| [`ttl-30-mac1.jpg`](Phase-2/B-TTL/ttl-30-mac1.jpg) | Mac 1 | `app.team1.test. 30 IN A 10.7.31.128` | captured |
| `automatic-expiry-mac1.jpg` | Mac 1 | Timestamped loop: old answer until expiry, then the new one | to capture |
| `dig-vs-os-cache-mac1.jpg` | Mac 1 | `dig` new IP while `dscacheutil` still old | to capture |
| `manual-flush-mac1.jpg` | Mac 1 | Flush switches the answer at once | to capture |

### C · Service isolation (complete)

| File | Mac | What it shows |
| --- | --- | --- |
| [`direct-access-before-mac1.jpg`](Phase-2/C-Isolation/direct-access-before-mac1.jpg) | Mac 1 | Before the rules: edge returns B, direct `http://10.7.10.192:3001` returns A |
| [`pf-mac3.jpg`](Phase-2/C-Isolation/pf-mac3.jpg) | Mac 3 | Rules loaded into anchor `com.apple/cnproject`, `pf enabled` (after an earlier clean rollback) |
| [`pf-mac4.jpg`](Phase-2/C-Isolation/pf-mac4.jpg) | Mac 4 | Backup DNS answers from Mac 4; rules loaded, `pf enabled` |
| [`blocked-mac1.jpg`](Phase-2/C-Isolation/blocked-mac1.jpg) | Mac 1 | Direct 3001 and 3002: `Couldn't connect to server` after about 1 s; HTTPS through the edge still returns A |
| [`allowed-mac2.jpg`](Phase-2/C-Isolation/allowed-mac2.jpg) | Mac 2 | The edge still reaches Backend A directly |
| [`pf-restore-mac3.jpg`](Phase-2/C-Isolation/pf-restore-mac3.jpg) | Mac 3 | Anchor flushed, `pf disabled`, `pf.conf unchanged` |
| [`pf-restore-mac4.jpg`](Phase-2/C-Isolation/pf-restore-mac4.jpg) | Mac 4 | Rules loaded, then flushed, `pf disabled`, `pf.conf unchanged` |

### D · Backend failover

| File | Mac | What it shows | Status |
| --- | --- | --- | --- |
| [`backend-a-down-mac4.jpg`](Phase-2/D-Backend-Failover/backend-a-down-mac4.jpg) | Mac 4 | Request loop: A and B alternate, then only B after Backend A is stopped | captured |
| [`nginx-error-log-mac2.jpg`](Phase-2/D-Backend-Failover/nginx-error-log-mac2.jpg) | Mac 2 | 18:26:14 `connect() failed (61: Connection refused)` to upstream 10.7.10.192:3001 for a request from 10.7.12.3 | captured |
| [`failover-and-recovery-mac3.txt`](Phase-2/D-Backend-Failover/failover-and-recovery-mac3.txt) | Mac 3 | Full run through Mac 2, timestamped: baseline A/B, Backend A killed, 10/10 requests 200 from B, A restarted at 18:59:15 and back in rotation at 18:59:21 | captured |

### E · Edge migration

| File | Mac | What it shows | Status |
| --- | --- | --- | --- |
| [`primary-edge-header-mac1.png`](Phase-2/E-Edge-Migration/primary-edge-header-mac1.png) | Mac 1 | Before cutover: `HTTP/2 200`, `x-edge: mac2`, `x-backend: A` | captured |
| `standby-preflight-mac3.jpg` | Mac 3 | Standby answers with `x-edge: mac3-standby` | to capture |
| `dns-cutover-mac1.jpg` | Mac 1, Mac 3 | Record moved to 10.7.10.192 on both resolvers | to capture |
| `fresh-standby-mac4.jpg` | Mac 4 | Fresh client reaches the standby at once | to capture |

### F · Troubleshooting

| File | Mac | What it shows | Status |
| --- | --- | --- | --- |
| `faculty-fault-mac4.jpg` | Mac 4 | Layer-by-layer diagnosis of the injected fault | during evaluation |

Setup problems found and fixed during Phase 2 (port 53 conflict, macOS
firewall blocking dnsmasq, DHCP address changes) are written up in the
[Phase 2 report](../phase2/REPORT.md#troubleshooting-findings).
