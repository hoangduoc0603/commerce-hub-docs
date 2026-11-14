# Bằng chứng: cửa vào cụm, DNS và PKI của lab

Bằng chứng theo bảng "Bằng chứng cần có" của [cluster-entry.md](../standards/cluster-entry.md#bằng-chứng-cần-có). Mỗi dòng ghi ngày chạy, ticket và kết quả. Dòng chưa chạy để trống; ticket tương ứng sẽ điền. Bản ghi tổng: [2026-11-g0.md](2026-11-g0.md).

## Bảng bằng chứng

| Kiểm tra | Ngày, ticket | Kết quả | Đạt |
|---|---|---|---|
| DNS từ Mac | 2026-11-14, G0-02 | `dscacheutil -q host -a name x.lab.internal` → `10.20.0.200`; `a.b.lab.internal` → `10.20.0.200`; `github.com` vẫn ra IP công khai | ✅ |
| DNS từ pod | 2026-11-14, G0-02 | `busybox:stable` ép chạy trên từng node `k8s-cp`, `k8s-w1`, `k8s-w2`: `nslookup auth.lab.internal` → `10.20.0.200`. `kubernetes.default.svc.cluster.local` → `10.96.0.1`, `github.com` → IP công khai | ✅ (chạy lại sau mỗi `kubeadm upgrade`) |
| Name constraints | 2026-11-14, G0-02 (một phần) | Chỉ OpenSSL 4.1.0: `platform/scripts/lab-ca/test-constraints.sh` 18/18 PASS (10 ca name constraints, 8 ca root và hành vi script) (chi tiết bên dưới). Chrome, Safari, `curl` ở G0-06; JVM, Node ở G0-07 | ⏳ |
| Đúng phiên bản | 2026-11-14, G0-05 | CRD `gateways…` có `bundle-version: v1.6.1`, `channel: standard`; Deployment `envoy-gateway` có nhãn `helm.sh/chart: gateway-helm-v1.10.0` (Argo CD render bằng `helm template`, không có release Helm nên `helm list` rỗng; dùng nhãn này thay lệnh trong bảng chuẩn) | ✅ |
| Gateway sẵn sàng | 2026-11-14, G0-05 | Gateway `edge` `Accepted=True`, `Programmed=True`; route thử `Accepted`, `ResolvedRefs` | ✅ |
| IP cố định | 2026-11-14, G0-05 | Service Envoy `LoadBalancer`, `EXTERNAL-IP` `10.20.0.200` | ✅ |
| Chặn namespace lạ | 2026-11-14, G0-05 | Route khai trùng `whoami.lab.internal` ở namespace không nhãn: `Accepted=False` `NotAllowedByListeners`, traffic vẫn tới app thật. Giữa namespace có nhãn chưa có ranh giới hostname (G0-22) | ✅ (một phần) |
| RAM | 2026-11-14, G0-05 (lúc rảnh) | Controller 56/256 Mi, Envoy 21/128 Mi, shutdown-manager 23/32 Mi. Đo 24 giờ có tải ở G0-34 | ⏳ |
| HTTP → HTTPS, Hairpin, TLS trên Mac, Trust ở JVM/Node, Re-encrypt Keycloak, Đường dẫn Keycloak bị chặn, Giả `X-Forwarded-For`, Zero-downtime khi đổi Envoy | | | |
| Mailpit | | | |

## Chi tiết

### DNS `lab.internal` (G0-02, 2026-11-14)

**dnsmasq trên `gw`** (dnsmasq 2.90-4~deb12u2, Debian 12):

| Truy vấn từ Mac, `dig @10.20.0.5` | Kết quả |
|---|---|
| `x.lab.internal` A | `10.20.0.200` |
| `a.b.lab.internal` A | `10.20.0.200` (`address=` phủ mọi mức subdomain) |
| `x.lab.internal` AAAA, MX | `NOERROR`, `ANSWER: 0` (sau khi thêm `local=/lab.internal/`; trước đó `REFUSED`) |
| `x.lab.internal` qua TCP | `10.20.0.200` |
| `example.com` | `REFUSED`: không phải resolver mở |

- Socket: chỉ `10.20.0.5:53` (UDP, TCP). `/etc/resolv.conf` của `gw` không đổi; `gw` không có `resolvconf` hay `systemd-resolved`.
- Gói Debian chạy dnsmasq với `--local-service`, nhưng cờ này không có tác dụng khi có `listen-address` (`man dnsmasq`), nên Mac (IP tailnet `100.x`) vẫn hỏi được.
- RAM: `MemoryCurrent` khoảng 0,7 MiB.

**Split DNS của Tailscale trên Mac** (Tailscale 1.104.5, macOS 27.2):

- `tailscale dns status` có route `lab.internal -> 10.20.0.5`.
- `scutil --dns` **không** có resolver `domain : lab.internal`. App Tailscale đăng ký `100.100.100.100` là resolver `Supplemental` không gắn domain, xếp trước DNS của máy; quad-100 tự chia theo domain. Kiểm bằng `tailscale dns status`, không bằng `scutil`.
- Truy vấn trước khi cấu hình để lại cache âm trong `mDNSResponder` (`dns-sd -G v4 x.lab.internal`: `No Such Record`, TTL 108 002 giây). Phải `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`.

**CoreDNS** (v1.14.6): thêm server block `lab.internal:53 { errors; cache 30; forward . 10.20.0.5 }`. Từ lúc patch ConfigMap tới khi cả hai pod in `Reloading complete` mất khoảng **78 giây**. AAAA của `auth.lab.internal` từ pod không lỗi, không địa chỉ.

### Root CA (G0-02, 2026-11-14)

- Tạo bằng `platform/scripts/lab-ca/make-root.sh`, OpenSSL 4.1.0 (Homebrew). Subject `O=commerce-hub lab, CN=commerce-hub lab root CA 2026`, EC P-384, `ecdsa-with-SHA384`, hạn 2026-11-14 → 2036-11-11.
- Extension: `basicConstraints` critical `CA:TRUE`; `keyUsage` critical `keyCertSign, cRLSign`; `nameConstraints` critical, Permitted `DNS:lab.internal`, `DNS:svc`, `DNS:svc.cluster.local`, Excluded `IP:0.0.0.0/0`, `IP:::/0`.
- SHA-256: `A5:92:C1:6B:5A:53:7F:B3:67:52:91:CD:51:3E:59:2D:A4:4B:BF:48:77:4B:B7:68:0F:78:57:75:F7:57:8F:CD`.
- Khóa: `~/lab-ca/lab-root-ca.key` trên Mac (quyền 600, thư mục 700, `ENCRYPTED PRIVATE KEY`), ngoài repo và ngoài cụm. Phần công khai: `platform/pki/lab-root-ca.crt`.
- Tin trên Mac: Keychain System, trust setting ở admin domain (`security dump-trust-settings -d`), fingerprint trong Keychain khớp, `security verify-cert` thành công.

**Name constraints với OpenSSL 4.1.0** (`test-constraints.sh`: chuỗi tạm root → intermediate **không** có ràng buộc riêng → leaf):

| Leaf | Mong đợi | Kết quả |
|---|---|---|
| `ok.lab.internal`, `*.lab.internal`, `kc-service.keycloak.svc`, `kc-service.keycloak.svc.cluster.local` | Chấp nhận | `OK` |
| `evil.example.com`, `lab.internal.evil.com`, `evillab.internal`, `ok.lab.internal` + `github.com` | Từ chối | `permitted subtree violation` |
| IP SAN `10.20.0.200`, `::1` | Từ chối | `excluded subtree violation` |

Đối chứng âm: cùng bộ test với root bỏ dòng `nameConstraints` cho 7 FAIL đúng chỗ, nên test không xanh giả.

### Ghi chú cho G0-06: Avast trên Mac

`security dump-trust-settings -d` có thêm `Avast trusted CA`, root của phần mềm diệt virus dùng để chặn và quét HTTPS. Nếu Avast chặn `*.lab.internal`, trình duyệt sẽ thấy chứng chỉ do Avast ký lại, nên bằng chứng "TLS trên Mac" và "Name constraints" trên Chrome/Safari không còn đánh giá chuỗi của lab. Trước khi lấy bằng chứng trên trình duyệt: xem issuer của chứng chỉ; nếu là Avast thì loại trừ `*.lab.internal` khỏi tính năng quét HTTPS của Avast, và ghi lại.
