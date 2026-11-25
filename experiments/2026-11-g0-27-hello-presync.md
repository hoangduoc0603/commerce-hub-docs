# Bản ghi: `hello` dùng `pg-main`, migration bằng Job `PreSync`

Ticket [G0-27](../.scratch/g0-platform/issues/27-hello-pg-main-presync.md), quyết định ở [ADR-0020](../adr/0020-migrations-run-as-argocd-presync-job.md). Bằng chứng theo bảng "Bằng chứng cần có" của [db-migration.md](../standards/db-migration.md) (PreSync chặn deploy, `lock_timeout`, owner đúng, không sót index hỏng) và mục "Sync waves, hooks, health" của [gitops-argocd.md](../standards/gitops-argocd.md). Đo ngày **2026-11-25** (giờ UTC) trên cụm `homelab` (Kubernetes 1.37.2, Argo CD 3.6.1, CloudNativePG 1.30.1, PostgreSQL 18.7, PgBouncer 1.25.2), chart `app` 0.3.0.

## Bối cảnh

- Runtime `hello` (1 replica, 512Mi) đăng nhập `hello_app` qua `pg-main-pooler-rw` (PgBouncer `transaction`), `sslmode=require`. Job `hello-migrate` (hook `PreSync`, wave `0`, `BeforeHookCreation`, `backoffLimit` 2, `activeDeadlineSeconds` 600) chạy cùng image ở profile `migrate`, đăng nhập `hello_migrator` thẳng `pg-main-rw`, `init-sqls`: `SET lock_timeout = '5s'; SET ROLE hello_owner;`.
- Credential: bản sao của `pg-main-hello-app` và `pg-main-hello-migrator` (namespace `postgres`) seal sang namespace `hello`. Của runtime là SealedSecret thường wave `-1`; của migrator là SealedSecret hook `PreSync` wave `-1`, `HookSucceeded`.
- ApplicationSet `services-lab`: auto-sync, `selfHeal`, `retry.limit` 5 (backoff 5 s ×2, tối đa 3 phút).

## Giả thuyết

1. SealedSecret hook `PreSync` wave `-1` được giải mã trước Job, dù SealedSecret thường wave `-1` thuộc phase Sync (Argo CD xếp phase trước wave).
2. Job tạo được schema trên `pg-main` với owner đúng; chạy lại Job không làm gì thêm.
3. Một phiên đọc giữ `AccessShareLock` làm migration cần `AccessExclusiveLock` lỗi sau khoảng 5 s; Job thử lại thành công khi khóa được nhả; tải đọc không bị chặn quá 5 s.
4. Migration lỗi trên dữ liệu thật làm Job `Failed`, sync dừng, Deployment giữ bản cũ, API không gián đoạn; `git revert` commit image đưa app về xanh.

## Cách đo

- Trạng thái Argo CD: `kubectl -n argocd get app svc-hello -o json` (`status.sync`, `status.operationState`, `status.history`), events của Application.
- Thứ tự hook: events `Unsealed` của SealedSecret trong namespace `hello`.
- Job: `kubectl -n hello get pod -l app.kubernetes.io/name=hello-migrate -w`, log từng pod, `status.startTime/completionTime` của Job.
- DB: `psql` bằng `postgres` qua socket local trong pod primary `pg-main-2` (`\dt+`, `\dp`, `\l`, `pg_index`, `pg_stat_activity`, `pg_locks`); `hello_app` qua Pooler với mật khẩu đi qua pipe.
- Tải: vòng `curl` từ Mac qua `edge` mỗi 0,5 s (AC3: GET) hoặc mỗi 2 s (AC2: GET và POST xen kẽ), ghi mã và `time_total`.
- Mức khóa của từng lệnh DDL: container `postgres:18.7`, trong một transaction đọc `pg_locks` của bảng.

## Số đo

### Đưa credential vào namespace service (bước 4, `gitops` `4a7f854`)

