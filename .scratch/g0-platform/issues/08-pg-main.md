# 08: `pg-main` trên CloudNativePG với role khai báo

Status: ready-for-human
Blocked by: 04
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

CloudNativePG 1.30.1 chạy cluster `pg-main` PostgreSQL 18, 1 instance, requests = limits, cộng một Pooler PgBouncer `transaction`. Database và bốn role `_owner`/`_migrator`/`_app`/`_lookup` khai báo bằng CR trong app `platform`, mật khẩu là `SealedSecret`. Ticket này tạo database `keycloak` và `hello`. Theo [ADR-0003](../../../adr/0003-shared-postgres-cluster.md), [ADR-0004](../../../adr/0004-single-instance-by-default-on-homelab.md), [ADR-0010](../../../adr/0010-workspace-isolation-shared-schema-with-mandatory-rls.md), [db-migration.md](../../../standards/db-migration.md).

## Mục tiêu học

- Postgres qua operator: CR `Cluster`, role và database khai báo, Pooler.
- PDB của operator tương tác với `kubectl drain` khi chỉ có 1 instance.

## Tiêu chí nghiệm thu

- [ ] `pg-main` `Healthy` trong Argo CD; CR `Cluster` và PVC có `Delete=false`.
- [ ] Đăng nhập `hello_app` qua Pooler: `CREATE TABLE x()` bị `permission denied`.
- [ ] `hello_lookup` là `NOLOGIN`; không role đăng nhập được nào có `BYPASSRLS`.
- [ ] Thêm database thứ ba chỉ bằng một commit (ghi vào runbook "thêm service").
- [ ] Thử `kubectl drain` node đang chạy `pg-main`: ghi PDB có chặn không và cách xử lý vào runbook; nếu phải lệch chuẩn thì ghi vào ADR-0004.
