# CN Project - Private Network Service Platform (Team 1)

Computer Networks course project. Four Macs on one private Wi-Fi LAN serve
`https://app.team1.test`: our own DNS resolves the name, TLS terminates at
an nginx edge, and nginx load-balances across two backends.

- **Phase 1 - Build & Observe** (complete): DNS, HTTP(S), TCP, TLS, load balancing, caching, packet analysis.
- **Phase 2 - Harden & Recover** (in progress): backup DNS, TTL and record changes, backend isolation, HA failover, edge migration, fault diagnosis.

The application stays simple; the network is the project.

![Topology](docs/topology.png)

## Team and machines

| Mac | Owner | IP | Phase 1 role | Phase 2 additions |
| --- | --- | --- | --- | --- |
| Mac 1 | Harshita | 10.7.18.129 | Primary DNS (dnsmasq) + test client | TTL / cutover client |
| Mac 2 | Yashi | 10.7.31.128 | Edge: nginx reverse proxy, TLS, load balancer | - |
| Mac 3 | Manan | 10.7.10.192 | Backend A, port 3001 | Backup DNS, standby edge, backend firewall |
| Mac 4 | Akhil | 10.7.12.3 | Backend B, port 3002 + main test client | Backend firewall |

Network 10.7.0.0/19, gateway 10.7.0.1, domain `team1.test`. Addresses come
from the lab DHCP server; the Phase 1 evidence was recorded with earlier
addresses, listed in [`docs/ip-service-inventory.md`](docs/ip-service-inventory.md).

## Request flow

```
Client --DNS, UDP 53------> Mac 1 dnsmasq (backup: Mac 3)   answer: 10.7.31.128
Client --HTTPS, TCP 443---> Mac 2 nginx, TLS ends here      (standby edge: Mac 3)
                              |--plain HTTP--> Mac 3  Backend A :3001
                              |--plain HTTP--> Mac 4  Backend B :3002
```

## Phase 1 - Build & Observe (summary)

All seven build tasks and the five required failure demonstrations are done.

| Task | Result | Evidence |
| --- | --- | --- |
| A - Private LAN | Four Macs on 10.7.0.0/19, 0% ping loss between every pair | [`evidence/01_LAN`](evidence/01_LAN) |
| B - Private DNS | `app/api.team1.test` -> Mac 2, TTL 30 s, two clients resolve via Mac 1 | [`evidence/02_DNS`](evidence/02_DNS) |
| C - Two backends | `/`, `/api/status`, `/api/info`, header `X-Backend: A/B` | [`evidence/03_BACKENDS`](evidence/03_BACKENDS) |
| D - Edge + load balancing | nginx round-robin, A and B alternate, HTTP/1.1 and HTTP/2 | [`evidence/04_NGINX`](evidence/04_NGINX) |
| E - HTTPS / TLS | Own root CA, server cert with SANs, no warnings, no `-k` | [`evidence/05_TLS`](evidence/05_TLS) |
| F - HTTP caching | `Cache-Control: max-age=60`, shared ETag, `304 Not Modified` | [`evidence/06_CACHE`](evidence/06_CACHE) |
| G - Protocol flow | DNS, TCP handshake, TLS 1.2 and 1.3 handshakes, encrypted HTTP, ports | [`evidence/07_WIRESHARK`](evidence/07_WIRESHARK) |
| 6.3 - Failures | Wrong DNS, wrong record, one backend down, both down (502), wrong port | [`evidence/08_FAILURES`](evidence/08_FAILURES) |

## Phase 2 - Harden & Recover

Phase 2 extends the same network. Step-by-step commands:
[`docs/phase2-runbook.md`](docs/phase2-runbook.md).

