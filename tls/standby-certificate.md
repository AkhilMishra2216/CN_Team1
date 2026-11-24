# Standby edge certificate (Phase 2, Ext E)

The standby edge on Mac 3 needs a certificate for `app.team1.test`.
Copying Mac 2's server key would put the same private key on two machines,
so instead Mac 3 makes its **own** key and asks the Team 1 root CA (on
Mac 2) to sign it. The CA key never leaves Mac 2 and the standby key never
leaves Mac 3; only the CSR and the signed certificate travel (both public).

## 1. Mac 3: key + signing request

```bash
mkdir -p ~/team1-standby && cd ~/team1-standby
openssl genrsa -out standby.app.team1.test.key 2048
openssl req -new -key standby.app.team1.test.key -out standby.app.team1.test.csr \
  -subj "/C=IN/O=Team1 CN Project/CN=app.team1.test"
```

AirDrop `standby.app.team1.test.csr` to Mac 2.

## 2. Mac 2: sign it with the Team 1 root CA

```bash
cd ~/team1-certs
openssl x509 -req -in ~/Downloads/standby.app.team1.test.csr \
  -CA team1-rootCA.pem -CAkey team1-rootCA.key -CAcreateserial \
  -out standby.app.team1.test.crt -days 365 -sha256 \
  -extfile openssl-san.cnf
openssl verify -CAfile team1-rootCA.pem standby.app.team1.test.crt
# standby.app.team1.test.crt: OK
```

AirDrop `standby.app.team1.test.crt` back to Mac 3.

## 3. Mac 3: install for nginx

```bash
mkdir -p /opt/homebrew/etc/nginx/certs
cp ~/team1-standby/standby.app.team1.test.key /opt/homebrew/etc/nginx/certs/
cp ~/Downloads/standby.app.team1.test.crt /opt/homebrew/etc/nginx/certs/
```

Clients need nothing new: they already trust the Team 1 root CA, which
signed both edge certificates.
