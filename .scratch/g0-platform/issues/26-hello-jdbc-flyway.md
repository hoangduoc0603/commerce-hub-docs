# 26: `hello` lưu lời chào bằng JdbcClient và Flyway

Status: resolved
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

- [x] Test HTTP (MockMvc) tạo lời chào trả 201 kèm `Location`, đọc lại trả 200, ID lạ trả 404. `GreetingApiTests`, `GreetingApiErrorTests` (thêm 400 cho `name` sai, ID sai dạng, NUL, surrogate lẻ).
- ~~Test catalog từ test-fixtures pass; bỏ bảng khỏi allowlist thì đỏ.~~ Sang G1 cùng ticket 25 (2026-11-15).
- [x] Migration chạy từ đầu trên PostgreSQL 17.x và 18.x đều xanh. `MigrationCompatibilityTests` với 17.11 và 18.7, 52–160 ms ([bản ghi](../../../experiments/2026-11-g0-26-hello-db.md)).
- [x] Profile `migrate` chạy Flyway rồi thoát, không mở cổng HTTP. `MigrateProfileTests`; process thật exit 0 (migrate, chạy lại), exit 1 (sai mật khẩu), `lsof` không thấy cổng nào ([bản ghi](../../../experiments/2026-11-g0-26-hello-db.md)).
- [x] CI có bước chặn sửa migration đã merge (PR thử sửa migration cũ thì đỏ). Job `migration-guard`; PR thử #4 (sửa V1) đỏ, #5 (thêm V2) xanh ([bản ghi](../../../experiments/2026-11-g0-26-hello-db.md)).
- ~~Luật ArchUnit pass: `domain` không import Spring, `application` không import adapter.~~ Bỏ (2026-11-15); code đặt theo quy ước hexagonal.
- [x] `./gradlew bootTestRun` chạy `hello` trên máy với PostgreSQL và PgBouncer `transaction` của Testcontainers (class `TestHelloApplication` trong `src/test` dùng lại cấu hình container của test); `curl` tạo và đọc được lời chào. Thêm 2026-11-15 (spec G0, mục "Thứ tự làm"): compose (32) phải chờ realm của ticket 11, nên trước đó đây là cách chạy `hello` trên máy. Hỗ trợ của Boot 4.1 cho `bootTestRun` kiểm lại docs khi làm. Kiểm 2026-11-25: `TestHelloApplication` dùng `SpringApplication.from(...).with(TestcontainersConfiguration.class)`; app lên 5,5 s, `POST` 201, `GET` theo `Location` 200, dừng app thì container bị xóa.

## Quyết định khi làm (chốt 2026-11-24)

- **Nhánh:** làm trên nhánh `g0-26` của `hello`, PR để CI chạy. Merge ở bước đầu của ticket 27, khi values DB trong `gitops` đã sẵn: push vào `main` là deploy lên lab (ticket 24), mà có starter JDBC không có `spring.datasource.url` thì pod lỗi khởi động.
- **UUIDv7:** `com.fasterxml.uuid:java-uuid-generator` 5.2.0 (`Generators.timeBasedEpochGenerator()`, tăng dần cả trong cùng millisecond). Loại: tự viết theo RFC 9562 (phải tự lo đơn điệu), `uuidv7()` của PostgreSQL 18 (17 không có, spec muốn ID sinh trong service).
- **Chặn sửa migration:** job trong `ci.yml` của `hello` (service G1 chép template là có), chạy cả PR (`base..head`) lẫn push vào `main` (`before..sha`); job `deploy` `needs` job này, vì ruleset không bắt status check. Loại: thêm vào `java-service.yml` của `platform` (phải release, áp cả service không có DB).
- **Hình dạng kết nối:** `spring.datasource.*` luôn là runtime (`hello_app` qua PgBouncer), `spring.flyway.*` luôn là migrate (`hello_migrator` nối thẳng). Giống nhau ở test, `bootTestRun`, profile `migrate` và lab.
- **Image test:** `postgres:18.7` và `17.11` (lab chạy 18.7 theo `gitops/infra/pg-main/cluster.yaml`; `db-migration.md` còn ghi 17.11, sửa ở bước 11), PgBouncer dùng đúng image CNPG `1.25.2` của `gitops/infra/pg-main/pooler.yaml`.

