// G0-07: gọi HTTPS bằng fetch (undici) có sẵn trong Node, in status hoặc chuỗi nguyên nhân lỗi TLS. Không truyền
// tùy chọn `ca`: trust đến từ bộ root có sẵn của Node cộng NODE_EXTRA_CA_CERTS.
let fail = 0;
console.log(`node ${process.version}, NODE_EXTRA_CA_CERTS=${process.env.NODE_EXTRA_CA_CERTS ?? '(unset)'}, NODE_TLS_REJECT_UNAUTHORIZED=${process.env.NODE_TLS_REJECT_UNAUTHORIZED ?? '(unset)'}`);
for (const url of process.argv.slice(2)) {
  try {
    const r = await fetch(url, { redirect: 'manual' });
    console.log(`OK   ${r.status} ${url}`);
  } catch (e) {
    fail++;
    console.log(`FAIL ${url}`);
    for (let c = e; c; c = c.cause) console.log(`     ${c.name}: ${c.code ?? ''} ${c.message}`);
  }
}
process.exit(fail ? 1 : 0);
