---
status: accepted
date: 2026-11-13
---

# ADR-0014: PKI và DNS của lab: `lab.internal`, CA nội bộ có root offline

Lab dùng domain **`lab.internal`** (ICANN giữ `.INTERNAL` cho dùng riêng từ 29/07/2024) và **CA nội bộ**, không dùng chứng chỉ công khai.

- **PKI:** root CA tạo offline trên Mac, có name constraints chỉ cho `lab.internal`, `svc`, `svc.cluster.local`. Root ký một intermediate CA đưa vào cụm bằng Sealed Secret, làm `ClusterIssuer lab-ca` của cert-manager. Chứng chỉ wildcard `*.lab.internal` của Gateway `edge` ([ADR-0013](0013-gateway-api-envoy-gateway-shared-edge.md)) do annotation trên Gateway sinh. Dựng lại cụm không phải tin lại root.
- **Tin CA:** Mac thêm root vào Keychain hệ thống. JVM dùng truststore PKCS12 do **trust-manager v0.26.0** sinh (root CA cộng CA công khai), chart `app` mount và đặt `-Djavax.net.ssl.trustStore` cho cả JVM, nên mọi HTTP client và `JwtDecoder` tự tin mà không sửa code. Node (`seller-web`) dùng `NODE_EXTRA_CA_CERTS`.
- **Keycloak:** `edge` re-encrypt tới Keycloak bằng `BackendTLSPolicy` v1. Route công khai chỉ gồm `/realms/commerce-hub`, `/resources/`, `/.well-known/`; admin console ở hostname riêng `kc-admin.`.
- **DNS:** dnsmasq trên VM `gw` trả wildcard `*.lab.internal` về IP cố định `10.20.0.200` của `edge` (MetalLB, annotation `metallb.io/loadBalancerIPs`). Mac phân giải qua split DNS của Tailscale (`lab.internal` → `10.20.0.5`), pod qua một server block CoreDNS chuyển về cùng chỗ.
- **Hostname:** G0–G1 có `app.`, `auth.`, `shopee-sim.`, `argocd.`, `grafana.`, `kc-admin.`; từ G2 thêm `tiktok-sim.`, `webhooks.`. Prometheus, Alertmanager và admin API của simulator chỉ dùng `port-forward`.

Chi tiết và nguồn ở [tra cứu 11/2026](../research/2026-11-cluster-entry.md) và [cluster-entry.md](../standards/cluster-entry.md) (ticket [16](../.scratch/architecture-g0-g1/issues/16-cluster-entry.md)).

## Phương án đã cân nhắc

- **Chứng chỉ công khai qua ACME DNS-01.** Không phải cài trust ở đâu cả. Bị loại vì cần domain thật, cụm phải giữ token API của nhà cung cấp DNS, và mọi hostname của lab lộ trên Certificate Transparency log.
- **Root `SelfSigned` sinh trong cụm.** Bị loại vì mỗi lần dựng lại cụm phải tin lại root ở mọi client.
- **SSL bundle của Spring Boot cho từng client.** Bị loại vì phải nhớ cấu hình ở mọi client; sót một chỗ là lỗi TLS lúc chạy.
- **`/etc/hosts`.** Bị loại vì phải sửa ở Mac, mọi node và CoreDNS cho mỗi hostname mới.
- **Tên `.local` hoặc `home.arpa`.** `.local` bị mDNS chiếm trên macOS; `home.arpa` dài hơn mà không thêm lợi ích.

## Hệ quả

- Mọi client mới (máy khác, runner CI, công cụ như k6) phải tin root CA trước khi gọi vào lab.
- Khóa root nằm trên Mac; mất khóa thì phải tạo root mới và tin lại ở mọi nơi. Name constraints giới hạn thiệt hại nếu lộ khóa.
- `kubeadm upgrade` có thể ghi đè Corefile; sau mỗi lần nâng cụm phải diff ConfigMap `coredns` và test phân giải `lab.internal` từ pod.
- **Chưa xác minh**, kiểm khi dựng G0: cert-manager 1.21 chỉ ghi hỗ trợ tới K8s 1.36; Safari, JDK 25, Node có thực thi name constraints của root người dùng thêm không; `fetch` (undici) trong `openid-client` có đọc `NODE_EXTRA_CA_CERTS` không. Kết quả G0-06 (2026-11-15): cert-manager 1.21.3 chạy được trên 1.37 (cài, cấp, cụm trắng); Safari, SecTrust của macOS và Chrome 157 từ chối chứng chỉ ngoài constraints ([bản ghi](../experiments/2026-11-g0.md#5-pki-của-lab-và-https-trên-edge-cấp-chứng-chỉ-chuỗi-tin-cậy-name-constraints-cụm-trắng)). Kết quả G0-07 (2026-11-15): JDK 25 (`name constraints check failed`) và Node 24/26 (`permitted subtree violation`) từ chối chứng chỉ ngoài constraints; `fetch` (undici) của Node 24/26 đọc `NODE_EXTRA_CA_CERTS` ([bản ghi](../experiments/2026-11-g0.md#6-phân-phối-trust-bằng-trust-manager-jvm-node-hairpin-name-constraints)). Mọi mục ở đây đã kiểm.
- Mailpit chạy trên `gw` (systemd, `MemoryMax=128M`), Keycloak gửi SMTP tới `10.20.0.5:1025`. Không tốn RAM của cụm; đổi chỗ rẻ nên không cần ADR riêng.
