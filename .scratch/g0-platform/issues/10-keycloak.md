# 10: Keycloak production sau `edge` (bản mỏng)

Status: ready-for-human
Blocked by: 08
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

Keycloak Operator 26.8.2 chạy 1 instance Keycloak ở chế độ production, dùng image chính thức (ghim phiên bản), DB `keycloak` trên `pg-main` (đã tạo ở ticket 08, nối thẳng `-rw`). `auth.lab.internal` qua Gateway `edge` chỉ mở `/realms/commerce-hub`, `/resources/`, `/.well-known/`. `edge` kết thúc TLS và nói HTTP với Keycloak trong cụm. Trang admin chỉ vào bằng `kubectl port-forward`. Theo [keycloak.md](../../../standards/keycloak.md), [cluster-entry.md](../../../standards/cluster-entry.md).

Ghi chú về cạnh chặn: bỏ 07, vì lý do duy nhất cần bundle của trust-manager là `BackendTLSPolicy`, nay đã hoãn sang G7.

## Mục tiêu học

- IdP sau reverse proxy: hostname, proxy kết thúc TLS, và vì sao không tin `X-Forwarded-For` do client đặt.

## Thu hẹp 2026-11-15

Theo quyết định D5 (spec G0 mục "Sửa phạm vi 2026-11-15").

- Giữ: Keycloak Operator, 1 instance chế độ production, DB `keycloak` trên `pg-main`, hostname `auth.lab.internal` qua `edge` với danh sách path công khai ở trên, realm dạng code (ticket 11).
- Hoãn tới G1: image build riêng chứa theme và `passwordBlacklist`, làm cùng luồng đăng ký nhà bán. G0 dùng image chính thức.
- Hoãn tới G7: hostname admin `kc-admin.lab.internal` (trước mắt dùng `kubectl port-forward`); re-encrypt Envoy → Keycloak cổng 8443 bằng `BackendTLSPolicy` (trước mắt `edge` kết thúc TLS, HTTP trong cụm).

Tiêu chí hoãn tới G7:

- `BackendTLSPolicy` `Accepted`; tắt TLS phía Keycloak thì `edge` trả 503.

## Tiêu chí nghiệm thu

- [ ] CR `Keycloak` `Ready=True`; log không có "dev mode".
- [ ] `/realms/master/`, `/admin/`, `/metrics` từ ngoài cụm qua `auth.` trả 404 hoặc 403.
- [ ] Keycloak chỉ nghe HTTP trong cụm, nhưng URL nó sinh ra khi gọi qua `auth.` là `https://auth.lab.internal/...` (`iss` của token kiểm ở ticket 11).
- [ ] Đăng nhập sai với `X-Forwarded-For: 6.6.6.6`: event ghi IP khác `6.6.6.6`.
- [ ] Health `UP` và metric `keycloak_user_events` qua cổng 9000.
- [ ] Vào được admin console bằng `kubectl port-forward`; runbook ghi lệnh và cấu hình hostname cần cho việc này. **Chưa xác minh:** chỉ đặt `hostname` thì admin console có thể redirect về `https://auth.lab.internal/admin`, đường `edge` chặn; có thể phải đặt `hostname-admin` trỏ về địa chỉ `port-forward`.
