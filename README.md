# CN_Team1

## Private Network Service Platform · Computer Networks Course Project

A private service on four macOS laptops on one Wi-Fi LAN. Our own DNS
resolves `app.team1.test`, an nginx edge terminates TLS and load-balances
across two Python backends, and Phase 2 adds a backup resolver, backend
isolation, health-checked failover and a standby edge. The application
stays simple; the network is the project.

| Phase | Focus | Status |
| --- | --- | --- |
| [Phase 1 · Build & Observe](phase1/README.md) | DNS, HTTP(S), TCP, TLS, load balancing, caching, packet analysis | Complete |
| [Phase 2 · Harden & Recover](phase2/README.md) | Backup DNS, TTL, service isolation, HA failover, edge migration, fault diagnosis | In progress: C and D complete; A, B, E partly; F at evaluation |

---

## Repository structure

```text
CN_Team1/
│
├── phase1/                          # Phase 1: core service platform
│   ├── backend/                     # server.py (Backend A :3001 and B :3002) + run scripts
│   ├── dns/                         # team-dnsmasq.conf, primary DNS on Mac 1
│   ├── nginx/                       # nginx.conf, TLS edge + round-robin upstream on Mac 2
│   ├── tls/                         # Team root CA and server certificate steps
│   ├── scripts/                     # verify-lan / dns / backends / edge
│   └── README.md                    # Phase 1 manual and results
│
├── phase2/                          # Phase 2: resilience and isolation
│   ├── config/                      # backup-dnsmasq.conf, standby-edge.conf, pf-backend.conf
│   ├── scripts/                     # lb-loop.sh, watch-edge.sh
│   ├── report/                      # Phase 2 report, IEEE format (LaTeX + PDF)
│   ├── standby-certificate.md       # Standby edge certificate via the team CA
│   ├── REPORT.md                    # Phase 2 results summary
│   └── README.md                    # Phase 2 runbook, step by step
│
├── docs/                            # Shared documentation
│   ├── IP-inventory.md              # Machines, addresses (current + Phase 1), services
│   ├── architecture.md              # Phase 1 architecture and design decisions
│   ├── phase2-architecture.md       # Phase 2 fallbacks and packet behaviour
│   ├── architecture.pdf
│   ├── topology.png
│   └── request-flow.png
│
├── evidence/
│   ├── Phase-1/                     # LAN, DNS, Backends, NGINX, TLS, Caching, Wireshark, Failures
│   ├── Phase-2/                     # A-Backup-DNS, B-TTL, C-Isolation, D-Backend-Failover,
│   │                                # E-Edge-Migration, F-Troubleshooting
│   └── README.md                    # Evidence index: captured and still to capture
│
├── .gitignore                       # Keeps private keys out of the repo
└── README.md
```

---

## Network

| Machine | Owner | IP (current) | Phase 1 role | Phase 2 additions | Services |
| --- | --- | --- | --- | --- | --- |
| **Mac 1** | Harshita | `10.7.18.129` | Primary DNS + test client | TTL / cutover client | dnsmasq, 53 UDP/TCP |
| **Mac 2** | Yashi | `10.7.31.128` | Edge: reverse proxy, TLS, load balancer | - | nginx, 80 / 443 |
| **Mac 3** | Manan | `10.7.10.192` | Backend A | Backup DNS, standby edge, backend firewall | Python 3001, dnsmasq 53, nginx 443 |
| **Mac 4** | Akhil | `10.7.12.3` | Backend B + main test client | Backend firewall | Python 3002 |

Network `10.7.0.0/19`, gateway `10.7.0.1`, domain `team1.test`
(`app.team1.test`, `api.team1.test`, TTL 30 s). Addresses come from the
lab DHCP server; the Phase 1 evidence used earlier ones, listed in
[`docs/IP-inventory.md`](docs/IP-inventory.md).

![Topology](docs/topology.png)

