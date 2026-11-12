---
status: accepted
date: 2026-11-12
---

# ADR-0003: Một cluster PostgreSQL dùng chung cho mọi service

Mọi service có DB (workspace, channel-connector, catalog, inventory, order), Keycloak và `shopee-sim` dùng chung một `Cluster` CloudNativePG tên `pg-main` (PostgreSQL 18; số instance ở lab theo [ADR-0004](0004-single-instance-by-default-on-homelab.md)) ở namespace `postgres`. Database per service (C1) vẫn giữ ở mức logic: mỗi service một `Database` riêng và bộ role `<svc>_owner` / `_migrator` / `_app`, `REVOKE CONNECT, TEMPORARY ... FROM PUBLIC`, `pg_hba` theo database × role, `connectionLimit` cho từng role. Không service nào có quyền vào database của service khác. Chi tiết và nguồn ở [tra cứu 11/2026](../research/2026-11-postgres-on-cluster.md) (ticket [03](../.scratch/architecture-g0-g1/issues/03-postgres-on-cluster.md)).

## Phương án đã cân nhắc

- **Mỗi service một cluster.** Đây là khuyến nghị trong FAQ của CloudNativePG: cô lập tài nguyên, PITR và nâng cấp riêng cho từng service. Bị loại vì cụm home lab chỉ có 32 GB RAM cho mọi thứ: 7 cluster × 2 instance tốn thêm khoảng 4–8 GB (ước lượng, chưa đo), lớn hơn phần còn lại cho service.

## Hệ quả

- Một service chạy truy vấn nặng hay chiếm hết connection có thể ảnh hưởng service khác. Giảm bằng `connectionLimit` từng role và Pooler PgBouncer.
- PITR và nâng cấp major chỉ làm được cho cả cluster. Muốn khôi phục dữ liệu một service phải dựng cluster mới từ backup rồi chép riêng database đó.
- Quyền ghi CR `DatabaseRole` và `Pooler` tương đương superuser, nên chỉ project `platform` của Argo CD được tạo chúng.
- Tách lại khi: RAM của lab tăng (ví dụ 64 GB), một service cần PITR hay lịch nâng cấp riêng, hoặc số đo cho thấy noisy neighbour giữa các service. Việc tách là dựng cluster mới cho service đó rồi chuyển database sang (`pg_dump`/restore hoặc logical replication).

## Ghi chú

- 2026-11-13: Đổi tên service `tenant` thành `workspace` theo GLOSSARY ([ticket 09](../.scratch/architecture-g0-g1/issues/09-g1-contracts.md#answer), Q24). Quyết định không đổi.
