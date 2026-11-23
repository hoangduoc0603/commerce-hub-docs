# 26: `hello` lưu lời chào bằng JdbcClient và Flyway

Status: ready-for-human
Blocked by: — (bỏ 19 ngày 2026-11-24, [ADR-0019](../../../adr/0019-no-contracts-repo.md); bỏ 25 ngày 2026-11-15, [ADR-0018](../../../adr/0018-self-contained-services-no-shared-library-yet.md))
Repos: services/hello, docs
Spec: [G0](../spec.md)

## Mô tả

`hello` có API tạo và đọc lời chào ~~theo OpenAPI của `contracts`~~ viết code-first (controller, DTO record, Bean Validation `name` 1–50 ký tự; sửa 2026-11-24, [ADR-0019](../../../adr/0019-no-contracts-repo.md)), lưu vào một bảng toàn cục (không `workspace_id`) bằng `JdbcClient`, ID là UUIDv7 ~~(thêm module `ids` vào `service-kit` nếu chưa có)~~ sinh ngay trong `hello`. Migration Flyway chạy bằng profile `migrate`; ~~runtime dùng chế độ "không thuộc Workspace" của hook~~. Test chạy trên PostgreSQL thật đi qua PgBouncer `transaction` (Testcontainers). ~~Bảng nằm trong allowlist của test catalog, lý do ghi ngay tại chỗ.~~

## Sửa phạm vi 2026-11-15 (bỏ `service-kit`)

Theo [ADR-0018](../../../adr/0018-self-contained-services-no-shared-library-yet.md).

- Giữ: API, `JdbcClient`, Flyway profile `migrate`, PostgreSQL 17.x và 18.x, chặn sửa migration, `bootTestRun`.
- Đổi: UUIDv7 sinh trong `hello` (tự viết hay dùng thư viện như `java-uuid-generator`, chọn khi làm, ghi lý do). Cấu hình Testcontainers (container PostgreSQL và PgBouncer, tag image ghim kèm comment trỏ tới version trong `gitops`) viết trong test của `hello`.
- Bỏ: chế độ "không thuộc Workspace" của hook, test catalog RLS (sang G1 cùng ticket 25); luật ArchUnit (layout hexagonal là quy ước).

## Mục tiêu học

- Migration có version, bất biến sau khi merge, tách quyền migrate và runtime.

## Tiêu chí nghiệm thu

- [ ] Test HTTP (MockMvc) tạo lời chào trả 201 kèm `Location`, đọc lại trả 200, ID lạ trả 404.
- ~~Test catalog từ test-fixtures pass; bỏ bảng khỏi allowlist thì đỏ.~~ Sang G1 cùng ticket 25 (2026-11-15).
- [ ] Migration chạy từ đầu trên PostgreSQL 17.x và 18.x đều xanh.
- [ ] Profile `migrate` chạy Flyway rồi thoát, không mở cổng HTTP.
- [ ] CI có bước chặn sửa migration đã merge (PR thử sửa migration cũ thì đỏ).
- ~~Luật ArchUnit pass: `domain` không import Spring, `application` không import adapter.~~ Bỏ (2026-11-15); code đặt theo quy ước hexagonal.
- [ ] `./gradlew bootTestRun` chạy `hello` trên máy với PostgreSQL và PgBouncer `transaction` của Testcontainers (class `TestHelloApplication` trong `src/test` dùng lại cấu hình container của test); `curl` tạo và đọc được lời chào. Thêm 2026-11-15 (spec G0, mục "Thứ tự làm"): compose (32) phải chờ realm của ticket 11, nên trước đó đây là cách chạy `hello` trên máy. Hỗ trợ của Boot 4.1 cho `bootTestRun` kiểm lại docs khi làm.