| Ext | What we add | How | Config | Evidence |
| --- | --- | --- | --- | --- |
| A - Backup DNS | Second resolver on Mac 3 with identical records; clients list Mac 1 then Mac 3 | dnsmasq on Mac 3; primary stopped, clients keep resolving | [`dns/backup-dnsmasq.conf`](dns/backup-dnsmasq.conf) | `evidence/09_BACKUP_DNS` |
| B - TTL + record change | 30 s TTL; record changed while a client watches | OS cache keeps the old answer until TTL expiry; manual flush switches at once | [`dns/team-dnsmasq.conf`](dns/team-dnsmasq.conf) (`local-ttl=30`) | `evidence/10_DNS_TTL` |
| C - Service isolation | Only the edges may reach ports 3001/3002 | macOS `pf` rules in their own anchor; `/etc/pf.conf` untouched; rollback shown | [`firewall/pf-backend.conf`](firewall/pf-backend.conf) | `evidence/11_FIREWALL` |
| D - HA failover | Requests keep flowing when Backend A stops | nginx passive health checks: `max_fails=1 fail_timeout=10s`, `proxy_next_upstream` | [`nginx/nginx.conf`](nginx/nginx.conf) | `evidence/12_HA_FAILOVER` |
| E - Edge migration | Standby nginx on Mac 3, DNS cutover from Mac 2 to Mac 3 | Same pool and TLS settings; own key, signed by the team CA; `X-Edge` shows which edge answered | [`nginx/standby-edge.conf`](nginx/standby-edge.conf), [`tls/standby-certificate.md`](tls/standby-certificate.md) | `evidence/13_EDGE_MIGRATION` |
| F - Fault diagnosis | Faculty injects one fault | Layer by layer: DNS -> IP -> TCP -> TLS -> HTTP | [`docs/phase2-runbook.md`](docs/phase2-runbook.md#ext-f---faculty-injected-fault) | `evidence/14_TROUBLESHOOTING` |

What changed from Phase 1, in short: a second DNS server, a second edge, a
host firewall on both backends, and two client scripts that make failover
and TTL effects visible over time. Nothing in Phase 1 was rebuilt.

The remaining single point of failure is the active edge: if it fails,
clients wait up to one TTL (30 s) before a DNS change reaches them. Removing
it fully needs two edges behind one floating IP (VRRP/keepalived) or a
health-checked DNS service (Route 53 failover).

## Running it

**Phase 1 services** (needed for everything):

| Mac | Command |
| --- | --- |
| Mac 3 | `./backend/run-backend-a.sh` |
| Mac 4 | `./backend/run-backend-b.sh` |
| Mac 2 | `cp nginx/nginx.conf /opt/homebrew/etc/nginx/servers/team1.conf && sudo nginx -t && sudo nginx` |
| Mac 1 | `cp dns/team-dnsmasq.conf /opt/homebrew/etc/dnsmasq.conf && sudo brew services start dnsmasq` |
| Clients | `sudo networksetup -setdnsservers Wi-Fi 10.7.18.129 10.7.10.192` |

Certificates: [`tls/certificate-setup.md`](tls/certificate-setup.md) (Phase 1 edge) and
[`tls/standby-certificate.md`](tls/standby-certificate.md) (Phase 2 standby edge).

**Phase 2**: [`docs/phase2-runbook.md`](docs/phase2-runbook.md).

## Scripts

| Script | Run on | Shows |
| --- | --- | --- |
| `scripts/verify-lan.sh` | any Mac | IP details + ping to all four Macs |
| `scripts/verify-dns.sh` | client | Name resolves to Mac 2 via Mac 1 |
| `scripts/verify-backends.sh` | Mac 2 | Both backends answer directly |
| `scripts/verify-edge.sh` | client | TLS validation, round-robin, HTTP/1.1 and HTTP/2 |
| `scripts/lb-loop.sh` | client | One request per second: status code and backend (Ext D) |
| `scripts/watch-edge.sh` | client | Resolver answer and answering edge every 3 s (Ext B, E) |

## Repository layout

| Path | Contents |
| --- | --- |
| [`backend/`](backend) | `server.py` (both backends), run scripts |
| [`dns/`](dns) | Primary (`team-dnsmasq.conf`, Mac 1) and backup (`backup-dnsmasq.conf`, Mac 3) DNS |
| [`nginx/`](nginx) | Primary edge (`nginx.conf`, Mac 2) and standby edge (`standby-edge.conf`, Mac 3) |
| [`firewall/`](firewall) | `pf-backend.conf` for Mac 3 and Mac 4 |
| [`tls/`](tls) | CA and certificate steps, SAN extension file |
| [`scripts/`](scripts) | Verification and demo scripts |
| [`docs/`](docs) | Architecture, IP inventory, Phase 2 runbook, diagrams |
| [`report/`](report) | Phase 2 report (IEEE format): LaTeX source and PDF |
| [`evidence/`](evidence) | Screenshots and captures, one folder per task; each has a README |

## Security note

Private keys (`*.key`) are excluded by `.gitignore`. The root CA key and the
primary edge key stay on Mac 2; the standby edge key is generated on Mac 3
and never copied. Only the public root CA certificate goes to clients.