| Phép đo | Kết quả |
|---|---|
| `kubeseal --validate` trước push | Cả hai bản mã giải mã được; đối chứng: đổi tên thành `hello-db-appx` → `unable to decrypt` |
| Thứ tự hook | `Unsealed` của `hello-db-migrator` (hook PreSync) 15:27:58, của `hello-db-app` (wave -1 phase Sync) 15:28:00 |
| `HookSucceeded` | Sau sync thành công không còn `hello-db-migrator`; sync lỗi thì còn lại và lần sau được apply đè |
| Bản sao | sha256 của `.data` trùng bản ở `postgres`; type `kubernetes.io/basic-auth`, owner `SealedSecret/hello-db-app` |
| Một commit đổi cả chart lẫn values | Áp thành **hai** lần sync: 15:27:16 chart 0.2.0 + values mới, 15:28:02 chart 0.3.0 (values vào app ngay, `targetRevision` phải qua root cập nhật ApplicationSet) |

### Bật Job và tạo schema (bước 5, 6)

| Phép đo | Kết quả |
|---|---|
| Commit chỉ bật `migration.enabled` (`daeb43c`) | App báo `Synced` ở `daeb43c` mà **không có operation, không có Job**: hook không nằm trong diff. Phải sync tay |
| Khe giữa image mới và Job | Argo CD sync commit digest 40 s sau khi nó xuất hiện, trước commit bật Job: `POST` trả 500 (`relation … does not exist`) từ 15:43:09 tới 15:47:22 |
| Job lần đầu | 15:47:18→15:47:22 (4 s), pod chạy 1 s, exit 0; `Creating Schema History table`, `Successfully applied 1 migration … v202611250048`; JVM `Started … in 1.085 seconds` |
| Chạy lại | Job mới: `Schema "public" is up to date. No migration necessary.`, exit 0 |
| AC1 | `POST` 201 + `Location`; `GET` 200; `kubectl delete pod` → `GET` cùng ID 200; ID lạ 404 |
| AC4 | `\dt+`: `greeting`, `flyway_schema_history` thuộc `hello_owner`; `\dp greeting`: `hello_app=arwd/hello_owner`; `flyway_schema_history` không cấp cho ai; `\l hello`: `=c/hello_owner` (TEMPORARY đã thu hồi) |
| AC5 | `SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid`: 0 hàng (sau bước 6, 7 và 8) |
| Đường kết nối | `pg_stat_activity`: chỉ `hello_app`, `ssl = t`, `client_addr` = IP pod Pooler; không còn phiên `hello_migrator` sau khi Job thoát |
| Tách quyền qua Pooler | `CREATE TABLE x()` → `permission denied for schema public`; `CREATE TEMP TABLE` → `permission denied to create temporary tables` |

### Mức khóa (container `postgres:18.7`)

| Lệnh | Khóa trên bảng |
|---|---|
| `ALTER TABLE … RENAME CONSTRAINT` | `AccessExclusiveLock` |
| `ALTER TABLE … ALTER COLUMN … SET DEFAULT` | `AccessExclusiveLock` |
| `COMMENT ON TABLE` | `ShareUpdateExclusiveLock` (không xung đột với transaction đang đọc) |

### `lock_timeout` (bước 7, AC3)

Phiên `hello_app` qua Pooler `BEGIN; SELECT count(*) FROM greeting; SELECT pg_sleep(2400)` từ 16:25:18 (`AccessShareLock` granted). V2 `RENAME CONSTRAINT` merge 16:25:29, auto-sync 16:31:09.

| Mốc | Sự kiện |
|---|---|
| 16:31:21.425 | Pod 1: `Migrating schema "public" to version "202611252256 - rename greeting name check"` |
| 16:31:26.441 | Pod 1: `ERROR: canceling statement due to lock timeout` (**5,016 s**), `Changes successfully rolled back`, exit 1 |
| 16:31:30 | `pg_cancel_backend` phiên giữ khóa |
| 16:31:36 | Pod 2 (backoff ~10 s): `Successfully applied 1 migration … v202611252256`, exit 0 |
| 16:31:47 | Sync `Succeeded`, Deployment rollout image mới |

