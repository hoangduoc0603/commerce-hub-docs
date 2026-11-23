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
