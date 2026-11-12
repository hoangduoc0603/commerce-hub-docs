# 03 PostgreSQL trên cụm home lab

Type: research
Status: resolved
Blocked by:
Map: [Kiến trúc G0–G1](../map.md)

## Question

Chạy PostgreSQL 17+ trên cụm kubeadm 1.37 (3 node, local-path-provisioner, ngân sách RAM chặt) thế nào cho đúng chuẩn production?
- Operator nào: CloudNativePG, Zalando postgres-operator, Crunchy PGO, hay StatefulSet tự viết. So sánh và đề xuất.
- Database per service (C1): một cluster PostgreSQL chứa nhiều database, hay mỗi service một cluster. Tác động lên RAM, backup, cô lập.
- Backup và khôi phục (WAL archive, đích lưu ngoài cụm), HA với 3 node.
- Connection pooling (PgBouncer) và tương thích với advisory lock của Flyway, RLS.
- Mâu thuẫn đã biết: CNPG khuyên app kết nối bằng user owner, nhưng owner bỏ qua RLS ([db-migration.md](../../../standards/db-migration.md)).

Đầu vào: [`docs/standards/db-migration.md`](../../../standards/db-migration.md), [homelab](../../../../platform/docs/homelab-hyperv.md).

## Comments
- 2026-11-12: Research xong, xem [docs/research/2026-11-postgres-on-cluster.md](../../../research/2026-11-postgres-on-cluster.md). Đề xuất: CloudNativePG 1.30.1 + PG 18, một `Cluster` 2 instance dùng chung (mỗi service một `Database` + 3 role, lệch khuyến nghị "một DB mỗi cluster" của CNPG, nên viết ADR), sync `ANY 1` `preferred`. Backup bằng plugin Barman Cloud (cần cert-manager) lên RustFS trên `gw` (MinIO đã archived), `archive_timeout: 1min` cho N10. Pooler PgBouncer `transaction` cho runtime với tenant context bằng `set_config(..., true)`; Flyway và Keycloak nối thẳng `-rw`. "Mâu thuẫn" owner/RLS được chính FAQ CNPG giải: user riêng cho đọc ghi. Lưu ý: K8s 1.37 mới ở mức "tested, not supported" với CNPG 1.30.

## Answer

Chốt 2026-11-12 (người dùng duyệt đề xuất của [tra cứu](../../../research/2026-11-postgres-on-cluster.md#đề-xuất-cho-ticket-03)):
- **Operator:** CloudNativePG 1.30.1, nâng lên 1.31 khi ra (1.30 chỉ "tested, not supported" với K8s 1.37, hết hạn khoảng 12/2026). PostgreSQL 18, image `standard`.
- **Topology:** một `Cluster` `pg-main` dùng chung, mỗi service một `Database` + 3 role → [ADR-0003](../../../adr/0003-shared-postgres-cluster.md).
- **HA:** 2 instance, anti-affinity `required`, đồng bộ `ANY 1` với `dataDurability: preferred`, requests = limits.
- **Backup:** plugin Barman Cloud v0.16.0 (cần cert-manager), đích RustFS trên VM `gw`, `archive_timeout: 1min` (N10), `ScheduledBackup` hằng ngày, giữ 14 ngày; diễn tập PITR ra cluster mới và đo RTO.
- **Pooling:** `Pooler` PgBouncer `transaction` cho runtime; tenant context chỉ đặt bằng `set_config(..., true)` trong transaction. Job Flyway và Keycloak nối thẳng `pg-main-rw`.
- **Role và RLS:** giữ 3 role owner/migrator/app và `FORCE ROW LEVEL SECURITY`; không có mâu thuẫn với CNPG (owner bảng mới bỏ qua RLS, FAQ của CNPG cũng khuyên user riêng). Khai báo role bằng `DatabaseRole` trong app `platform`.

Phần phân quyền + tenant context để ticket 06 chốt trong ADR multi-tenancy. Phụ thuộc mới (cert-manager, RustFS trên `gw`, pod Pooler, sidecar Barman) chuyển sang ticket 04.