Tải: 717 `GET` (16:25–16:32), **0 lỗi**; đúng một request chậm, `16:31:21 200 5.076 s`, trùng khoảng DDL đứng trong hàng đợi khóa; các request khác < 1,1 s. `flyway_schema_history` không có dòng cho lần lỗi. Log: [`ac3-get-latency.log`](2026-11-g0-27-hello-presync/ac3-get-latency.log).

### PreSync chặn bản lỗi (bước 8, AC2)

V3: `ADD COLUMN locale text NOT NULL;` rồi `ALTER COLUMN locale SET DEFAULT 'vi';`. Bảng trống: cả hai qua, `INSERT` sau đó nhận `vi` (đo trên `postgres:18.7`); `./gradlew test` 33 test xanh, CI của PR xanh.

| Phép đo | Kết quả |
|---|---|
| Thời gian tới sync `Failed` | Auto-sync 16:43:30 → `Failed` 16:53:20 (9 phút 50 giây), `retried 5 times` |
| Số pod migrate | **18** (6 lần tạo Job × 3 pod), mỗi pod exit 1 sau ~2 s: `column "locale" of relation "greeting" contains null values` |
| Trong lúc lỗi | App `OutOfSync`, health `Healthy`; Deployment giữ digest V2; auto-sync không thử lại cùng revision sau lần cuối |
| Rollback `git revert` (`da34083`, push 16:53:38) | Trạng thái mong muốn bằng trạng thái đang chạy nên app `Synced Healthy` **không có operation**, `operationState` vẫn `Failed`, hook SealedSecret của lần lỗi còn lại. Sync tay 16:57:23→16:57:41 `Succeeded`, Job `up to date`, hook bị xóa |
| API | 16:39:30–17:01:37: **1 260 request (GET, POST), 0 lỗi**, chậm nhất 0,38 s |
| Schema sau | `flyway_schema_history` chỉ V1, V2; cột `locale` không tồn tại |
| Gỡ V3 khỏi `hello` | `migration-guard` đỏ ở PR (hello#9) và ở push `main` `b28780d`; `deploy` bị bỏ qua; `gitops` không đổi |

Log: [`ac2-api.log`](2026-11-g0-27-hello-presync/ac2-api.log), [`ac2-migrate-pods.log`](2026-11-g0-27-hello-presync/ac2-migrate-pods.log).

## Kết luận

- Giả thuyết 1–4 đúng. Migration là một bước của deploy: chạy trước khi code mới lên, cùng image, lỗi thì code mới không bao giờ chạy, và `lock_timeout` biến một DDL kẹt khóa thành 5 s chậm thay vì nghẽn không giới hạn.
- Hai điểm làm lộ trình lệch dự kiến, cùng một gốc là "hook không nằm trong diff": commit chỉ bật Job, và revert về đúng trạng thái đang chạy, đều không kích sync. Ghi vào [gitops-argocd.md](../standards/gitops-argocd.md) và runbook [migration-presync.md](../runbooks/migration-presync.md).
- Khe 500 ở bước 5 là chi phí một lần khi đưa DB vào service có sẵn. Service G1 có `migration.enabled: true` ngay từ deploy đầu nên không gặp.
- Hai tầng thử lại nhân nhau (18 pod, gần 10 phút) cho một lỗi tất định. Giữ `backoffLimit` 2 vì cần cho lỗi tạm thời (lock timeout); xét lại `retry.limit` của ApplicationSet ở G7.
- Chưa đo: memory đỉnh của pod migrate (sống 1 s, `kubectl top` không kịp), gián đoạn khi chạy hai replica. Pod cũ kết thúc ở trạng thái `Error` khi bị thay (thoát mã khác 0 sau SIGTERM), nguyên nhân **chưa xác minh**, xem ở ticket zero-downtime.
