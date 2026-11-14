// G0-07 bước 6: máy chủ TLS phục vụ hai chứng chỉ theo SNI (evil.example.com và nc-control.lab.internal).
// tls.crt của cert-manager = leaf + intermediate, nên máy chủ gửi đủ chuỗi; root chỉ nằm ở client.
import https from 'node:https';
import tls from 'node:tls';
import fs from 'node:fs';
const ctx = (d) => tls.createSecureContext({ cert: fs.readFileSync(`${d}/tls.crt`), key: fs.readFileSync(`${d}/tls.key`) });
const byName = { 'evil.example.com': ctx('/certs/evil'), 'nc-control.lab.internal': ctx('/certs/nc-control') };
https.createServer({ SNICallback: (name, cb) => cb(null, byName[name] ?? byName['nc-control.lab.internal']) },
  (req, res) => { res.end(`hello from ${req.headers.host}\n`); })
  .listen(8443, () => console.log('listening 8443'));
