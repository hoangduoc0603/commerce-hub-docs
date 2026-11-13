# 16 Cửa vào cụm: Gateway API, TLS và hostname của lab

Type: research
Status: open
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

## Comments
