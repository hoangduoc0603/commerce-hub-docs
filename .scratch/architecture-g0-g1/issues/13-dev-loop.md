# 13 Vòng phát triển local

Type: grilling
Status: open
Blocked by: 04
Map: [Kiến trúc G0–G1](../map.md)

## Question

Khi code một service trên MacBook (arm64), hạ tầng (Kafka, PostgreSQL, Keycloak) lấy từ đâu: cụm home lab qua Tailscale, `platform/compose`, hay `kind`? Có dùng Tilt/Skaffold/Telepresence không. Test tích hợp chạy bằng Testcontainers trên Mac hay trong CI.

## Comments
- 2026-11-12: Từ ticket [04 Ngân sách tài nguyên home lab](04-resource-budget.md#answer): cụm lab chỉ còn dư khoảng 1 GiB sau G1 ([ADR-0004](../../../adr/0004-single-instance-by-default-on-homelab.md)), không chạy thêm được bản sao môi trường (preview, namespace riêng cho dev). Nếu dev loop cần Kafka hay PostgreSQL riêng thì chạy trên Mac (Kafka 1 broker chỉ được dùng ở đó).
