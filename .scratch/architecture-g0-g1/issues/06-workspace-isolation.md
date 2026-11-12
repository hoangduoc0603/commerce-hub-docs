# 06 Cô lập Workspace ở tầng dữ liệu

Type: grilling
Status: open
Blocked by: 03, 05
Map: [Kiến trúc G0–G1](../map.md)

## Question

Với shared schema + cột `tenant_id` (C8), N11 được bảo đảm thế nào?
- RLS nhận `tenant_id` ra sao khi dùng connection pool (`SET LOCAL` trong transaction?), trong consumer Kafka, trong job nền chạy cho mọi Workspace.
- Role DB nào chạy app, ai được `BYPASSRLS` (đề xuất trong [db-migration.md](../../../standards/db-migration.md)).
- Test cô lập tự động (N11) ở seam nào.
- ADR: shared schema + RLS so với schema-per-tenant (C8 yêu cầu so sánh).
