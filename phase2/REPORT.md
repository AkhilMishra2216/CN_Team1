# Phase 2 report · Harden, Recover, and Troubleshoot

Full report in IEEE format: [`report/phase2-report.pdf`](report/phase2-report.pdf)
(LaTeX source alongside). This page summarises the measured results.

## What changed from Phase 1

| Ext | Addition | Where |
| --- | --- | --- |
| A | Backup resolver with the same records; clients list Mac 1, then Mac 3 | dnsmasq on Mac 3 |
| B | Record change observed under a 30 s TTL | Mac 1, Mac 3 |
| C | Backend ports open to the edge only | pf anchor on Mac 3 and Mac 4 |
| D | Passive health checks and retry | nginx upstream on Mac 2 |
| E | Standby edge and DNS cutover | nginx on Mac 4, serving the same mkcert certificate as Mac 2 |
| F | Layered diagnosis procedure | Client (Mac 4) |

## Results · 24 November 2026

### A · Backup DNS (partly run)

- The backup on Mac 3 answers `app.team1.test` and `api.team1.test` with 10.7.31.128, TTL 30, in 3 ms, and forwards other names upstream ([transcript](../evidence/Phase-2/A-Backup-DNS/backup-resolver-mac3.txt)).
- Mac 4 queried the backup directly and got 10.7.31.128 ([screenshot](../evidence/Phase-2/A-Backup-DNS/backup-direct-query-mac4.jpg)).
- With both resolvers listed, normal lookups are answered by the primary (`SERVER: 10.7.18.129#53`, 24 ms) ([screenshot](../evidence/Phase-2/A-Backup-DNS/primary-answering-mac3.jpg)).
- **Still to run:** stop the primary on Mac 1 and show a client resolving through `10.7.10.192`.

### B · TTL (partly run)

- The answer carries TTL 30 ([screenshot](../evidence/Phase-2/B-TTL/ttl-30-mac1.jpg)).
- **Still to run:** record change with a timestamped client loop, `dig` vs. OS cache, manual flush.

### C · Service isolation (complete)

| Test | Before rules | With rules |
| --- | --- | --- |
| Mac 1 → Backend A directly | `{"backend": "A", "status": "ok"}` | `Couldn't connect to server` after 1018 ms |
| Mac 1 → Backend B directly | not captured | `Couldn't connect to server` after 1008 ms |
| Mac 1 → `https://app.team1.test` | `{"backend": "B", ...}` | `{"backend": "A", ...}` |
| Mac 2 (edge) → Backend A directly | not captured | `{"backend": "A", "status": "ok"}` |

Rules on both backends: `pass in quick proto tcp from 10.7.31.128 to any port {3001, 3002}`
then `block return in quick proto tcp from any to any port {3001, 3002}`, in
anchor `com.apple/cnproject`. Rollback flushed the anchor and disabled pf, and
`diff` showed `/etc/pf.conf` unchanged on both Macs.
Evidence: [`C-Isolation`](../evidence/Phase-2/C-Isolation).

### D · Backend failover (complete)

- A client loop on Mac 4 showed A and B alternating, then only B after Backend A was stopped ([screenshot](../evidence/Phase-2/D-Backend-Failover/backend-a-down-mac4.jpg)).
- At 18:26:14 nginx logged `connect() failed (61: Connection refused) while connecting to upstream` for `http://10.7.10.192:3001`, request from 10.7.12.3. That request was then served by B ([screenshot](../evidence/Phase-2/D-Backend-Failover/nginx-error-log-mac2.jpg)).
- A second, fully timestamped run from Mac 3 through Mac 2 ([transcript](../evidence/Phase-2/D-Backend-Failover/failover-and-recovery-mac3.txt)):

  | Phase | Time | Requests | Result |
  | --- | --- | --- | --- |
  | Baseline | 18:58:59 to 18:59:04 | 8 | 200, alternating B, A |
  | Backend A killed | 18:59:05 | | direct `10.7.10.192:3001` refused |
  | Outage | 18:59:06 to 18:59:14 | 10 | 10 × 200, all from B, no errors |
  | A restarted | 18:59:15 | | A answers directly |
  | Recovery | 18:59:16 to 18:59:37 | 18 | B only until 18:59:20; A back at 18:59:21, then alternating |

  A rejoined 6 s after its restart, within the 10 s `fail_timeout`: nginx retries a failed upstream only after that window.

