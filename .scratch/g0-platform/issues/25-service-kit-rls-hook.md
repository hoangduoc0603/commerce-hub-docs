# 25: `service-kit`: hook RLS cho JdbcClient và JPA

Status: ready-for-human
Hoãn tới: G1 (quyết định 2026-11-15, spec G0 mục "Sửa phạm vi 2026-11-15", gạch đầu dòng "Bỏ thư viện dùng chung")
Lý do: không còn thư viện dùng chung ([ADR-0018](../../../adr/0018-self-contained-services-no-shared-library-yet.md)); ở G0 `hello` chỉ có bảng toàn cục nên hook không có ai dùng. Làm trong service đầu tiên có bảng theo Workspace, cùng lúc với case thật (N11 thuộc giai đoạn 1 trong ma trận truy vết).
Blocked by: ~~18~~ (service đầu tiên có bảng theo Workspace ở G1)
Repos: ~~libs/service-kit~~ service G1 đầu tiên có bảng theo Workspace, docs
Spec: [G0](../spec.md)

## Mô tả

Module `workspace-access` bản G0 (phần dữ liệu): Workspace hiện tại giữ trong `ScopedValue`; hook `TransactionExecutionListener.afterBegin` chạy `set_config('app.workspace_id', ?, true)` cho cả `DataSourceTransactionManager` và `JpaTransactionManager`; thiếu context thì ném exception; không đổi Workspace khi transaction đang mở; chế độ khai báo tường minh "không thuộc Workspace" (không đặt tham số, bảng có RLS trả 0 dòng). Artifact test-fixtures chứa test catalog RLS và test hành vi qua PgBouncer `transaction`. Bản sao Member, filter HTTP, interceptor Kafka để G1. Theo [ADR-0010](../../../adr/0010-workspace-isolation-shared-schema-with-mandatory-rls.md), [ADR-0012](../../../adr/0012-two-persistence-stacks-one-rls-hook.md), [db-migration.md](../../../standards/db-migration.md).

## Sửa phạm vi 2026-11-15 (bỏ `service-kit`)

Theo [ADR-0018](../../../adr/0018-self-contained-services-no-shared-library-yet.md).

- Giữ: toàn bộ hành vi và tiêu chí về hook, `ScopedValue`, chế độ "không thuộc Workspace", test catalog, test hành vi qua PgBouncer, kiểm `nullif`.
- Đổi: code nằm trong service G1 đầu tiên có bảng theo Workspace thay cho module `workspace-access`; test catalog và test hành vi là test của service đó, không phải artifact test-fixtures. Mẫu JPA chứng minh ADR-0012 nằm ở service JPA đầu tiên (nếu service đầu tiên dùng `JdbcClient` thì tiêu chí "mẫu JPA" đi cùng service JPA kế tiếp).
- Bỏ: publish `service-kit` có test-fixtures.
- Tên ticket giữ nguyên vì số ticket là ID cố định; khi lên spec G1, ticket này chuyển sang spec đó.

## Mục tiêu học

- Row-Level Security với connection pool ở chế độ transaction: vì sao `set_config(..., true)` trong transaction.
- `ScopedValue` (JEP 506) thay cho `ThreadLocal` trên virtual thread.

## Tiêu chí nghiệm thu

- [ ] Test `N11_` với mẫu `JdbcClient` và mẫu JPA, qua container PgBouncer: Workspace A rồi B trên cùng server connection, B thấy 0 dòng của A.
- [ ] Truy vấn ngoài transaction trả 0 dòng; thiếu context thì exception; insert sai Workspace bị `WITH CHECK` từ chối.
- [ ] Chế độ "không thuộc Workspace" đọc được bảng toàn cục và thấy 0 dòng của bảng có RLS.
- [ ] Kiểm `nullif` với `''` trên connection đã từng đặt tham số; ghi kết quả (điểm chưa xác minh).
- [ ] Test catalog bắt được schema cố ý sai: thiếu `FORCE`, policy sai mẫu, FK không ghép, `_app` là owner.
- ~~Publish bản mới của `service-kit` có test-fixtures.~~ Bỏ (2026-11-15).

## Comments

- 2026-11-15: Dời ra sau ticket 24, ở vị trí 8 của mục "Thứ tự làm" trong spec G0. Lý do: khi đó chưa có service nào dùng hook, nên API của module (Q1–Q4 lúc lập lộ trình: chỗ đặt container PgBouncer, dạng test catalog, mức chặn đổi Workspace khi transaction đang mở, ba ràng buộc JPA của ADR-0012) phải đoán. Chưa ghi lộ trình; bốn câu này chốt lại khi bắt đầu, lúc `hello` đã chạy trên lab. Ba điều đã kiểm vẫn dùng được: `afterBegin` chạy sau `doBegin` và ngoài `try` nên kiểm context ở `beforeBegin` (bytecode `spring-tx` 7.0.10); Boot 4.1.2 tự gắn bean `TransactionExecutionListener` vào transaction manager tự cấu hình (`ExecutionListenersTransactionManagerCustomizer`); user mặc định của Testcontainers là superuser nên bỏ qua RLS.
