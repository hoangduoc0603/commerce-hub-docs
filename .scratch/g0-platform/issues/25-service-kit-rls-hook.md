# 25: `service-kit`: hook RLS cho JdbcClient và JPA

Status: ready-for-human
Blocked by: 18
Repos: libs/service-kit, docs
Spec: [G0](../spec.md)

## Mô tả

Module `workspace-access` bản G0 (phần dữ liệu): Workspace hiện tại giữ trong `ScopedValue`; hook `TransactionExecutionListener.afterBegin` chạy `set_config('app.workspace_id', ?, true)` cho cả `DataSourceTransactionManager` và `JpaTransactionManager`; thiếu context thì ném exception; không đổi Workspace khi transaction đang mở; chế độ khai báo tường minh "không thuộc Workspace" (không đặt tham số, bảng có RLS trả 0 dòng). Artifact test-fixtures chứa test catalog RLS và test hành vi qua PgBouncer `transaction`. Bản sao Member, filter HTTP, interceptor Kafka để G1. Theo [ADR-0010](../../../adr/0010-workspace-isolation-shared-schema-with-mandatory-rls.md), [ADR-0012](../../../adr/0012-two-persistence-stacks-one-rls-hook.md), [db-migration.md](../../../standards/db-migration.md).

## Mục tiêu học

- Row-Level Security với connection pool ở chế độ transaction: vì sao `set_config(..., true)` trong transaction.
- `ScopedValue` (JEP 506) thay cho `ThreadLocal` trên virtual thread.

## Tiêu chí nghiệm thu

- [ ] Test `N11_` với mẫu `JdbcClient` và mẫu JPA, qua container PgBouncer: Workspace A rồi B trên cùng server connection, B thấy 0 dòng của A.
- [ ] Truy vấn ngoài transaction trả 0 dòng; thiếu context thì exception; insert sai Workspace bị `WITH CHECK` từ chối.
- [ ] Chế độ "không thuộc Workspace" đọc được bảng toàn cục và thấy 0 dòng của bảng có RLS.
- [ ] Kiểm `nullif` với `''` trên connection đã từng đặt tham số; ghi kết quả (điểm chưa xác minh).
- [ ] Test catalog bắt được schema cố ý sai: thiếu `FORCE`, policy sai mẫu, FK không ghép, `_app` là owner.
- [ ] Publish bản mới của `service-kit` có test-fixtures.
