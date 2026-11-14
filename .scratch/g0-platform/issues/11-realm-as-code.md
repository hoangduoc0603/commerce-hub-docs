# 11: Realm `commerce-hub` dạng code

Status: ready-for-human
Blocked by: 10
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

Realm `commerce-hub` là YAML trong `gitops`, áp bằng Job keycloak-config-cli. Bản G0 có: chính sách brute force theo BR-02, SMTP tới Mailpit `10.20.0.5:1025`, client `argocd` và `grafana` cho SSO, một client test confidential chỉ bật client credentials có mapper Audience `commerce-hub-api`, và một group admin. Secret của client là `SealedSecret`. Tài khoản admin của chủ repo tạo tay qua `kc-admin.` theo runbook. Client của `seller-web`, `admin-web` và theme đăng ký thuộc G1. Theo [keycloak.md](../../../standards/keycloak.md), [ADR-0008](../../../adr/0008-keycloak-authn-only-members-replicated-via-kafka.md).

## Mục tiêu học

- Realm dạng code: idempotent, ghi đè sửa tay.
- OAuth2 client credentials và audience trong access token.

## Tiêu chí nghiệm thu

- [ ] Chạy Job hai lần liên tiếp: lần hai không đổi gì; sửa tay một client trên UI rồi sync lại thì bị ghi đè.
- [ ] Token client credentials của client test có `aud` chứa `commerce-hub-api`; `iss` là `https://auth.lab.internal/realms/commerce-hub`.
- [ ] Email thử từ realm tới Mailpit, xem được qua API Mailpit; đo RAM Mailpit.
- [ ] 31 lần sai mật khẩu liên tiếp với user thử thì có event khóa tạm.
- [ ] Refresh token dùng lại sau khi đã refresh thì nhận `invalid_grant`.
- [ ] Runbook "tạo tài khoản admin trong realm".
