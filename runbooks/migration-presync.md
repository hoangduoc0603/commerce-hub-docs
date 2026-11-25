# Runbook: migration chạy bằng Job `PreSync`

Bật, theo dõi và xử lý sự cố của Job migrate (chart `app` 0.3.0, `migration.*`) cho một service trên lab. Quyết định: [ADR-0020](../adr/0020-migrations-run-as-argocd-presync-job.md). Chuẩn: [db-migration.md](../standards/db-migration.md), [gitops-argocd.md](../standards/gitops-argocd.md) mục "Sync waves, hooks, health".

- Diễn tập ngày 2026-11-25 với `hello` ([G0-27](../.scratch/g0-platform/issues/27-hello-pg-main-presync.md), [bản ghi](../experiments/2026-11-g0-27-hello-presync.md)): tạo schema, chạy lại, `lock_timeout`, migration lỗi và rollback.
- Phiên bản: Argo CD 3.6.1, chart `app` **0.3.1** trở lên, Flyway 12.4.0, CloudNativePG 1.30.1 (PostgreSQL 18.7). Chart 0.3.0 cho Job dùng ServiceAccount do chart tạo, mà SA đó chưa có lúc PreSync của lần sync đầu: service mới bật migration từ deploy đầu sẽ kẹt (review G0-27, sửa ở 0.3.1).
- Thay `<svc>` bằng tên service (namespace và app `svc-<svc>` trùng tên).

## Điều cần nhớ trước

- Hook **không nằm trong diff**. Commit chỉ đổi Job hay SealedSecret hook (ví dụ chỉ bật `migration.enabled`, chỉ đổi `migration.env`) thì app vẫn `Synced`, không có sync nào chạy. Migration mới đi kèm image mới (digest đổi) nên deploy thường luôn chạy Job.
- Hook chạy ở **mọi** lần sync, kể cả sync tay và self-heal. Không có migration chờ thì Job ghi `up to date` và thoát 0 trong khoảng 1 s.
- Commit đổi `targetRevision` của chart (ở `apps/lab/services.yaml`) cùng lúc với values của service được áp thành hai lần sync: values trước, chart sau. Cần chart mới thì nâng chart ở một commit riêng trước.

## Sync tay

Tương đương nút Sync trong UI Argo CD (CLI `argocd` trên máy cần đăng nhập):

```bash
kubectl -n argocd patch application svc-<svc> --type merge -p '{"operation":{"initiatedBy":{"username":"<tên-bạn>"},"sync":{"syncStrategy":{"hook":{}}}}}'
```

```bash
kubectl -n argocd get app svc-<svc> -o json | jq -c '.status.operationState | {phase, message, startedAt, finishedAt}, (.syncResult.resources[]? | select(.hookType) | {kind, name, hookPhase})'
```

Đạt khi `phase` là `Succeeded`, hook `Job <svc>-migrate` `Succeeded`.

## Bật migration cho service đã chạy trên lab mà chưa có DB

Thứ tự (G0-27 bước 4–5):

1. Commit `gitops`: SealedSecret của hai role (`hello-db-app` thường, `hello-db-migrator` có `preSync: true`; lệnh seal ở [pg-main-them-service.md](pg-main-them-service.md) mục "Đưa mật khẩu sang namespace của service"), `secretEnv`, URL DB, khối `migration` với `enabled: false`. Image cũ bỏ qua các biến này.
2. Merge code có profile `migrate` vào repo service; chờ bot ghi digest.
3. Commit `gitops` bật `migration.enabled: true`, rồi **sync tay** (commit này chỉ đổi hook).

Từ bước 2 tới khi Job chạy, image mới chạy mà chưa có bảng: request chạm DB trả 500 (G0-27: khoảng 4 phút). Service mới thì bật `migration.enabled: true` ngay từ deploy đầu, không có khe này.

**Không** bật `migration.enabled` khi image đang chạy chưa có profile `migrate`: Job khởi động web server, không thoát, treo tới `activeDeadlineSeconds` (600 s) rồi sync lỗi.

## Xem Job

