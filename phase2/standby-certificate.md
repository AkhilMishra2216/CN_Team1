# Edge certificates in Phase 2 (Ext E)

In Phase 2 both edges serve one certificate for `app.team1.test` and
`api.team1.test`, issued by Yashi's **mkcert** CA on Mac 2. Every client
trusts that CA's public root (`~/cn/rootCA.pem`; also added to the System
keychain), so validation stays on: `curl --cacert ~/cn/rootCA.pem`, never `-k`.

## What we did

1. **Mac 2** issued the certificate with mkcert:
   ```bash
   mkcert -install
   mkcert -cert-file team1.pem -key-file team1-key.pem app.team1.test api.team1.test
   cp "$(mkcert -CAROOT)/rootCA.pem" .
   ```
2. **Clients** copied `rootCA.pem` to `~/cn/rootCA.pem` and trusted it:
   ```bash
   sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/cn/rootCA.pem
   ```
3. **Mac 4** (standby edge) received `team1.pem` and `team1-key.pem` from Mac 2
   and serves them unchanged.

## Verified

Both edges present the same certificate (captured on Mac 3 at 19:01,
[`cutover-state-mac3.txt`](../evidence/Phase-2/E-Edge-Migration/cutover-state-mac3.txt)):

```bash
echo | openssl s_client -connect 10.7.31.128:443 -servername app.team1.test 2>/dev/null | openssl x509 -noout -fingerprint -sha256 -issuer
echo | openssl s_client -connect 10.7.12.3:443   -servername app.team1.test 2>/dev/null | openssl x509 -noout -fingerprint -sha256 -issuer
# both: sha256 Fingerprint=17:DA:59:37:...:C4:51, issuer=O=mkcert development CA ...
```

## Trade-off

Copying the key was the fastest way to give the standby a trusted
certificate, but it puts one private key on two machines: if either Mac is
compromised, both edges are. The cleaner design is for Mac 4 to generate
its own key and a signing request, and for the same CA to sign it. Clients
would trust it without any change, because they trust the CA rather than a
particular certificate.
