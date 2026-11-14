# 22: Chart `app`: HTTPRoute, NetworkPolicy, truststore

Status: ready-for-human
Blocked by: 07, 21
Repos: platform, gitops, docs
Spec: [G0](../spec.md)

## Mô tả

Thêm vào chart `app` ba khả năng bật bằng values: `httpRoute.*` gắn vào Gateway `edge` (nhiều hostname, chỉ port chính); NetworkPolicy ingress theo danh sách cho phép, tự mở cho pod Envoy khi có route, egress chỉ siết khi khai báo `egress.to`; mount truststore của trust-manager (JVM thêm `-Djavax.net.ssl.trustStore`, Node đặt `NODE_EXTRA_CA_CERTS`). Kiểm trên lab bằng một release thử deploy qua Argo CD. Theo [helm-chart.md](../../../standards/helm-chart.md), [ADR-0013](../../../adr/0013-gateway-api-envoy-gateway-shared-edge.md), [ADR-0014](../../../adr/0014-lab-pki-and-dns.md).

## Mục tiêu học

- NetworkPolicy mặc định chặn, và cách chart tự mở đúng nguồn cho Envoy.

## Tiêu chí nghiệm thu

- [ ] Release thử có route: `HTTPRoute` `Accepted`, `ResolvedRefs`; `curl https://<host>.lab.internal` qua `edge` trả 200.
- [ ] Gọi `servicePort` từ pod lạ ở namespace khác bị chặn; qua `edge` vẫn thành công.
- [ ] Release thử JVM gọi `https://argocd.lab.internal` OK; tắt truststore trong values thì lỗi `PKIX`.
- [ ] `ct install` vẫn pass (biến thể route chạy trên kind có CRD Gateway API, hoặc chỉ render nếu không có controller; ghi lựa chọn).
- [ ] Release chart mới publish lên registry.

## Chuyển từ G0-05

- [ ] Ràng buộc hostname theo namespace: hiện mọi namespace có nhãn `edge.lab.internal/routes` khai được bất kỳ `*.lab.internal` nào, kể cả hostname của app khác (path cụ thể hơn thắng). Chọn cơ chế (ví dụ `ValidatingAdmissionPolicy` so `spec.hostnames` của HTTPRoute với danh sách cho phép gắn trên namespace) và thử bằng một route khai `auth.lab.internal` từ namespace service. Review G0-05 điểm 1.
- [ ] Schema của chart kiểm `httpRoute.parentRef` (chỉ `edge/edge`, `sectionName` hợp lệ): `parentRef` sai tên làm app chỉ `Progressing` mãi, không `Degraded`. Review G0-05 điểm 7.
