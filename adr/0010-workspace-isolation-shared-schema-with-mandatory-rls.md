---
status: accepted
date: 2026-11-13
---

# ADR-0010: Cô lập Workspace bằng shared schema và RLS bắt buộc

Mọi service commerce-hub có DB (workspace, channel-connector, catalog, inventory, order) dùng **chung một schema cho mọi Workspace**. Mỗi bảng chứa dữ liệu của Workspace có cột `workspace_id`. Code luôn ghi rõ `workspace_id` trong truy vấn, và **PostgreSQL Row-Level Security là thứ bảo đảm** BR-04: quên một `WHERE` thì truy vấn trả 0 dòng, không lộ dữ liệu.

- Mỗi bảng có `workspace_id` bật `ENABLE` và `FORCE ROW LEVEL SECURITY`, kèm một policy cho mọi role:
  `FOR ALL USING (workspace_id = nullif(current_setting('app.workspace_id', true), '')::uuid) WITH CHECK (<cùng biểu thức>)`.
- Workspace hiện tại được đặt bằng `set_config('app.workspace_id', ?, true)` ở **đầu mỗi transaction**. Dùng `set_config` thay `SET` vì giá trị chỉ sống trong transaction, nên đi qua PgBouncer ở chế độ `transaction` vẫn an toàn. Thiếu context khi mở transaction thì ném exception. Một transaction chỉ thuộc một Workspace.
- **Không role nào đăng nhập được mà có `BYPASSRLS`.** Role `_owner`, `_migrator` và `_app` đều chịu RLS. Job nền và backfill chạy theo từng Workspace, mỗi Workspace một transaction có context riêng.
- Những tra cứu mà bản chất là chéo Workspace chỉ đi qua hàm `SECURITY DEFINER` thuộc role `<svc>_lookup` (`NOLOGIN`, `BYPASSRLS`). Hàm chỉ trả ID hoặc số đếm.
- FK giữa hai bảng có `workspace_id` viết dạng ghép `(workspace_id, x_id)`, vì kiểm FK bỏ qua RLS.

Bối cảnh và các câu hỏi đã chốt nằm ở ticket [06 Cô lập Workspace ở tầng dữ liệu](../.scratch/architecture-g0-g1/issues/06-workspace-isolation.md). Checklist cho migration ở [db-migration.md](../standards/db-migration.md).

## Phương án đã cân nhắc

