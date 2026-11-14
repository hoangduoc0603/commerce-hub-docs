# 10: Keycloak production sau `edge`

Status: ready-for-human
Blocked by: 07, 08
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

Keycloak Operator 26.8.2 chạy 1 instance Keycloak ở chế độ production, image build sẵn, DB `keycloak` trên `pg-main` (nối thẳng `-rw`). `auth.lab.internal` chỉ mở `/realms/commerce-hub`, `/resources/`, `/.well-known/`; trang admin ở `kc-admin.lab.internal`. Envoy re-encrypt tới cổng 8443 bằng `BackendTLSPolicy`. Theo [keycloak.md](../../../standards/keycloak.md), [cluster-entry.md](../../../standards/cluster-entry.md).

Ghi chú về cạnh chặn: 07 chỉ cần nếu `BackendTLSPolicy` lấy CA từ bundle của trust-manager. Nếu nó tham chiếu thẳng Secret của cert-manager thì bỏ 07.

## Mục tiêu học

- IdP sau reverse proxy: hostname, re-encrypt, và vì sao không tin `X-Forwarded-For` do client đặt.

## Tiêu chí nghiệm thu

- [ ] CR `Keycloak` `Ready=True`; log không có "dev mode".
- [ ] `/realms/master/`, `/admin/`, `/metrics` từ ngoài cụm qua `auth.` trả 404 hoặc 403.
- [ ] `BackendTLSPolicy` `Accepted`; tắt TLS phía Keycloak thì `edge` trả 503.
- [ ] Đăng nhập sai với `X-Forwarded-For: 6.6.6.6`: event ghi IP khác `6.6.6.6`.
- [ ] Health `UP` và metric `keycloak_user_events` qua cổng 9000.
