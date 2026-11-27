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

## Chuyển từ G0-10

- NetworkPolicy của Keycloak (`spec.networkPolicy.http` trong `gitops/infra/keycloak/keycloak.yaml`) chỉ cho pod Envoy của `edge` và pod trong namespace `keycloak` vào cổng 8080. Đi qua `https://auth.lab.internal` (truststore, như tiêu chí ở trên) thì không cần đổi gì. Nếu đặt `jwk-set-uri` nội bộ (`http://keycloak-service.keycloak.svc:8080/realms/commerce-hub/protocol/openid-connect/certs`, `keycloak.md` mục Resource server khuyên) thì phải thêm namespace `hello` vào danh sách đó trong cùng commit, nếu không `hello` timeout khi tải JWKS. Đo 2026-11-27: pod ở namespace khác gọi 8080 thì timeout ([bản ghi G0-10](../../../experiments/2026-11-g0-10-keycloak.md)).
- Discovery của `commerce-hub` đã có `issuer` `https://auth.lab.internal/realms/commerce-hub`; dòng "Issuer đúng" của `keycloak.md` còn phần so với `issuer-uri` của `hello`.

## Chuyển từ G0-11

- Client test là `smoke-test` (chỉ client credentials). Secret: `kubectl -n keycloak get secret realm-commerce-hub -o jsonpath='{.data.SMOKE_TEST_CLIENT_SECRET}' | base64 -d`. Token lấy qua `https://auth.lab.internal/realms/commerce-hub/protocol/openid-connect/token` với Basic auth `smoke-test:<secret>`, `grant_type=client_credentials`.
- Token đo 2026-11-27: `RS256`, `iss` `https://auth.lab.internal/realms/commerce-hub`, `aud` chỉ là chuỗi `commerce-hub-api` (không phải mảng), sống 300 s, không có `realm_access`/`resource_access` ([bản ghi G0-11](../../../experiments/2026-11-g0-11-realm-as-code.md)). Test "sai `aud`" cần một token khác: client `account-console` (user đăng nhập) cho `aud` `account`.
