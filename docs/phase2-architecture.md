# Phase 2 architecture

Phase 2 keeps the Phase 1 path (client → DNS on Mac 1 → HTTPS to the edge
on Mac 2 → plain HTTP to Backend A or B) and adds a fallback for every
layer that can fail.

```
                       DNS, UDP 53                      backup (Ext A)
Client (Mac 4, Mac 1) ─────────────► Mac 1 primary dnsmasq ┄┄┄┄► Mac 3 backup dnsmasq
        │                             app.team1.test → 10.7.31.128, TTL 30 s
        │ HTTPS 443
        ├──────────────► Mac 2 edge nginx (X-Edge: mac2) ──┬─ HTTP ─► Mac 3 Backend A :3001
        │                                                  └─ HTTP ─► Mac 4 Backend B :3002
        ┊ after DNS cutover (Ext E)                            ▲
        └┄┄┄┄┄┄┄┄┄┄┄┄► Mac 3 standby nginx (X-Edge: mac3-standby) ┘
                        pf on Mac 3 and Mac 4: only Mac 2 may open 3001/3002 (Ext C)
```

| Layer that fails | Without Phase 2 | With Phase 2 |
| --- | --- | --- |
| Primary DNS (Mac 1) | Names stop resolving | Clients fall back to Mac 3 (second resolver in their list) |
| One backend | nginx already retried in Phase 1 | Same, now shown live with the error log (Ext D) |
| Direct client access to a backend | Possible: backends listen on 0.0.0.0 | Refused by pf; only the edge is allowed (Ext C) |
| Edge (Mac 2) | Service down | Record moved to the standby on Mac 3; cached clients follow within one TTL (Ext E) |

## Packet behaviour worth pointing at

- **DNS fallback.** Each client keeps its own ordered resolver list. When Mac 1 does not answer, the client sends the same query to Mac 3. `dig` then shows `SERVER: 10.7.10.192#53`.
- **Firewall.** `block return` answers a blocked SYN with a TCP RST, so curl fails at once with *Couldn't connect to server* rather than waiting for a timeout. The edge's own connections from 10.7.31.128 match the `pass` rule first.
- **Health checks.** nginx marks Backend A failed after one refused connection (`max_fails=1`) and skips it for 10 s (`fail_timeout`). `proxy_next_upstream` resends that request to B.
- **TTL.** The OS resolver cache on each client keeps an answer for its TTL. `dig` asks the server directly and sees a change at once; applications see it after the cache entry expires or is flushed.

## Remaining single point of failure

The active edge. A cutover is manual, and clients that cached the old
address keep using it for up to one TTL. Two edges behind one floating
address (VRRP/keepalived) or a health-checked DNS service would remove it.