### Request flow

```
Client --DNS, UDP 53------> Mac 1 dnsmasq        (fallback: Mac 3 dnsmasq)
       <-- 10.7.31.128, TTL 30
Client --HTTPS, TCP 443---> Mac 2 nginx, TLS ends here    (standby: Mac 3 nginx)
                              |--plain HTTP--> Mac 3  Backend A :3001
                              |--plain HTTP--> Mac 4  Backend B :3002
                              pf on Mac 3 + Mac 4: only Mac 2 may open 3001/3002
```

Details: [Phase 1 architecture](docs/architecture.md) ·
[Phase 2 architecture](docs/phase2-architecture.md).

---

## Phase 1 · Build & Observe

All seven build tasks and the five required failure demonstrations are
done. Results and evidence links: [`phase1/README.md`](phase1/README.md#results-and-evidence).

## Phase 2 · Harden & Recover

| Ext | What it adds | Config | Evidence | Status |
| --- | --- | --- | --- | --- |
| A · Backup DNS | Second resolver on Mac 3; clients list Mac 1, then Mac 3 | [`backup-dnsmasq.conf`](phase2/config/backup-dnsmasq.conf) | [`A-Backup-DNS`](evidence/Phase-2/A-Backup-DNS) | Backup answering; failover still to run |
| B · TTL | 30 s TTL observed through a record change | [`team-dnsmasq.conf`](phase1/dns/team-dnsmasq.conf) | [`B-TTL`](evidence/Phase-2/B-TTL) | TTL shown; change + flush still to run |
| C · Isolation | Only the edge may reach ports 3001/3002 | [`pf-backend.conf`](phase2/config/pf-backend.conf) | [`C-Isolation`](evidence/Phase-2/C-Isolation) | Complete, including rollback |
| D · Backend failover | nginx passive health checks + retry | [`nginx.conf`](phase1/nginx/nginx.conf) | [`D-Backend-Failover`](evidence/Phase-2/D-Backend-Failover) | Complete |
| E · Edge migration | Standby nginx on Mac 3 + DNS cutover | [`standby-edge.conf`](phase2/config/standby-edge.conf) | [`E-Edge-Migration`](evidence/Phase-2/E-Edge-Migration) | Baseline only; cutover still to run |
| F · Troubleshooting | Layered diagnosis of a faculty-injected fault | [runbook](phase2/README.md#ext-f--faculty-injected-fault) | [`F-Troubleshooting`](evidence/Phase-2/F-Troubleshooting) | At evaluation |

- [Phase 2 runbook](phase2/README.md): every command, by Mac, in run order
- [Phase 2 results](phase2/REPORT.md) and the [IEEE-format report (PDF)](phase2/report/phase2-report.pdf)
- [Evidence index](evidence/README.md)

---

## Quick start (from the repository root)

| Mac | Phase 1 | Phase 2 |
| --- | --- | --- |
| Mac 1 | `cp phase1/dns/team-dnsmasq.conf /opt/homebrew/etc/dnsmasq.conf && sudo brew services start dnsmasq` | - |
| Mac 2 | `cp phase1/nginx/nginx.conf /opt/homebrew/etc/nginx/servers/team1.conf && sudo nginx -t && sudo nginx` | - |
| Mac 3 | `./phase1/backend/run-backend-a.sh` | Backup DNS and standby edge: [runbook](phase2/README.md) |
| Mac 4 | `./phase1/backend/run-backend-b.sh` | - |
| Clients | `sudo networksetup -setdnsservers Wi-Fi 10.7.18.129 10.7.10.192` | `./phase2/scripts/lb-loop.sh`, `./phase2/scripts/watch-edge.sh` |

## Security note

Private keys (`*.key`) are excluded by `.gitignore`. The root CA key and
the primary edge key stay on Mac 2; the standby edge key is generated on
Mac 3 and never copied. Only the public root CA certificate goes to clients.
