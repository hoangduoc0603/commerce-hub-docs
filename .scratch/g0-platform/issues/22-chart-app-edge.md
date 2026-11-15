# 22: Chart `app`: HTTPRoute, truststore

Status: ready-for-human
Blocked by: 07, 21
Repos: platform, gitops, docs
Spec: [G0](../spec.md)

## Mô tả

Thêm vào chart `app` hai khả năng bật bằng values: `httpRoute.*` gắn vào Gateway `edge` (nhiều hostname, chỉ port chính); mount truststore của trust-manager (JVM thêm `-Djavax.net.ssl.trustStore`, Node đặt `NODE_EXTRA_CA_CERTS`). Truststore cần vì Spring Resource Server gọi JWKS qua `https://auth.lab.internal` (ticket 29). Kiểm trên lab bằng một release thử deploy qua Argo CD, chart kéo từ GHCR. Theo [helm-chart.md](../../../standards/helm-chart.md), [ADR-0013](../../../adr/0013-gateway-api-envoy-gateway-shared-edge.md), [ADR-0014](../../../adr/0014-lab-pki-and-dns.md), [ADR-0017](../../../adr/0017-images-and-charts-on-ghcr.md).

## Mục tiêu học

- JVM tin CA nội bộ: truststore phát từ trust-manager, và lỗi `PKIX` khi thiếu.

## Thu hẹp 2026-11-15

Theo quyết định D6, D7 (spec G0 mục "Sửa phạm vi 2026-11-15").

- Giữ: `httpRoute.*`, truststore từ trust-manager, kiểm trên lab qua Argo CD.
- Đổi: chart publish và kéo từ GHCR.
- Hoãn tới G7: NetworkPolicy (ingress theo danh sách cho phép, tự mở cho pod Envoy khi có route, egress chỉ siết khi khai báo `egress.to`); `ct install`; JSON schema của values, kể cả phần kiểm `httpRoute.parentRef`.

Tiêu chí hoãn tới G7:

- Gọi `servicePort` từ pod lạ ở namespace khác bị chặn; qua `edge` vẫn thành công.
- `ct install` vẫn pass (biến thể route chạy trên kind có CRD Gateway API, hoặc chỉ render nếu không có controller; ghi lựa chọn).
- Schema của chart kiểm `httpRoute.parentRef` (chỉ `edge/edge`, `sectionName` hợp lệ): `parentRef` sai tên làm app chỉ `Progressing` mãi, không `Degraded`. Chuyển từ G0-05, review điểm 7.

## Tiêu chí nghiệm thu

- [ ] Release thử có route: `HTTPRoute` `Accepted`, `ResolvedRefs`; `curl https://<host>.lab.internal` qua `edge` trả 200.
- [ ] Release thử JVM gọi `https://argocd.lab.internal` OK; tắt truststore trong values thì lỗi `PKIX`.
- [ ] Release chart mới publish lên GHCR.

## Chuyển từ G0-05

- **Hoãn tới G7** (2026-11-15: bảo mật cửa vào, không cần để service chạy; chỉ một người deploy nên rủi ro chiếm hostname thấp). Ràng buộc hostname theo namespace: hiện mọi namespace có nhãn `edge.lab.internal/routes` khai được bất kỳ `*.lab.internal` nào, kể cả hostname của app khác (path cụ thể hơn thắng). Chọn cơ chế (ví dụ `ValidatingAdmissionPolicy` so `spec.hostnames` của HTTPRoute với danh sách cho phép gắn trên namespace) và thử bằng một route khai `auth.lab.internal` từ namespace service. Review G0-05 điểm 1.
