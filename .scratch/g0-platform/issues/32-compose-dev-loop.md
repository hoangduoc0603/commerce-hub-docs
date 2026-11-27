# 32: Vòng dev trên Mac với `platform/compose`

Status: ready-for-human
Blocked by: 11, 26
Repos: platform, services/hello, docs
Spec: [G0](../spec.md)

## Mô tả

`platform/compose` dựng trên Mac: Kafka KRaft 1 broker, ~~Apicurio 3~~ (bỏ 2026-11-24, [ADR-0019](../../../adr/0019-no-contracts-repo.md)), PostgreSQL 18 (database và bốn role cho `hello`), PgBouncer `transaction`, Keycloak. Hai init đọc bản checkout `../gitops`: keycloak-config-cli áp realm, `yq` đọc CR `KafkaTopic` (G0 chưa có topic). Có `.env.example` và profile `obs` chạy `grafana/otel-lgtm`. `hello` chạy trên host với profile `local`. README ghi lệch ADR-0001 chỉ ở dev. Thêm một job theo lịch trong `platform` so major.minor của PostgreSQL, Kafka, Keycloak, ~~Apicurio~~ giữa `gitops`, compose ~~và bảng tag của `service-kit`~~ (sửa 2026-11-15: không còn bảng tag dùng chung, [ADR-0018](../../../adr/0018-self-contained-services-no-shared-library-yet.md); tag Testcontainers ghim trong test của từng service, quét chúng xét lại ở G1). Theo ticket 13 của map.

## Mục tiêu học

- Giữ dev giống production mà không chạy chung hạ tầng: nguồn cấu hình duy nhất là `gitops`.

## Tiêu chí nghiệm thu

- [ ] `docker compose up` rồi `./gradlew bootRun --args='--spring.profiles.active=local'`: tạo và đọc lời chào bằng token lấy từ Keycloak local.
- [ ] Bật profile `obs`: trace của `hello` hiện trên Grafana local; tắt thì `hello` vẫn chạy (exporter `none`).
- [ ] Realm local giống realm lab vì đọc cùng YAML.
- [ ] Job so tag đỏ khi cố ý đổi minor của PostgreSQL trong compose.
- [ ] Đo RAM của compose (và compose cộng `hello`) trên Mac, ghi vào bản ghi thí nghiệm.
- [ ] `docker compose down -v` reset sạch.

## Chuyển từ G0-11

- Realm: `gitops/infra/keycloak/realm/commerce-hub.yaml`. Init keycloak-config-cli trong compose dùng cùng image `adorsys/keycloak-config-cli:6.6.0-26.8.1` (ghim digest như `gitops/infra/keycloak/keycloak-config-cli.yaml`) và các biến của Job lab: `IMPORT_CACHE_ENABLED=false`, `IMPORT_VARSUBSTITUTION_ENABLED=true`, `SMOKE_TEST_CLIENT_SECRET` (giá trị dev trong `.env.example`). Thiếu biến này thì công cụ dừng (`undefined-is-error`).
- Ở compose, đăng nhập công cụ bằng admin bootstrap qua password grant của `admin-cli` là đủ: `admin-cli` có sẵn scope `kc-admin-api` mà Keycloak 26.8.2 bắt buộc cho admin API, và có `manage-realm` trên `master` nên không cần `KEYCLOAK_SKIPSERVERINFO`. Lab dùng client service account riêng (runbook `keycloak-admin.md`), vì ở lab không để mật khẩu admin trong cụm.
- SMTP trong file trỏ `10.20.0.5:1025` (Mailpit trên `gw`). Ở compose, nếu muốn kiểm email thì thêm một service Mailpit và ghi đè `smtpServer.host` bằng biến; nếu không thì chỉ là cấu hình không dùng tới.
