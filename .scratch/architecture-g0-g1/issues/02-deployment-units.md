# 02 Đơn vị triển khai ở G0–G1

Type: grilling
Status: resolved
Blocked by:
Map: [Kiến trúc G0–G1](../map.md)

## Question

C1 ghi "modular monolith trước, tách sau", B1 vẽ 10 service, ADR-0001 chốt polyrepo. Ở G0–G1 hệ thống gồm những đơn vị triển khai nào: đủ service theo B1, gộp bớt, hay modular monolith?

## Answer

Chốt ngày 2026-11-12 (người dùng): **tách service theo B1** để làm đúng chuẩn microservice; bỏ hướng modular monolith của C1. Thư mục `commerce-hub/` là workspace của cả hệ thống; mỗi service là một project (một repo, theo ADR-0001) trong `services/`.

Hệ quả cho G1 (suy ra từ ma trận truy vết, mỗi yêu cầu G1 có service sở hữu riêng):
- `services/`: gateway, workspace, channel-connector, catalog, inventory, order.
- `simulators/shopee-sim`, `frontend/` (Next.js).
- Chưa có ở G1: webhook-ingress, notification (G2), fulfillment (G4), reporting (G6).

Đi ngược C1 nhưng khớp ADR-0001, nên không cần ADR mới; khi viết arc42 (ticket 14) ghi rõ lý do bỏ modular monolith.

## Comments
- 2026-11-12: Từ ticket [12 Kiến trúc shopee-sim](12-shopee-sim.md#answer): `simulators/shopee-sim` đổi thành `simulators/marketplace-sim`, một repo và một deployable phục vụ cả Shopee và TikTok (khớp ADR-0001).