- **Schema-per-tenant.** Cô lập rõ ràng, dễ xóa một Workspace (BR-05). Bị loại vì ở cỡ 1.000 Workspace × 5 service, Flyway phải chạy trên 5.000 schema mỗi lần deploy, một migration lỗi giữa chừng để lại các schema ở nhiều version khác nhau, catalog PostgreSQL phình to, và connection pool phải chuyển `search_path`. Cách này cũng không giúp gì cho truy vấn chéo Workspace của job.
- **Database-per-tenant.** Mọi điểm yếu của schema-per-tenant, cộng thêm số connection nhân theo số Workspace. Không đặt vừa một cụm `pg-main` dùng chung ([ADR-0003](0003-shared-postgres-cluster.md)).
- **Chỉ lọc ở code** (Hibernate filter hoặc `WHERE` tự viết). Bị loại vì một truy vấn quên lọc, một native query hay một repository mới viết là lộ dữ liệu, không có lớp nào phía sau chặn lại.
- **Chỉ RLS, code không ghi `workspace_id`.** Bị loại vì unique key và index ghép vẫn bắt đầu bằng `workspace_id` (BR-13), nên code dù sao cũng phải biết cột này. Ghi rõ nó trong truy vấn thì đọc code là thấy ý đồ.
- **Role `<svc>_system` có `BYPASSRLS` cho job.** Bị loại vì một credential đăng nhập được mà thấy mọi Workspace sẽ thành lối tắt cho mọi đường code "tiện tay".
- **Policy chấp nhận giá trị đặc biệt `'*'`.** Bị loại vì chỉ cần một bug đặt nhầm `'*'` là lộ toàn bộ dữ liệu.
- **App dùng user owner mặc định của CloudNativePG.** Bị loại vì owner có quyền DDL. Nếu không bật `FORCE` thì owner còn bỏ qua RLS. FAQ của CloudNativePG cũng mô tả cách tách một user đọc ghi riêng, nên đây không phải lệch khỏi chuẩn ([tra cứu 11/2026, mục 6](../research/2026-11-postgres-on-cluster.md#6-mâu-thuẫn-owner-và-rls)).

## Hệ quả

- **Bốn role cho mỗi service.** `_owner` sở hữu bảng. `_migrator` là login của Job Flyway và là thành viên của `_owner` và `_lookup`. `_app` là login của pod runtime, chỉ có quyền DML. `_lookup` sở hữu các hàm tra cứu chéo Workspace. `BYPASSRLS` chỉ superuser cấp được, nên `_lookup` được khai báo bằng CR `DatabaseRole` trong app `platform`. Vì `_migrator` phải `SET ROLE <svc>_lookup` để tạo hàm, credential của Job migration đọc được mọi Workspace. Chấp nhận vì chỉ Job `PreSync` cầm credential này và SQL của nó đi qua review; pod runtime không bao giờ có nó.
- **`FORCE` làm owner cũng thấy 0 dòng khi chưa đặt context.** Backfill dữ liệu vì thế phải chạy theo từng Workspace, giống job. Các lệnh DDL (tạo index, validate constraint) không chịu RLS.
- **Kiểm unique và FK bỏ qua RLS.** Đây vừa là lợi vừa là hại. Lợi: BR-08 (một Shop chỉ thuộc một Workspace) dựa được vào unique `(sàn, shop_id)` toàn cục; lỗi vi phạm được đổi thành thông báo chung, không nêu Workspace cũ. Hại: FK đơn cột cho phép trỏ sang Workspace khác, nên mọi FK phải viết dạng ghép.
- **Một bẫy của `current_setting`**: khi một session đã từng `set_config` cho tham số tự đặt, hết transaction thì `current_setting` trả `''` chứ không trả `NULL`, vì vậy policy phải bọc bằng `nullif`. Hành vi này **chưa xác minh** bằng nguồn chính thức (suy ra từ ngữ nghĩa của PostgreSQL), và được kiểm bằng test hành vi chạy qua PgBouncer.
- **Workspace đi vào context ở ba nơi**, cùng một `ScopedValue` trong `libs/workspace-access`: filter HTTP (từ `MemberContext`, hoặc từ service account trong danh sách cho phép ở F3.3c, [ADR-0008](0008-keycloak-authn-only-members-replicated-via-kafka.md)), interceptor của consumer Kafka (từ `workspaceId` trong envelope; thiếu thì là lỗi không retry được), và vòng lặp của job.
- **Cache trong ứng dụng phải có Workspace trong key.** RLS không bảo vệ được dữ liệu đã nằm trong bộ nhớ.
- **Xóa hẳn một Workspace (BR-05, N14)** là `DELETE ... WHERE workspace_id = ?` theo lô trên mọi bảng, không thể `DROP SCHEMA`. Đây là giá phải trả của shared schema.
- **Noisy neighbour** giữa các Workspace vẫn còn, vì mọi Workspace dùng chung bảng và chung pool. Giảm bằng cách cho job chạy theo từng Workspace và rate limit theo Workspace (C8). Đo ở Giai đoạn 5.
- **Xét lại khi** một Workspace lớn cần tách ra (số đo cho thấy nó chiếm phần lớn tải), hoặc yêu cầu pháp lý bắt dữ liệu một Workspace nằm ở DB riêng. Khi đó chuyển Workspace đó sang một database riêng mà vẫn dùng cùng schema và policy.

## Ghi chú

- 2026-11-13: Đổi tên service `tenant` thành `workspace` theo GLOSSARY ([ticket 09](../.scratch/architecture-g0-g1/issues/09-g1-contracts.md#answer), Q24). Quyết định không đổi.
- 2026-11-13: Bảng phiên của BFF trong database `seller_web` không có `workspace_id` và không bật RLS, vì phiên thuộc Account chứ không thuộc Workspace. Đây là ngoại lệ có chủ đích ([ADR-0011](0011-nextjs-bff-with-server-side-session.md)).
