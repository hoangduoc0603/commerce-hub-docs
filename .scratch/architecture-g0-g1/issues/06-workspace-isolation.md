# 06 Cô lập Workspace ở tầng dữ liệu

Type: grilling
Status: resolved
Blocked by: 03, 05
Map: [Kiến trúc G0–G1](../map.md)

## Question

Với shared schema + cột `workspace_id` (C8), N11 được bảo đảm thế nào?
- RLS nhận `workspace_id` ra sao khi dùng connection pool (`SET LOCAL` trong transaction?), trong consumer Kafka, trong job nền chạy cho mọi Workspace.
- Role DB nào chạy app, ai được `BYPASSRLS` (đề xuất trong [db-migration.md](../../../standards/db-migration.md)).
- Test cô lập tự động (N11) ở seam nào.
- ADR: shared schema + RLS so với schema-per-tenant (C8 yêu cầu so sánh).

## Answer

Chốt ngày 2026-11-13 (người dùng), sau hai vòng grilling (Q1–Q12). Quyết định chính: [ADR-0010](../../../adr/0010-workspace-isolation-shared-schema-with-mandatory-rls.md). Checklist cho migration, policy, role và bằng chứng đã ghi vào [db-migration.md](../../../standards/db-migration.md).

### Các quyết định

1. **Shared schema, code ghi rõ `workspace_id`, RLS là thứ bảo đảm.** Loại schema-per-tenant, database-per-tenant, cách chỉ lọc ở code và cách chỉ dùng RLS (ADR-0010). Cache trong ứng dụng phải có Workspace trong key.
2. **Tên gọi**: cột `workspace_id` (`uuid`), tham số phiên `app.workspace_id`, trường envelope `workspaceId`. Đã sửa C8, kafka.md, lint trong db-migration.md. Chữ "tenant" chỉ còn trong câu nói về kiến trúc multi-tenant.
3. **Consumer Kafka** lấy Workspace từ `workspaceId` trong envelope và tin giá trị này (mỗi topic một producer). Event không có `workspaceId` là lỗi không retry được. Một event mang sai Workspace không thấy được dòng thật và đụng PK hoặc unique khi insert.
4. **Job nền** (BR-29, metric Oversell, poll F5.2b, dọn dữ liệu BR-05 sau này) chạy bằng `_app`, lấy danh sách Workspace qua hàm `_lookup`, rồi xử lý **từng Workspace trong transaction riêng**. Không có role `_system` có `BYPASSRLS`, không có giá trị `'*'`.
5. **FK ghép** `(workspace_id, x_id)` giữa hai bảng có `workspace_id`, bảng cha có `UNIQUE (workspace_id, id)`. PK là `id` UUID toàn cục. Lý do: kiểm FK bỏ qua RLS.
6. **Ngoài N11**: `marketplace-sim` và Keycloak không bật RLS.
7. **Đặt context**: `libs/workspace-access` giữ Workspace trong một `ScopedValue` (Java 25, JEP 506). Ba nơi gắn giá trị: filter HTTP (`MemberContext`, hoặc service account trong danh sách cho phép ở F3.3c), interceptor của consumer Kafka, vòng lặp của job. Hook ở đầu transaction chạy `set_config('app.workspace_id', ?, true)`. Thiếu context thì ném exception; một transaction chỉ thuộc một Workspace; mọi truy cập DB nằm trong transaction (ngoài transaction thì fail closed). Cùng giá trị được đưa vào MDC và span.
8. **Policy** cho mọi role, viết thẳng biểu thức: `workspace_id = nullif(current_setting('app.workspace_id', true), '')::uuid`, áp cho cả `USING` và `WITH CHECK`. `nullif` để xử lý `''` trên connection đã từng đặt tham số (**chưa xác minh**, kiểm bằng test hành vi).
9. **`FORCE` trên mọi bảng; không role đăng nhập được nào có `BYPASSRLS`.** Backfill chạy theo từng Workspace. DDL không chịu RLS.
10. **Tra cứu chéo Workspace** chỉ qua hàm `SECURITY DEFINER` thuộc role `<svc>_lookup` (`NOLOGIN`, `BYPASSRLS`, khai báo bằng CR `DatabaseRole`), chỉ trả ID hoặc số đếm. Ở G1 có: danh sách Workspace có dữ liệu trong service; ở `workspace` thêm "Workspace của tôi" và số Workspace một Account sở hữu (BR-03). Hai trường hợp không cần hàm: BR-08 dựa vào unique `(sàn, shop_id)`, lỗi được đổi thành thông báo chung; callback OAuth đã biết Workspace từ `state` và phiên. Bảng `account` của `workspace` là bảng toàn cục, không RLS.
11. **Test N11 ba tầng**, đặt tên `N11_`/`BR04_`:
    - catalog dùng chung trong test-fixtures của `libs/workspace-access`, chạy sau Flyway (đủ RLS, policy đúng mẫu, danh sách bảng cho phép, FK ghép, quyền sở hữu hàm, quyền của `_app`);
    - hành vi trong lib, đi qua container PgBouncer `transaction` (đổi Workspace trên cùng connection, truy vấn ngoài transaction, thiếu context, `WITH CHECK`);
    - API trong từng service: ID của Workspace khác trả 404; event mang sai Workspace không làm đổi dữ liệu.
12. **ADR-0010** gộp cả mô hình role `_owner`/`_migrator`/`_app`/`_lookup`. Credential của Job migration đọc được mọi Workspace (qua `SET ROLE _lookup`); chấp nhận và đã ghi trong ADR.

### Để cho ticket khác

- Ticket 09: `workspaceId` là trường bắt buộc của envelope mọi event.
- Ticket 11: hook transaction và `ScopedValue` trong `libs/workspace-access`, artifact test-fixtures chứa test catalog và test hành vi, interceptor consumer, lint migration.
- Ticket 14: mục 8 của arc42 (cross-cutting) tóm tắt cô lập Workspace và link ADR-0010.
- Ngoài đích của map: Platform Admin đọc dữ liệu chéo Workspace (PA-*) cần một đường riêng có audit, chốt khi làm ứng dụng admin.

## Comments
- 2026-11-13: Từ ticket [05 Mô hình danh tính và Workspace trong token](05-identity-model.md#answer): Workspace của request HTTP lấy từ `MemberContext` (header `X-Workspace-Id` đã kiểm Member bằng bản sao), hoặc từ service account trong danh sách cho phép với lệnh nội bộ F3.3c. Ticket này còn chốt cách đưa nó vào RLS và Workspace trong consumer Kafka, job nền ([ADR-0008](../../../adr/0008-keycloak-authn-only-members-replicated-via-kafka.md)).
- 2026-11-13: Đã resolve, xem [Answer](#answer).