### E · Edge migration (partly run)

- Before the cutover, responses come from the primary edge, `x-edge: mac2` ([screenshot](../evidence/Phase-2/E-Edge-Migration/primary-edge-header-mac1.png)).
- The standby edge runs on Mac 4 with the same backend pool and the same certificate as Mac 2 ([config](config/standby-edge.conf), [certificate notes](standby-certificate.md)).
- After the cutover, at 19:01 on Mac 3 ([transcript](../evidence/Phase-2/E-Edge-Migration/cutover-state-mac3.txt)):

  | Check | Result |
  | --- | --- |
  | Primary DNS (Mac 1) | `app.team1.test. 30 IN A 10.7.12.3` |
  | Backup DNS (Mac 3) | `app.team1.test. 30 IN A 10.7.31.128` (not yet changed) |
  | Mac 3 OS resolver | 10.7.12.3 |
  | 4 requests by name | 200 each, `x-edge: mac4`, backends B, A, B, A |
  | Mac 2 directly | 200, `x-edge: mac2` (old edge still serving) |
  | Certificates | identical on both edges, SHA-256 `17:DA:59:…:C4:51`, issued by the mkcert CA |

- Finding: only the primary resolver had been changed. Clients that fall back to the backup would be sent to the old edge, so a cutover has to change every resolver.
- **Still to run:** backup resolver changed too; timestamped cached-vs-fresh client during the TTL window; rollback to Mac 2.

### F · Faculty fault

Done live during evaluation.

## Troubleshooting findings

| Problem | Symptom | Layer | Cause | Fix |
| --- | --- | --- | --- | --- |
| Addresses changed | Phase 1 configs pointed at old IPs | IP | Lab DHCP gave all four Macs new leases; Mac 4 reported a second new address during setup | Updated DNS records, nginx upstreams and scripts. Certificates unaffected (they name hosts, not IPs) |
| Backup DNS would not start | `failed to create listening socket for 10.7.10.192: Address already in use` | Transport (socket) | An earlier dnsmasq Homebrew service on Mac 3 still held UDP 53 | `sudo brew services stop dnsmasq`, then start the backup |
| Backup DNS unreachable on the LAN | `dig @127.0.0.1` answered; `dig @10.7.10.192` timed out | Host firewall | macOS application firewall had dnsmasq on *Block incoming connections* | `socketfilterfw --unblockapp` for dnsmasq; queries then answered |

The timeout (not a refusal) in the last case was the clue: a closed port is
refused immediately, while a firewall drop shows up as silence.

## Learning by extension

- **A.** DNS redundancy lives in the client's resolver list. A second server only helps because the client names it and moves on when the first does not answer.
- **B.** A record change is a gradual drain, not a switch. The TTL chosen before the change sets how fast clients follow.
- **C.** Listening on 0.0.0.0 makes a backend reachable by everyone, so reachability has to be narrowed on purpose. A host firewall does this without touching the application.
- **D.** Retrying on another upstream turns a backend failure into a little extra latency instead of an error, as long as one healthy backend remains.
- **E.** Moving an edge needs a certificate clients already trust, the same backend pool, and a DNS change on every resolver. Cached clients follow only when their answer expires. Copying the key was quick; a separate key signed by the same CA would be safer.
- **F.** Checking layers in order, and noting refusal vs. timeout, finds the faulty layer faster than guessing.