## Lộ trình

- [x] 1. Nhánh `g0-26`. Thêm starter JDBC, driver PostgreSQL, Testcontainers; `TestcontainersConfiguration` với `postgres:18.7` và script bốn role giống `gitops/infra/pg-main/hello.yaml`; `DynamicPropertyRegistrar` cho DataSource (`hello_app`, nối thẳng tạm thời). Kiểm: `./gradlew test` xanh, test `current_user = hello_app`, `server_version` bắt đầu bằng `18.7`.
- [x] 2. PgBouncer `transaction` (image CNPG 1.25.2) đứng trước DataSource. Kiểm: test chạy cùng một query 10 lần (vượt `prepareThreshold=5` của pgjdbc) xanh qua PgBouncer.
- [x] 3. Starter Flyway (`spring.flyway.enabled=false` ở `application.yaml`, test bật lại), migration đầu tạo `greeting`, `ALTER DEFAULT PRIVILEGES`, `REVOKE TEMPORARY`; cấu hình theo checklist `db-migration.md` (`validate-migration-naming`, `fail-on-missing-locations`, `postgresql.transactional-lock=false`, `init-sqls`). Kiểm: bảng và `flyway_schema_history` thuộc `hello_owner`; `hello_app` `CREATE TABLE` bị `permission denied`.
- [x] 4. Test migration từ đầu trên 17.11 và 18.7 (`@ParameterizedTest`, Flyway API). Kiểm: hai case xanh, ghi thời gian.
- [x] 5. UUIDv7 (red → green). Kiểm: version 7, variant RFC 9562, 1 000 ID tăng dần.
- [x] 6. Test MockMvc tạo và đọc lời chào, rồi domain, use case, port, adapter `JdbcClient`, controller DTO record. Kiểm: 201 + `Location`, `GET` 200, JsonPath đúng tên field.
- [x] 7. Starter Validation; ID lạ → 404, `name` rỗng hoặc > 50 ký tự → 400. Kiểm: test MockMvc xanh.
- [x] 8. `TestHelloApplication` dùng lại cấu hình container. Kiểm: `./gradlew bootTestRun`, `curl` tạo rồi đọc được lời chào.
- [x] 9. Profile `migrate`: web `none`, Flyway bật, thoát. Kiểm: test context không phải web và schema đã có; `java -jar ... --spring.profiles.active=migrate` → `echo $?` là 0, sai mật khẩu ≠ 0, không cổng nào nghe.
- [x] 10. Job `migration-guard` trong CI, `deploy` cần nó. Kiểm: PR sửa V1 đỏ, PR thêm V2 xanh.
  - Phát sinh 2026-11-25: CI của PR thử lộ lỗi `ci / image / build`. Training run AOT trong Dockerfile khởi động app, mà từ bước 3 bean `JdbcClient` cần URL DataSource ("Failed to determine a suitable driver class"). Dockerfile đã ghi trước việc này cho ticket 26 nhưng lộ trình bỏ sót. Sửa: `-Dspring.datasource.url=jdbc:postgresql://aot-training.invalid:5432/hello` chỉ cho lệnh training. Kiểm: image chạy `-XX:AOTMode=on` ở profile `migrate` (exit 0) và runtime (POST 201), khởi động 0,6 s so với 1,3 s không cache.
- [x] 11. Docs: tick `db-migration.md`, hai điểm chưa xác minh thành kết quả, sửa 17.11 → 18.7, số đo vào `docs/experiments/`, ma trận truy vết.
  - Làm 2026-11-25: [db-migration.md](../../../standards/db-migration.md) tick 18 mục `hello` đã đạt, ba điểm chưa xác minh (thứ tự `init-sqls`, cách thoát profile `migrate`, PgBouncer và `pg-main-rw`) thành kết quả có nguồn, sửa production 17.11 → 18.7, ghi lệch `@ServiceConnection`, thêm hai dòng lựa chọn (chặn sửa migration, cách thoát). [container-image.md](../../../standards/container-image.md) thêm cách URL `.invalid` cho training run. Số đo ở [bản ghi G0-26](../../../experiments/2026-11-g0-26-hello-db.md), link từ [2026-11-g0.md](../../../experiments/2026-11-g0.md). Ma trận truy vết: không có dòng tương ứng (ticket hạ tầng của `hello`, không mã F/N; như G0-23, G0-24).
