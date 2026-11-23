# 29: `hello` bắt buộc JWT

Status: ready-for-human
Blocked by: 11, 27, 28
Repos: services/hello, gitops, docs (bỏ `libs/service-kit` ngày 2026-11-15)
Spec: [G0](../spec.md)

## Mô tả

Mọi route của `hello` bắt buộc JWT của realm `commerce-hub`: chỉ RS256, `audiences: commerce-hub-api`, validator mặc định (`iss`, `exp`, `nbf`). Thiếu hoặc sai token thì trả 401 Problem Details có `traceId` (entry point ~~trong module `web`~~ viết trong `hello`, sửa 2026-11-15 theo [ADR-0018](../../../adr/0018-self-contained-services-no-shared-library-yet.md)). Trên lab, `hello` tin issuer `https://auth.lab.internal` nhờ truststore của chart, không sửa code. Theo mục "Resource server" của [keycloak.md](../../../standards/keycloak.md).

## Mục tiêu học

- OAuth2 resource server: kiểm chữ ký qua JWKS, `iss`, `aud`, và vì sao thiếu `aud` là lỗ hổng.

## Tiêu chí nghiệm thu

- [ ] Test tự động (JWK giả): không token, sai `aud`, hết hạn, realm khác, ký bằng khóa lạ đều trả 401 Problem Details.
- [ ] Trên lab: token client credentials của client test tạo được lời chào; không token thì 401.
- [ ] Bỏ mount truststore trong values thì `hello` không tải được JWKS (lỗi `PKIX` trong log); bật lại thì chạy.
- ~~OpenAPI trong `contracts` khai bảo mật bearer khớp hành vi.~~ Bỏ (2026-11-24, [ADR-0019](../../../adr/0019-no-contracts-repo.md)).
