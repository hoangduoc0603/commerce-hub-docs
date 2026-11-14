# 26: `hello` lưu lời chào bằng JdbcClient và Flyway

Status: ready-for-human
Blocked by: 19, 25
Repos: services/hello, docs
Spec: [G0](../spec.md)

## Mô tả

`hello` có API tạo và đọc lời chào theo OpenAPI của `contracts`, lưu vào một bảng toàn cục (không `workspace_id`) bằng `JdbcClient`, ID là UUIDv7 (thêm module `ids` vào `service-kit` nếu chưa có). Migration Flyway chạy bằng profile `migrate`; runtime dùng chế độ "không thuộc Workspace" của hook. Test chạy trên PostgreSQL thật đi qua PgBouncer `transaction` (Testcontainers). Bảng nằm trong allowlist của test catalog, lý do ghi ngay tại chỗ.

## Mục tiêu học

- Migration có version, bất biến sau khi merge, tách quyền migrate và runtime.

## Tiêu chí nghiệm thu

- [ ] Test HTTP (MockMvc) tạo lời chào trả 201 kèm `Location`, đọc lại trả 200, ID lạ trả 404.
- [ ] Test catalog từ test-fixtures pass; bỏ bảng khỏi allowlist thì đỏ.
- [ ] Migration chạy từ đầu trên PostgreSQL 17.x và 18.x đều xanh.
- [ ] Profile `migrate` chạy Flyway rồi thoát, không mở cổng HTTP.
- [ ] CI có bước chặn sửa migration đã merge (PR thử sửa migration cũ thì đỏ).
- [ ] Luật ArchUnit pass: `domain` không import Spring, `application` không import adapter.