- [x] 12. Kết ticket (2026-11-25): `./gradlew test` 33 test xanh; `actionlint` sạch; `code-review` (mức high) trên `origin/main...g0-26` ra 5 phát hiện.
  - Đã sửa: `name` chứa NUL qua được `@Size` nhưng PostgreSQL `text` từ chối 0x00, API trả 500; surrogate lẻ thì trả 201 và lưu sai. Thêm `@Pattern(regexp = "[^\\x00\\p{Cs}]*")`, test NUL và surrogate lẻ đỏ trước khi sửa, emoji vẫn nhận (commit `06720c8`).
  - Để lại, không chặn: `migration-guard` chỉ theo dõi `src/main/resources/db/migration` và bỏ qua kiểu đổi `T` (sửa khi service đầu tiên có Java migration); chưa chặn hai nhánh merge ngược thứ tự timestamp (G1, đã ghi ở db-migration.md); `MigrationCompatibilityTests` chép tay `init-sqls` (đổi `application.yaml` thì đổi cả test, comment đã ghi); `bootTestRun` mở cổng PostgreSQL trên `0.0.0.0` với superuser `test`/`test` (mặc định của Testcontainers, chỉ máy dev).
  - Ma trận truy vết: không có dòng tương ứng (ticket hạ tầng của `hello`, không mã F/N; như G0-23, G0-24).
  - Nhánh `g0-26` chưa merge vào `main` (quyết định Q1): merge ở bước đầu ticket 27, khi values DB trong `gitops` đã sẵn.

## Bài học

- Test xanh không có nghĩa là migration an toàn: test luôn migrate trên DB trống, nên sửa V1 vẫn xanh (PR thử #4: `ci / check` xanh, chỉ `migration-guard` đỏ). Bất biến "không sửa migration đã merge" phải có lớp chặn riêng bằng `git diff --diff-filter=MDR base...head`. Ba chấm để không báo oan khi `main` có migration mới sau lúc rẽ nhánh. Vì ruleset không bắt status check, `deploy` phải `needs` job này.
- Muốn test có giá trị thì môi trường test phải giống lab ở đúng chỗ có rủi ro. `@ServiceConnection` cho test đăng nhập superuser, sẽ xanh cả ở chỗ lab báo `permission denied`. Test thật nên đi qua PgBouncer `transaction` bằng `hello_app` và migrate bằng `hello_migrator` với `SET ROLE hello_owner`. Mỗi lớp bảo vệ có một đối chứng âm (bỏ `SET ROLE`, `max_prepared_statements = 0`, bỏ `@Valid`, `uuidv7()` trên 17) để chứng minh test bắt được lỗi.
- Chỗ vấp: (1) `spring.flyway.enabled` đặt trong `DynamicPropertyRegistrar` bị bỏ qua âm thầm, vì `@Conditional` được tính trước. (2) `init-sqls` bị nối thành một chuỗi nên mỗi câu cần `;`. (3) Thêm starter JDBC làm hỏng training run AOT trong Dockerfile. Test không thấy lỗi này, chỉ CI build image của PR mới lộ; sửa bằng URL `.invalid` chỉ cho lệnh training. (4) `@Size` đếm đơn vị UTF-16, nên NUL và surrogate lẻ lọt qua và thành 500 hoặc lưu sai; `code-review` bắt được.
- Câu chuyện kể được: "Service có hai kết nối DB với hai role. Runtime chỉ có DML, đi qua PgBouncer `transaction` (prepared statement vẫn chạy nhờ `max_prepared_statements`). Migration chạy bằng chính image đó ở profile `migrate`: nối thẳng primary, `SET ROLE` sang owner, migrate xong thì thoát mã 0 trong khoảng 2 s, lỗi thì mã 1, không mở cổng nào. Migration đã merge bị CI chặn sửa. Toàn bộ được test trên PostgreSQL 17 và 18 với đúng role, pooler và image của lab, và mỗi lớp bảo vệ đều có đối chứng âm chứng minh test bắt được lỗi."
