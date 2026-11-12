# Chuẩn: Migration cơ sở dữ liệu (Flyway trên PostgreSQL)

- Ngày tra: 2026-11-12
- Phiên bản áp dụng: Spring Boot 4.1.2 với `spring-boot-starter-flyway`, Flyway 12.4.0 (`org.flywaydb:flyway-core` + `flyway-database-postgresql`, bản do Spring Boot quản lý; Flyway mới nhất là 12.11.0, không tự nâng), PostgreSQL JDBC 42.7.14, PostgreSQL 17 (17.11) và 18 (18.6) chạy bằng CloudNativePG, Testcontainers 2.0.5, Kubernetes 1.37, Argo CD 3.6.
- Phạm vi: thư mục `src/main/resources/db/migration` của mọi service có DB, cấu hình `spring.flyway.*`, Job migration trong chart `spring-service` (template thuộc [`helm-chart.md`](helm-chart.md)), role PostgreSQL của từng service, test migration trong CI.

## Checklist

### Đặt tên và version
- [ ] Tên file `V<yyyyMMddHHmm>__<mo_ta_snake_case>.sql`, ví dụ `V202611121030__create_stock_ledger.sql`. Version phải duy nhất và sắp theo số; version theo thời gian giảm đụng nhau khi hai nhánh cùng thêm migration (Flyway Desktop cũng mặc định kiểu này). [Versioned migrations](https://documentation.red-gate.com/flyway/flyway-concepts/migrations/versioned-migrations)
- [ ] `spring.flyway.validate-migration-naming=true` và `spring.flyway.fail-on-missing-locations=true` (mặc định đều `false`). File đặt sai tên sẽ bị bỏ qua âm thầm nếu không bật. [Spring Boot – Application properties](https://docs.spring.io/spring-boot/appendix/application-properties/index.html)
- [ ] Giữ `spring.flyway.out-of-order=false` (mặc định). Nhánh merge sau mà version nhỏ hơn bản đã chạy sẽ lỗi, buộc đổi tên trước khi merge. [Spring Boot – Application properties](https://docs.spring.io/spring-boot/appendix/application-properties/index.html)
- [ ] Dữ liệu chỉ để test đặt ở `src/test/resources/db/migration`, không đóng gói vào jar/image. [Spring Boot – Database initialization](https://docs.spring.io/spring-boot/how-to/data-initialization.html)
- [ ] Không dùng repeatable migration (`R__`) cho bảng hay dữ liệu; chỉ cân nhắc cho view/function. Chạy lại theo checksum khó dự đoán khi rollout từng bước. Đây là quy ước của dự án.

### Bất biến sau khi merge
- [ ] Migration đã merge vào nhánh mặc định không bao giờ sửa hay xóa; muốn đổi thì thêm migration mới. Flyway lưu checksum để phát hiện sửa đổi; docs khuyên "roll forward". [Versioned migrations](https://documentation.red-gate.com/flyway/flyway-concepts/migrations/versioned-migrations)
- [ ] CI chặn PR sửa hoặc xóa file migration đã có: `git diff --name-only --diff-filter=MDR origin/main -- '**/db/migration/**'` phải rỗng.
- [ ] `spring.flyway.validate-on-migrate=true` (mặc định) ở mọi môi trường. Checksum lệch thì dừng, không âm thầm chạy tiếp. [Spring Boot – Application properties](https://docs.spring.io/spring-boot/appendix/application-properties/index.html)
- [ ] `spring.flyway.clean-disabled=true` (mặc định) ở mọi môi trường thật; `flyway repair` chỉ chạy theo runbook. `repair` xóa bản ghi lỗi và căn lại checksum nhưng không dọn object còn sót. [Repair](https://documentation.red-gate.com/flyway/reference/commands/repair)

### Chạy migration ở đâu
- [ ] Migration chạy bằng **Job là hook `PreSync` của Argo CD**, dùng đúng image (digest) của bản sắp deploy, ở chế độ chỉ migrate rồi thoát. PreSync lỗi thì sync dừng, Deployment mới không được áp. [Argo CD – Sync Phases and Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [ ] Pod ứng dụng đặt `spring.flyway.enabled=false`; chỉ Job có credential của role migrate. Pod runtime không cầm quyền DDL.
- [ ] Job: `restartPolicy: Never`, `backoffLimit` nhỏ (2), `activeDeadlineSeconds` (ví dụ 600), **không** đặt `ttlSecondsAfterFinished`, `hook-delete-policy: BeforeHookCreation`. `activeDeadlineSeconds` thắng `backoffLimit`; Argo CD cảnh báo TTL có thể xóa Job trước khi đọc kết quả. [Kubernetes – Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/), [Argo CD – Sync Phases and Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [ ] Job chạy lại vô hại: hook chạy ở mọi lần sync, Flyway không có migration chờ thì không làm gì. Hai Job chồng nhau (hoặc ai đó chạy tay) vẫn an toàn vì Flyway dùng lock của DB để điều phối nhiều node. [Flyway FAQ – parallel](https://documentation.red-gate.com/flyway/reference/usage/frequently-asked-questions), [Argo CD – Sync Phases and Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [ ] Chế độ migrate-only không khởi động Kafka listener, scheduler hay web server (`spring.main.web-application-type=none` + profile `migrate`), thoát với mã ≠ 0 khi lỗi. **Chưa xác minh**: cách thoát gọn nhất trong Spring Boot 4.1 (ví dụ `FlywayMigrationStrategy` + `SpringApplication.exit`); cần prototype. [Spring Boot – Database initialization](https://docs.spring.io/spring-boot/how-to/data-initialization.html)
- [ ] Job kết nối thẳng tới primary của CloudNativePG, không qua connection pooler ở chế độ transaction. Advisory lock kiểu session và lệnh `SET` cần một session cố định. **Chưa xác minh**: tên service `-rw` và hành vi PgBouncer chưa tra trong đợt này.

### Expand/contract để rollout không downtime
- [ ] Mọi migration của bản N tương thích với code bản N-1 đang chạy. Rolling update có cả hai bản cùng lúc, và rollback (git revert) đưa N-1 chạy trên schema N. Docs Flyway khuyên giữ tương thích ngược giữa DB và mọi bản code đang chạy. [Undo migrations](https://documentation.red-gate.com/flyway/flyway-concepts/migrations/undo-migrations)
- [ ] Đổi phá vỡ (đổi tên/kiểu cột, tách bảng, thêm `NOT NULL`) chia ít nhất 3 release: **expand** (thêm cột/bảng mới, nullable) → code ghi cả hai và backfill theo lô → code đọc chỗ mới → **contract** (xóa cái cũ) ở release sau khi không còn bản nào dùng. Mỗi bước là một PR, ghi mã yêu cầu. Kiểm thứ tự rollout ở [`zero-downtime.md`](zero-downtime.md).
- [ ] Backfill dữ liệu lớn không nằm trong migration DDL: chạy theo lô nhỏ, idempotent, commit từng lô (job riêng hoặc Java migration không transaction). Một transaction dài giữ khóa và chặn vacuum. [PostgreSQL – idle_in_transaction_session_timeout](https://www.postgresql.org/docs/17/runtime-config-client.html)

### Thao tác khóa bảng trong PostgreSQL
- [ ] Session migrate đặt `lock_timeout` (ví dụ `5s`) qua `spring.flyway.init-sqls=SET lock_timeout = '5s'`; Job lỗi vì timeout thì `backoffLimit` thử lại. Không có timeout thì lệnh chờ khóa vô hạn. [PostgreSQL – lock_timeout](https://www.postgresql.org/docs/17/runtime-config-client.html), [Explicit locking](https://www.postgresql.org/docs/17/explicit-locking.html)
- [ ] `statement_timeout` đặt theo từng migration (`SET statement_timeout`) cho DDL lẽ ra phải nhanh; không đặt chung cho session migrate (sẽ cắt `CREATE INDEX CONCURRENTLY` dài) và không đặt trong `postgresql.conf`. [PostgreSQL – statement_timeout](https://www.postgresql.org/docs/17/runtime-config-client.html)
- [ ] Mặc định coi `ALTER TABLE` lấy `ACCESS EXCLUSIVE` (chặn cả `SELECT`) trừ khi docs ghi khác; PR có `ALTER TABLE` trên bảng lớn phải ghi mức khóa trong mô tả. [ALTER TABLE](https://www.postgresql.org/docs/17/sql-altertable.html), [Explicit locking](https://www.postgresql.org/docs/17/explicit-locking.html)
- [ ] Index trên bảng đã có dữ liệu dùng `CREATE INDEX CONCURRENTLY`, mỗi index **một file migration** kèm `V..._x.sql.conf` chứa `executeInTransaction=false`. `CREATE INDEX` thường chặn ghi suốt lúc build; `CONCURRENTLY` không chạy được trong transaction block. [CREATE INDEX](https://www.postgresql.org/docs/17/sql-createindex.html), [Flyway – Script configuration](https://documentation.red-gate.com/flyway/reference/script-configuration)
- [ ] `spring.flyway.postgresql.transactional-lock=false`. Lock transactional mặc định của Flyway gây lỗi với `CREATE INDEX CONCURRENTLY`. [Flyway – PostgreSQL](https://documentation.red-gate.com/fd/postgresql-database-277579325.html), [Spring Boot – Application properties](https://docs.spring.io/spring-boot/appendix/application-properties/index.html)
- [ ] File index concurrently bắt đầu bằng `DROP INDEX CONCURRENTLY IF EXISTS <idx>;` rồi mới `CREATE INDEX CONCURRENTLY <idx> ...`. Lần trước lỗi để lại index `INVALID` vẫn tốn chi phí ghi; docs khuyên xóa rồi tạo lại. Sau đó chạy `repair` theo FAQ vì migration không transaction không tự rollback. [CREATE INDEX – Building Indexes Concurrently](https://www.postgresql.org/docs/17/sql-createindex.html#SQL-CREATEINDEX-CONCURRENTLY), [Flyway FAQ – repair](https://documentation.red-gate.com/flyway/reference/usage/frequently-asked-questions)
- [ ] Bảng partition (ví dụ `order` theo tháng): tạo index `CONCURRENTLY` trên từng partition, rồi tạo index trên bảng cha không `CONCURRENTLY` (chỉ là metadata). Bảng partition không hỗ trợ build concurrently. [CREATE INDEX](https://www.postgresql.org/docs/17/sql-createindex.html)
- [ ] `ADD COLUMN` chỉ với default **non-volatile** (hằng số) hoặc không default. Default volatile (`clock_timestamp()`, `gen_random_uuid()`, `uuidv7()`) hay đổi kiểu cột viết lại toàn bảng và index. [ALTER TABLE – Notes](https://www.postgresql.org/docs/17/sql-altertable.html)
- [ ] Không `ALTER COLUMN ... TYPE` trên bảng lớn trừ khi kiểu cũ binary-coercible sang kiểu mới; còn lại làm expand/contract với cột mới. [ALTER TABLE – Notes](https://www.postgresql.org/docs/17/sql-altertable.html)
- [ ] Foreign key và `CHECK` mới trên bảng có dữ liệu: migration 1 `ADD CONSTRAINT ... NOT VALID`, migration 2 `VALIDATE CONSTRAINT` (chỉ lấy `SHARE UPDATE EXCLUSIVE`). `ADD FOREIGN KEY` còn khóa `SHARE ROW EXCLUSIVE` bảng được tham chiếu. FK `NOT VALID` trên bảng partition chỉ có từ PostgreSQL 18. [ALTER TABLE](https://www.postgresql.org/docs/17/sql-altertable.html), [PostgreSQL 18 release notes](https://www.postgresql.org/docs/18/release-18.html)
- [ ] Thêm `NOT NULL` cho cột có sẵn: `CHECK (col IS NOT NULL) NOT VALID` → `VALIDATE` → `SET NOT NULL` (bỏ qua quét bảng nhờ CHECK hợp lệ) → xóa CHECK. Từ PostgreSQL 18 có `NOT NULL ... NOT VALID` trực tiếp, chỉ dùng khi mọi môi trường đã ở 18. [ALTER TABLE – SET NOT NULL](https://www.postgresql.org/docs/17/sql-altertable.html), [PostgreSQL 18 release notes](https://www.postgresql.org/docs/18/release-18.html)
- [ ] Primary key/unique mới: `CREATE UNIQUE INDEX CONCURRENTLY`, rồi `ADD CONSTRAINT ... PRIMARY KEY USING INDEX`. Cột chưa `NOT NULL` thì làm bước `NOT NULL` ở trên trước, nếu không lệnh này quét toàn bảng. [ALTER TABLE – USING INDEX](https://www.postgresql.org/docs/17/sql-altertable.html)
- [ ] Generated column ghi rõ `STORED` hoặc `VIRTUAL`. PostgreSQL 18 đổi mặc định sang virtual, cùng một câu lệnh cho kết quả khác giữa 17 và 18. [PostgreSQL 18 release notes](https://www.postgresql.org/docs/18/release-18.html)

### Rollback
- [ ] Không viết migration "down": Flyway Community không có undo (undo thuộc bản Teams), và undo không cứu được migration lỗi giữa chừng. Lỗi thì **forward-fix** bằng migration mới. [Undo migrations](https://documentation.red-gate.com/flyway/flyway-concepts/migrations/undo-migrations)
- [ ] Rollback ứng dụng = `git revert` image trong `gitops` ([`gitops-argocd.md`](gitops-argocd.md)); schema giữ nguyên nhờ tương thích ngược.
- [ ] Trước migration **contract** (xóa cột/bảng) phải có backup mới đã kiểm restore. Đây là bước duy nhất làm mất dữ liệu; docs Flyway khuyên kết hợp backup/restore đã kiểm. [Undo migrations](https://documentation.red-gate.com/flyway/flyway-concepts/migrations/undo-migrations)
- [ ] Migration có transaction (DDL thường) lỗi thì PostgreSQL tự rollback; migration không transaction lỗi thì theo runbook: dọn tay → `repair` → sửa → chạy lại. [Flyway FAQ – repair](https://documentation.red-gate.com/flyway/reference/usage/frequently-asked-questions)

### Test migration
- [ ] Integration test dùng Testcontainers `PostgreSQLContainer` + `@ServiceConnection`, image ghim cùng major.minor với production (`postgres:17.11`; thêm một lần chạy với `18.x` trước khi nâng). Flyway chạy toàn bộ migration từ DB trống trong mỗi lần CI. [Spring Boot – Testcontainers](https://docs.spring.io/spring-boot/reference/testing/testcontainers.html)
- [ ] Test nâng cấp: dựng DB ở schema của release trước (checkout tag trước, chạy migration), nạp dữ liệu mẫu, rồi áp migration mới. Lỗi trên bảng có dữ liệu (NOT NULL, unique) không lộ ra khi DB trống.
- [ ] Test tương thích ngược: chạy bộ repository test của bản N-1 trên schema N. Chứng minh rollback code an toàn.
- [ ] Lint SQL trong CI: chặn `CREATE INDEX` không `CONCURRENTLY` trên bảng đã tồn tại, `ALTER COLUMN ... TYPE`, `ADD COLUMN ... NOT NULL` không default, `ADD CONSTRAINT` thiếu `NOT VALID`, migration thiếu `ENABLE ROW LEVEL SECURITY` cho bảng mới có `tenant_id`. Script tự viết (grep); công cụ lint bên ngoài **chưa xác minh**.

### Multi-tenancy với RLS: tác động lên migration
- [ ] Migration tạo bảng có `tenant_id` thì trong **cùng file**: `ENABLE ROW LEVEL SECURITY`, `FORCE ROW LEVEL SECURITY`, `CREATE POLICY`. Bật RLS mà chưa có policy thì mặc định từ chối mọi hàng, lỗi lộ ngay khi test. [Row Security Policies](https://www.postgresql.org/docs/17/ddl-rowsecurity.html)
- [ ] Policy, `ENABLE`/`FORCE` chỉ owner bảng làm được, nên nằm trong migration (chạy bằng role owner), không nằm trong code ứng dụng. [Row Security Policies](https://www.postgresql.org/docs/17/ddl-rowsecurity.html)
- [ ] Role runtime **không** phải owner, không `BYPASSRLS`, không superuser. Owner, superuser, `BYPASSRLS` đều bỏ qua RLS (owner trừ khi `FORCE`). [Row Security Policies](https://www.postgresql.org/docs/17/ddl-rowsecurity.html)
- [ ] Biết giới hạn: kiểm FK/unique luôn bỏ qua RLS; backfill chạy bằng role owner thấy mọi tenant nên phải tự lọc `tenant_id`. [Row Security Policies](https://www.postgresql.org/docs/17/ddl-rowsecurity.html)

### Tách quyền migrate và runtime
- [ ] Mỗi service ba role: `<svc>_owner` (NOLOGIN, sở hữu schema và bảng), `<svc>_migrator` (LOGIN, thành viên `<svc>_owner`, chỉ Job dùng), `<svc>_app` (LOGIN, chỉ DML). Role khai báo bằng CR `DatabaseRole` của CloudNativePG 1.30 (docs 1.30 khuyên dùng thay `spec.managed.roles`), chỉ app `platform` được ghi CR này; mật khẩu từ Secret `kubernetes.io/basic-auth` (đưa vào bằng SealedSecret), cùng namespace với `Cluster`. Xem [ADR-0003](../adr/0003-shared-postgres-cluster.md) và [tra cứu](../research/2026-11-postgres-on-cluster.md). [CloudNativePG – API](https://cloudnative-pg.io/docs/1.30/cloudnative-pg.v1/)
- [ ] Session migrate chạy `SET ROLE <svc>_owner` (qua `spring.flyway.init-sqls`) để object mới thuộc owner chứ không thuộc migrator. **Chưa xác minh**: thứ tự `init-sqls` so với lúc Flyway tạo bảng `flyway_schema_history`; kiểm bằng `\dt` sau lần chạy đầu.
- [ ] Quyền cho runtime cấp bằng `ALTER DEFAULT PRIVILEGES FOR ROLE <svc>_owner ... GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO <svc>_app` (và `USAGE` trên sequence) trong migration đầu. Bảng mới tự có quyền, không quên `GRANT`. [ALTER DEFAULT PRIVILEGES](https://www.postgresql.org/docs/17/sql-alterdefaultprivileges.html)
- [ ] Dùng `spring.flyway.url/user/password` riêng cho Job (Flyway tự tạo DataSource riêng khi có `url` hoặc `user`). [Spring Boot – Database initialization](https://docs.spring.io/spring-boot/how-to/data-initialization.html)

## Lựa chọn và phương án đã loại

| Quyết định | Chọn | Loại | Lý do | Nguồn |
|---|---|---|---|---|
| Nơi chạy migration (**nên viết ADR**) | Job hook `PreSync` của Argo CD | (a) Lúc app start; (b) initContainer; (c) Job wave âm không phải hook | (a) pod runtime phải giữ quyền DDL, migration dài làm startupProbe giết pod, mọi replica cùng thử. (b) vẫn chạy theo từng pod và pod vẫn mang credential migrate. (c) Job thường khó áp lại khi đổi image; hook được tạo lại mỗi lần sync. PreSync chặn deploy khi migration lỗi. Giá phải trả: gắn với Argo CD, `helm install` tay không chạy hook này | [Sync Phases and Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/), [Flyway FAQ](https://documentation.red-gate.com/flyway/reference/usage/frequently-asked-questions), [Spring Boot – Database initialization](https://docs.spring.io/spring-boot/how-to/data-initialization.html) |
| Rollback DB | Forward-fix + expand/contract | Undo migration | Undo chỉ có ở bản Teams và không xử lý được migration lỗi giữa chừng | [Undo migrations](https://documentation.red-gate.com/flyway/flyway-concepts/migrations/undo-migrations) |
| Kiểu version | Timestamp | Số nguyên tăng dần | Ít đụng version giữa các nhánh song song | [Versioned migrations](https://documentation.red-gate.com/flyway/flyway-concepts/migrations/versioned-migrations) |
| Phân quyền DB (**nên viết ADR**, cùng ADR multi-tenancy) | 3 role owner/migrator/app, runtime chịu RLS | App dùng user owner mặc định của CloudNativePG | Owner bỏ qua RLS và có quyền DDL. Docs CloudNativePG lại khuyên app kết nối bằng owner, nên đây là lệch có chủ đích | [Row Security Policies](https://www.postgresql.org/docs/17/ddl-rowsecurity.html), [CloudNativePG – Bootstrap](https://cloudnative-pg.io/docs/1.29/bootstrap/) |
| Bản Flyway | Bản Spring Boot quản lý (12.4.0) | Tự nâng 12.11.0 | Tránh lệch với auto-configuration; nâng theo Spring Boot | [Spring Boot – Dependency versions](https://docs.spring.io/spring-boot/appendix/dependency-versions/coordinates.html) |

## Lệch chuẩn có chủ đích ở home lab
- **Backup trước contract** dùng plugin Barman Cloud của CloudNativePG, đích là object store RustFS trên VM `gw` ([tra cứu](../research/2026-11-postgres-on-cluster.md#4-backup-và-khôi-phục)). `gw` nằm cùng máy vật lý với cụm: mất máy bàn là mất backup; chấp nhận vì dữ liệu lab tạo lại được từ simulator.
- **Một cụm PostgreSQL cho nhiều service** (mỗi service một database và bộ role riêng) thay vì mỗi service một cụm, do RAM. Ranh giới sở hữu dữ liệu giữ bằng role, không bằng cụm.

## Bằng chứng cần có

| Chứng minh | Cách đo | Đạt khi |
|---|---|---|
| Migration chạy từ đầu | CI: `./gradlew check` với Testcontainers 17.11 và 18.x | Xanh cả hai; ghi thời gian |
| Bất biến | PR thử sửa một migration cũ | CI đỏ ở bước kiểm diff |
| Khóa không chặn tải | Bảng ≥ 1 triệu hàng, chạy tải đọc/ghi (k6) trong lúc áp `CREATE INDEX` thường rồi `CONCURRENTLY`; theo dõi `pg_stat_activity` `wait_event_type = 'Lock'` | Có số: thời gian chặn và p99 của từng cách; `CONCURRENTLY` không có request lỗi |
| `lock_timeout` hoạt động | Mở transaction giữ khóa bảng, chạy Job migrate | Job lỗi `lock timeout` trong ~5 s, thử lại thành công sau khi nhả khóa; tải không bị chặn dây chuyền |
| Không sót index hỏng | `SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid;` | 0 hàng |
| PreSync chặn deploy | Đẩy migration lỗi cố ý | Job `Failed`, Deployment giữ bản cũ, app báo sync lỗi |
| Rollback | Deploy N (có expand) → `git revert` về N-1 trong lúc chạy tải | 0 request lỗi (cách đo ở [`zero-downtime.md`](zero-downtime.md)) |
| Tách quyền | Đăng nhập `<svc>_app`: `CREATE TABLE x()`; `SELECT` khi chưa đặt tenant | `permission denied`; 0 hàng |
| Owner đúng | `\dt+` và `\dp` sau migration | Bảng thuộc `<svc>_owner`, `<svc>_app` có đúng quyền DML |

Kết quả ghi vào `docs/experiments/`.

## Nguồn
- Flyway: [Versioned migrations](https://documentation.red-gate.com/flyway/flyway-concepts/migrations/versioned-migrations), [Undo migrations](https://documentation.red-gate.com/flyway/flyway-concepts/migrations/undo-migrations), [PostgreSQL database](https://documentation.red-gate.com/fd/postgresql-database-277579325.html), [PostgreSQL transactional lock](https://documentation.red-gate.com/fd/flyway-postgresql-transactional-lock-setting-277579114.html), [Script configuration](https://documentation.red-gate.com/flyway/reference/script-configuration), [Repair](https://documentation.red-gate.com/flyway/reference/commands/repair), [FAQ](https://documentation.red-gate.com/flyway/reference/usage/frequently-asked-questions), [Mixed setting (mã nguồn docs 12.11.0)](https://github.com/flyway/flyway/blob/flyway-12.11.0/documentation/Reference/Configuration/Flyway%20Namespace/Flyway%20Mixed%20Setting.md)
- Spring Boot 4.1.2: [Database initialization](https://docs.spring.io/spring-boot/how-to/data-initialization.html), [Application properties](https://docs.spring.io/spring-boot/appendix/application-properties/index.html), [Dependency versions](https://docs.spring.io/spring-boot/appendix/dependency-versions/coordinates.html), [Testcontainers](https://docs.spring.io/spring-boot/reference/testing/testcontainers.html)
- PostgreSQL: [Versioning policy](https://www.postgresql.org/support/versioning/), [CREATE INDEX](https://www.postgresql.org/docs/17/sql-createindex.html), [ALTER TABLE](https://www.postgresql.org/docs/17/sql-altertable.html), [Explicit locking](https://www.postgresql.org/docs/17/explicit-locking.html), [Client connection defaults](https://www.postgresql.org/docs/17/runtime-config-client.html), [Row Security Policies](https://www.postgresql.org/docs/17/ddl-rowsecurity.html), [ALTER DEFAULT PRIVILEGES](https://www.postgresql.org/docs/17/sql-alterdefaultprivileges.html), [PostgreSQL 18 release notes](https://www.postgresql.org/docs/18/release-18.html)
- [Kubernetes – Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/), [Argo CD – Sync Phases and Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- CloudNativePG: [API reference 1.30](https://cloudnative-pg.io/docs/1.30/cloudnative-pg.v1/), [Bootstrap](https://cloudnative-pg.io/docs/1.29/bootstrap/)
