# 16 Cửa vào cụm: Gateway API, TLS và hostname của lab

Type: research
Status: resolved
Blocked by:
Map: [Kiến trúc G0–G1](../map.md)

## Question

Lộ ra khi viết arc42 (ticket [14 Khung arc42 và C4 Context/Container](14-arc42-c4.md)): chưa ticket nào chốt traffic từ trình duyệt đi vào cụm bằng gì, trong khi G0–G1 cần mở ít nhất `app.<domain-lab>` (`seller-web`), `auth.<domain-lab>` (Keycloak) và `shopee-sim.<domain-lab>` (`marketplace-sim`, trang ủy quyền phải mở được từ trình duyệt). Tài liệu đang lệch nhau: ticket 11 và 12 viết "Ingress nhiều hostname", [keycloak.md](../../../standards/keycloak.md) viết HTTPRoute của Gateway API, [homelab](../../../../platform/docs/homelab-hyperv.md) mục 8.6 ghi `ingress-nginx` đã archive từ 24/03/2026 và gợi ý Envoy Gateway (tương thích K8s 1.37 **chưa xác minh**). Bảng ngân sách của ticket 04 không có controller nào.

Cần chốt, kèm checklist có nguồn trong `docs/standards/` (ví dụ `cluster-entry.md`):

- Gateway API hay Ingress; implementation nào chạy được trên K8s 1.37 cùng Calico và MetalLB; RAM của nó so với khoảng 1 GiB còn dư (ADR-0004).
- Chart `app` sinh `HTTPRoute` hay `Ingress`; ai sở hữu `Gateway` (app `platform` trong `gitops`?).
- TLS: CA nội bộ qua cert-manager (đã có) hay chứng chỉ công khai (DNS-01, cần domain thật); trình duyệt và `channel-connector` tin CA đó bằng cách nào. Keycloak cần TLS re-encrypt theo keycloak.md.
- `<domain-lab>` là gì và phân giải thế nào qua Tailscale (MagicDNS, split DNS hay `/etc/hosts`).
- Danh sách hostname ở G0–G1 và từ G2: `app.`, `auth.`, `shopee-sim.`, `tiktok-sim.`, `webhook-ingress`; các UI vận hành (Grafana, Argo CD, Mailpit) mở qua cửa này hay `port-forward`.
- Mailpit ở lab chạy ở đâu và tốn bao nhiêu RAM (chưa có trong ngân sách ticket 04).

## Answer

Chốt 2026-11-13 (người dùng trả lời Q1–Q9, theo đề xuất của [tra cứu](../../../research/2026-11-cluster-entry.md#đề-xuất-cho-ticket-16)):
- **API và implementation:** Gateway API (CRD standard v1.6.1), Envoy Gateway v1.10.0, Envoy 1 replica, limit đặt tay → [ADR-0013](../../../adr/0013-gateway-api-envoy-gateway-shared-edge.md).
- **Sở hữu:** một Gateway `edge` (namespace `edge`) do app `platform` sở hữu, wildcard `*.lab.internal`, redirect HTTP sang HTTPS. Chart `app` sinh `HTTPRoute`, tự mở NetworkPolicy cho pod Envoy. Gắn route bằng `allowedRoutes: Selector` theo nhãn namespace, không `ReferenceGrant`.
- **TLS:** CA nội bộ, root offline có name constraints, intermediate trong cụm làm `ClusterIssuer lab-ca` → [ADR-0014](../../../adr/0014-lab-pki-and-dns.md).
- **Tin CA:** Keychain trên Mac; trust-manager v0.26.0 sinh truststore toàn JVM; `NODE_EXTRA_CA_CERTS` cho Node. Chart `app` lo mount và đặt biến.
- **Domain và DNS:** `lab.internal`; dnsmasq trên `gw` (wildcard về `10.20.0.200`), split DNS Tailscale, block CoreDNS.
- **Hostname:** G0–G1 `app.`, `auth.`, `shopee-sim.`, `argocd.`, `grafana.`, `kc-admin.`; G2 thêm `tiktok-sim.`, `webhooks.`. Prometheus, Alertmanager, admin API của simulator dùng `port-forward`.
- **Keycloak:** re-encrypt bằng `BackendTLSPolicy` v1; route công khai chỉ `/realms/commerce-hub`, `/resources/`, `/.well-known/`; admin ở `kc-admin.`; test giả mạo `X-Forwarded-For` bắt buộc.
- **Mailpit:** v1.33.1 trên `gw` (systemd, `MemoryMax=128M`), SMTP `10.20.0.5:1025`.
- **RAM:** thêm khoảng 480 MiB; biên của lab còn khoảng 520 MiB (ADR-0004).

## Comments
- 2026-11-13: Khi resolve, sửa theo các chỗ đang ghi "Ingress": ticket [11](11-service-template.md) (chart `app`), [12](12-shopee-sim.md) (định tuyến `marketplace-sim`), và đối chiếu [keycloak.md](../../../standards/keycloak.md) (HTTPRoute).
- 2026-11-13: Research xong, xem [tra cứu](../../../research/2026-11-cluster-entry.md) và [chuẩn](../../../standards/cluster-entry.md). Đề xuất Gateway API (CRD v1.6.1 standard) với Envoy Gateway v1.10.0, bản duy nhất trong nhóm ghi hỗ trợ K8s 1.37 mà nhẹ (benchmark 10 route: controller khoảng 134 MiB, Envoy khoảng 18 MiB; limit đề xuất tổng 480 MiB gồm cả trust-manager). Gateway `edge` do `platform` sở hữu, chart `app` sinh HTTPRoute. TLS dùng CA nội bộ (root offline có name constraints, intermediate trong cụm), Keycloak re-encrypt bằng `BackendTLSPolicy` v1. Domain `lab.internal` phân giải bằng dnsmasq trên `gw` cộng split DNS của Tailscale cộng CoreDNS. Mailpit v1.33.1 chạy trên `gw`. Nên viết 2 ADR (cửa vào; PKI và DNS).
