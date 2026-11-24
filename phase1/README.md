# Phase 1 · Build and Observe

A client resolves `app.team1.test` through our own DNS server (Mac 1),
connects over HTTPS to an nginx edge (Mac 2) where TLS terminates, and
nginx load-balances each request to Backend A (Mac 3) or Backend B (Mac 4).

![Topology](../docs/topology.png)

## Layout

| Path | Contents |
| --- | --- |
| [`backend/`](backend) | `server.py` (both backends), `run-backend-a.sh`, `run-backend-b.sh` |
| [`dns/team-dnsmasq.conf`](dns/team-dnsmasq.conf) | Primary DNS for `team1.test` (Mac 1), TTL 30 s |
| [`nginx/nginx.conf`](nginx/nginx.conf) | Edge: TLS, round-robin upstream, passive health checks (Mac 2) |
| [`tls/`](tls) | Team root CA and server certificate steps, SAN extension file |
| [`scripts/`](scripts) | `verify-lan.sh`, `verify-dns.sh`, `verify-backends.sh`, `verify-edge.sh` |

## Machines

| Mac | Owner | Current IP | Role | Service |
| --- | --- | --- | --- | --- |
| Mac 1 | Harshita | 10.7.18.129 | Private DNS + test client | dnsmasq, 53/UDP+TCP |
| Mac 2 | Yashi | 10.7.31.128 | Edge reverse proxy + load balancer (TLS) | nginx, 80 / 443 |
| Mac 3 | Manan | 10.7.10.192 | Backend A | Python REST API, 3001 |
| Mac 4 | Akhil | 10.7.12.3 | Backend B + main test client | Python REST API, 3002 |

The Phase 1 evidence was recorded with earlier DHCP addresses; both sets
are in [`docs/IP-inventory.md`](../docs/IP-inventory.md).

## Launch (from the repository root)

| Mac | Command |
| --- | --- |
| Mac 3 | `./phase1/backend/run-backend-a.sh` |
| Mac 4 | `./phase1/backend/run-backend-b.sh` |
| Mac 2 | `cp phase1/nginx/nginx.conf /opt/homebrew/etc/nginx/servers/team1.conf && sudo nginx -t && sudo nginx` |
| Mac 1 | `cp phase1/dns/team-dnsmasq.conf /opt/homebrew/etc/dnsmasq.conf && sudo brew services start dnsmasq` |
| Clients | `sudo networksetup -setdnsservers Wi-Fi 10.7.18.129` then `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder` |

Certificates: [`tls/certificate-setup.md`](tls/certificate-setup.md).

## Verify

| Script | Run on | Checks |
| --- | --- | --- |
| `phase1/scripts/verify-lan.sh` | any Mac | IP details + ping to all four Macs |
| `phase1/scripts/verify-dns.sh` | client | Name resolves to Mac 2 via Mac 1 |
| `phase1/scripts/verify-backends.sh` | Mac 2 | Both backends answer directly by IP |
| `phase1/scripts/verify-edge.sh` | client | TLS validation, round-robin A/B, HTTP/1.1 and HTTP/2 |

## Results and evidence

| Task | Result | Evidence |
| --- | --- | --- |
| A · Private LAN | Four Macs on 10.7.0.0/19, 0% ping loss between every pair | [`LAN`](../evidence/Phase-1/LAN) |
| B · Private DNS | `app/api.team1.test` → Mac 2, TTL 30 s, two clients resolve via Mac 1 | [`DNS`](../evidence/Phase-1/DNS) |
| C · Two backends | `/`, `/api/status`, `/api/info`, header `X-Backend: A/B` | [`Backends`](../evidence/Phase-1/Backends) |
| D · Edge + load balancing | Round-robin, A and B alternate, HTTP/1.1 and HTTP/2 | [`NGINX`](../evidence/Phase-1/NGINX) |
| E · HTTPS / TLS | Own root CA, server cert with SANs, no warnings, no `-k` | [`TLS`](../evidence/Phase-1/TLS) |
| F · HTTP caching | `Cache-Control: max-age=60`, shared ETag, `304 Not Modified` | [`Caching`](../evidence/Phase-1/Caching) |
| G · Protocol flow | DNS, TCP handshake, TLS 1.2 and 1.3 handshakes, encrypted HTTP, ports | [`Wireshark`](../evidence/Phase-1/Wireshark) |
| 6.3 · Failures | Wrong DNS, wrong record, one backend down, both down (502), wrong port | [`Failures`](../evidence/Phase-1/Failures) |

Each evidence folder has a README listing every file and what it proves.