```bash
kubectl -n <svc> get job,pod -l app.kubernetes.io/component=migration
```

```bash
kubectl -n <svc> logs job/<svc>-migrate | grep -E "Database:|Current version|Migrating schema|Successfully applied|up to date|ERROR|Message"
```

Job gần nhất còn tới lần sync sau (`BeforeHookCreation`); pod lỗi của nó cũng còn. Muốn giữ log của một lần chạy trước khi sync lại thì lưu ra file trước.

## Sự cố

| Triệu chứng | Nguyên nhân thường gặp | Xử lý |
|---|---|---|
| Pod migrate lỗi `canceling statement due to lock timeout` | Một transaction dài đang giữ khóa trên bảng mà migration cần `AccessExclusive` | Job tự thử lại (`backoffLimit` 2, cách nhau 10 s, 20 s), Argo CD còn retry sync. Tìm phiên giữ khóa: `SELECT pid, usename, application_name, state, xact_start, left(query, 60) FROM pg_stat_activity WHERE datname = '<svc>' AND xact_start < now() - interval '1 minute';`, xử lý nguồn của nó; chỉ `pg_cancel_backend(pid)` khi chắc đó là phiên treo |
| App `OutOfSync`, operation `Failed` … `retried 5 times`; pod migrate lỗi lặp lại cùng một lỗi SQL | Migration sai (ví dụ `contains null values`: thêm `NOT NULL` trên bảng có dữ liệu) | Deployment vẫn chạy bản cũ, không cần gấp. Rollback: mục dưới. G0-27: 18 pod, gần 10 phút tới khi báo `Failed` |
| Job `Running` lâu, log dừng sau `Started` hoặc không có dòng Flyway nào | Image không có chế độ migrate-only, hoặc có thread non-daemon (Kafka listener, scheduler) chưa tắt trong profile `migrate` | Job bị `activeDeadlineSeconds` cắt; sửa profile trong repo service |
| Pod migrate `CreateContainerConfigError` | Secret của migrator không có (hook SealedSecret chưa giải mã được) | `kubectl -n <svc> get sealedsecret`, events `Unsealed`; bản mã sai tên hay namespace thì seal lại |
| Đã bật hoặc đổi Job mà không thấy Job chạy | Commit chỉ đổi hook | Sync tay |

## Rollback khi migration lỗi

Migration DDL trong transaction (mặc định của Flyway trên PostgreSQL) lỗi thì PostgreSQL rollback sạch, `flyway_schema_history` không có dòng cho nó. Migration không transaction (`executeInTransaction=false`) thì không: làm theo mục "Rollback" của [db-migration.md](../standards/db-migration.md) (dọn tay, `repair`).

1. Trong `gitops`: `git revert` commit của bot đã ghi digest bản lỗi; `git show --numstat HEAD` phải là `2 2 envs/lab/<svc>/values.yaml`; push.
2. Revert đưa trạng thái mong muốn về đúng trạng thái đang chạy (sync lỗi chưa áp gì), nên app báo `Synced` mà **không chạy sync nào**: `operationState` vẫn `Failed` cũ, hook SealedSecret của lần lỗi còn lại. **Sync tay** để Job của bản cũ chạy (`up to date`) và dọn hook.
3. Trong repo service: migration lỗi **chưa áp thành công ở bất kỳ môi trường nào** (kiểm `flyway_schema_history` của mọi môi trường) thì được xóa bằng commit revert. `migration-guard` sẽ đỏ ở PR và ở push vào `main`, nên lần push đó không deploy; đó là ngoại lệ có chủ đích (quyết định Q2 của G0-27). Lần push sau, guard xanh lại. Migration đã áp ở đâu đó thì không xóa: sửa bằng migration mới (forward-fix).
4. Sửa đúng ở một migration mới, qua PR như thường.

Lần merge kế tiếp vào repo service sẽ deploy đè bản rollback trong `gitops` ([gitops-argocd.md](../standards/gitops-argocd.md) mục "Rollback"), nên làm bước 3 trước khi merge thay đổi khác.
