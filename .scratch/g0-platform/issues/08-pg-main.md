# 08: `pg-main` trên CloudNativePG với role khai báo

Status: resolved
Blocked by: 04
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

CloudNativePG 1.30.1 chạy cluster `pg-main` PostgreSQL 18, 1 instance, requests = limits, cộng một Pooler PgBouncer `transaction`. Database và bốn role `_owner`/`_migrator`/`_app`/`_lookup` khai báo bằng CR trong app `platform`, mật khẩu là `SealedSecret`. Ticket này tạo database `keycloak` và `hello`. Theo [ADR-0003](../../../adr/0003-shared-postgres-cluster.md), [ADR-0004](../../../adr/0004-single-instance-by-default-on-homelab.md), [ADR-0010](../../../adr/0010-workspace-isolation-shared-schema-with-mandatory-rls.md), [db-migration.md](../../../standards/db-migration.md).

_Ghi chú 2026-11-15 (review): "requests = limits" áp cho `pg-main` (QoS `Guaranteed`). Pooler và operator cố ý chỉ đặt memory requests = limits, CPU chỉ request (QoS `Burstable`), lý do ghi trong `pooler.yaml` và [postgres-cnpg.md](../../../standards/postgres-cnpg.md)._

## Mục tiêu học

- Postgres qua operator: CR `Cluster`, role và database khai báo, Pooler.
- PDB của operator tương tác với `kubectl drain` khi chỉ có 1 instance.

## Tiêu chí nghiệm thu

- [x] `pg-main` `Healthy` trong Argo CD; CR `Cluster` (và namespace `postgres`) có `Prune=false,Delete=false`; PVC được bảo vệ qua ownerReference `controller: true` về `Cluster`. _Sửa 2026-11-15 (quyết định E): Argo CD không theo dõi PVC nên annotation trên PVC vô tác dụng._
- [x] Đăng nhập `hello_app` qua Pooler: `CREATE TABLE x()` bị `permission denied`.
- [x] `hello_lookup` là `NOLOGIN`; không role đăng nhập được nào **của service hoặc Keycloak** có `BYPASSRLS`; role hệ thống `postgres` không đăng nhập được qua mạng (`enableSuperuserAccess: false`). _Sửa 2026-11-15 (quyết định D): `postgres` có `rolbypassrls = true` sẵn nên câu cũ luôn fail._
- [x] Thêm database thứ ba chỉ bằng một commit (ghi vào runbook "thêm service").
- [x] Thử `kubectl drain` node đang chạy `pg-main`: ghi PDB có chặn không và cách xử lý vào runbook; nếu phải lệch chuẩn thì ghi vào ADR-0004.

## Lộ trình

Duyệt ngày 2026-11-15. Làm theo `/huong-dan`: chủ repo là driver từ bước 2; bước 1 là tài liệu, Claude viết. Hiện trạng lúc lập: cụm 3 node K8s 1.37.2 `Ready`; chưa có namespace `postgres`, chưa cài CNPG; ngân sách ([ticket 04](../../architecture-g0-g1/issues/04-resource-budget.md#answer)) `pg-main` 1 024 Mi, operator 200 Mi, Pooler 64 Mi.

Quyết định khi duyệt:
- (A) Chặn CONNECT chéo database bằng `pg_hba` theo database × role trong `Cluster.spec.postgresql.pg_hba`, không dựa vào migration của service.
- (B) Database `app` do bootstrap `initdb` tạo giữ nguyên, không đưa Secret `pg-main-app` cho ai. Mọi database dùng thật tạo bằng CR `Database`, nên thêm database luôn cùng một kiểu.
- (C) Keycloak chỉ có một role LOGIN `keycloak` sở hữu database (Keycloak tự migrate, không dùng RLS). Ghi lý do vào runbook.
- (D) Tiêu chí `BYPASSRLS` giới hạn ở role của service và Keycloak, cộng kiểm `postgres` không đăng nhập được qua mạng.
- (E) "PVC có `Delete=false`": tra ở bước 1 xem gắn annotation lên PVC qua `inheritedMetadata` được không; nếu không thì ghi cơ chế thật (ownerReference về `Cluster` + `Delete=false` trên `Cluster`) và sửa tiêu chí.

- [x] 1. Chuẩn `docs/standards/postgres-cnpg.md` (Claude viết, chủ repo duyệt): checklist có nguồn docs CNPG 1.30.1, tra lại `DatabaseRole`, `Pooler`, PDB, `inheritedMetadata`, `pg_hba`. Kiểm: checklist có nguồn; điểm chưa xác minh liệt kê.
  - Chủ repo duyệt 2026-11-15. Phát hiện: (1) docs nói thẳng cluster 1 instance thì PDB **chặn** drain và khuyên `enablePDB: false` cho dev; có quy trình tạm lên 2 instance để switchover; (2) operator luôn thêm `host all all all scram-sha-256` sau luật người dùng, nên `pg_hba` phải kết thúc bằng `reject`; (3) `Delete=false` qua `inheritedMetadata` vô tác dụng vì Argo CD không theo dõi PVC; (4) nhãn `cnpg.io/reload` phải nằm ở template của SealedSecret; (5) thêm vào lộ trình: project `commerce` chặn group `postgresql.cnpg.io` (bước 2).
- [x] 2. App `cloudnative-pg` (operator): CRD vendor `Prune=false,Delete=false`, image ghim digest, resources. Kiểm: `Synced/Healthy`; `kubectl get crd | grep cnpg`; RAM.
  - Chủ repo giao Claude làm. Kết quả: gitops `4f83d98`; push → `Synced/Healthy` sau 30 s. 11 CRD tách từ asset `cnpg-1.30.1.yaml`, so với `templates/crds/crds.yaml` của chart 0.29.1 thì giống hệt trừ annotation `helm.sh/resource-policy`; đều mang `Prune=false,Delete=false`. Image ghim digest bằng `image.tag: 1.30.1@sha256:923c267e…` (chart không có field digest), chuỗi này cũng vào `OPERATOR_IMAGE_NAME`. RAM 30 Mi khi chưa có `Cluster` (limit 200 Mi; đo lại ở bước 3). QoS `Burstable` vì CPU không đặt limit, đúng ý (chỉ memory requests = limits cho operator). Webhook có `caBundle` do operator tự điền, app không `OutOfSync` sau 75 s. 0 dòng log lỗi. Project `platform` thêm repo chart; project `commerce` chặn group `postgresql.cnpg.io`. Chưa kiểm chữ ký cosign của asset (máy chưa có cosign).
- [x] 3. Namespace `postgres` và `Cluster pg-main`: PG 18 `standard`, 1 instance, `requests = limits`, `local-path`, superuser tắt, `Delete=false`. Kiểm: Argo `Healthy`; `kubectl cnpg status`; QoS `Guaranteed`.
  - Chủ repo giao Claude làm. Kết quả: gitops `d239b05`; push → app `pg-main` `Synced/Healthy` sau 55 s (kéo image PG 15 s, 225 MB). PostgreSQL **18.7** (tag bất biến `18.7-202611122305-standard-trixie`, ghim digest; tra cứu cũ ghi 18.6). `Cluster in healthy state`, pod `pg-main-1` trên `k8s-w1`, QoS `Guaranteed` (1 CPU, 1 024 Mi), `shared_buffers` 256MB. RAM lúc rảnh: PostgreSQL 55 Mi, operator 39 Mi.
  - Pod Security `restricted` của namespace cho qua: container `postgres` chạy non-root, seccomp `RuntimeDefault`, drop ALL, root filesystem chỉ đọc. Init container `bootstrap-controller` dùng image operator ghim digest (qua `OPERATOR_IMAGE_NAME`, bước 2).
  - Quyết định E đã kiểm: PVC `pg-main-1` có ownerReference `controller: true` trỏ về `Cluster pg-main`. Bảo vệ thật là `Prune=false,Delete=false` trên `Cluster` (thêm cả `Prune=false` so với lộ trình).
  - Superuser: `postgres` có `rolpassword` NULL; đăng nhập qua `pg-main-rw` bằng mật khẩu bất kỳ → `password authentication failed`. Role đăng nhập được có `rolbypassrls`: chỉ `postgres` (tiêu chí D).
  - Chỉ có **1** PDB `pg-main-primary` (`minAvailable: 1`, `ALLOWED DISRUPTIONS 0`); docs nói mỗi Cluster 2 PDB, PDB cho replica không sinh khi chỉ có 1 instance. Thí nghiệm drain ở bước 8.
  - `pg_hba_file_rules` mặc định: `local all cnpg_metrics_exporter peer` đứng đầu, nên dòng `reject` ở bước 5 không chặn metrics exporter (gỡ một điểm chưa xác minh của chuẩn).
  - Argo CD 3.6.1 có health Lua sẵn cho `Cluster`, `Database` (có trong mã nguồn tag `v3.6.1`), không có cho `Pooler`, `DatabaseRole`. Argo CD 3.x không ghi health từng resource vào `status.resources`.
  - Chưa cài plugin `kubectl cnpg` trên Mac; trạng thái đọc bằng `kubectl get cluster`.
- [x] 4. Database `hello`, 4 `DatabaseRole`, 2 SealedSecret `basic-auth`, health check Lua cho `DatabaseRole`. Kiểm: `pg_roles`: `hello_lookup` `NOLOGIN`, không role LOGIN của service có `rolbypassrls`.
  - Chủ repo giao Claude làm. Kết quả: gitops `68854bf` (health Lua, app `argocd` `Synced/Healthy`) rồi `da82fd6` (`infra/pg-main/hello.yaml`, hai SealedSecret); app `pg-main` `Synced/Healthy` sau 10 s, qua wave 1 → 2 → 3. Bốn `DatabaseRole` và `Database hello` `APPLIED true`.
  - `pg_authid`: `hello_owner`, `hello_lookup` NOLOGIN, mật khẩu NULL; chỉ `hello_lookup` có `rolbypassrls`; `hello_migrator` (limit 2), `hello_app` (limit 10) lưu `SCRAM-SHA-256`. `hello_migrator` là thành viên `hello_owner`, `hello_lookup` (`inherit` và `set` đều true) mà vẫn `rolbypassrls = f`: thuộc tính role không di truyền. Role LOGIN có `rolbypassrls` trong cả cụm: chỉ `postgres` (tiêu chí D). Database `hello` thuộc `hello_owner`.
  - Mật khẩu: `openssl rand -hex 32` pipe thẳng sang `kubeseal`, không chạm đĩa; nhãn `cnpg.io/reload` có trên Secret sinh ra (`kubeseal` chép metadata của Secret đầu vào vào template). Plaintext không lưu ở đâu ngoài Secret trong cụm; bản sao cho namespace `hello` (G0-27) seal từ Secret đó.
  - `connectionLimit`: 97 kết nối dùng được (100 − 3 reserved); mỗi service 10 + 2 = 12, 6 database kiểu này 72, còn 25 cho Keycloak.
  - Health Lua thử offline bằng `argocd admin settings resource-overrides health` với 6 trạng thái giả (đúng cả 6), rồi trên object thật: `DatabaseRole` tạm ngoài Git có `inRoles: [no_such_role]` → `applied=false`, Lua trả **Progressing** kèm `role "no_such_role" does not exist`; sửa spec một role đang Healthy cho hỏng → `observedGeneration` đứng yên, cũng **Progressing**. Đúng như check `Database` có sẵn, nhưng nghĩa là commit role sai làm app kẹt Progressing chứ không đỏ (ghi vào chuẩn). Role thử đã xóa, `pg_roles` không còn.
  - Còn cho bước 5: `\l hello` cột Access privileges rỗng, tức PUBLIC vẫn có `CONNECT` và `TEMPORARY` mặc định. `pg_hba` chặn được CONNECT chéo database, không chặn TEMPORARY trong chính database của role; cân nhắc khi khóa ở bước 5.
- [x] 5. Khóa database: `pg_hba` theo database × role, `connectionLimit` từng role. Kiểm: `hello_app` nối DB `keycloak`/`app` bị từ chối.
  - Chủ repo giao Claude làm. Kết quả: gitops `359a90e` (`spec.postgresql.pg_hba`: `hostssl hello hello_migrator,hello_app all scram-sha-256`, `host all all all reject`); app `pg-main` `Synced/Healthy` 11 s sau push. Hai luật thành dòng 20–21, trước dòng mặc định 28 của operator.
  - Trước khóa: `hello_app` vào được `hello`, `app`, `postgres`, và vào `hello` không TLS. Sau khóa (psql trong pod nối `pg-main-rw`): `hello` vào được (`ssl = t`); `app`, `postgres`, `keycloak` (chưa tồn tại) đều `pg_hba.conf rejects connection ... SSL encryption`; `hello` với `sslmode=disable` → `rejects connection ... no encryption`; `hello_migrator` vào `app` và role bootstrap `app` vào `app` đều bị từ chối. Nối từ `127.0.0.1` (đường port-forward) vào `hello` vẫn được.
  - Reload, không restart: `pg_conf_load_time()` đổi 7 s sau push; `pg_postmaster_start_time()` và `restartCount 0` giữ nguyên. Metrics exporter vẫn chạy: `cnpg_collector_up 1`, `last_collection_error 0`. Log operator 0 lỗi.
  - `connectionLimit`: 3 kết nối `hello_migrator` song song → 2 thành công, kết nối thứ 3 `too many connections for role "hello_migrator"`.
  - Phát hiện: siết `pg_hba` không cắt phiên đang mở. Phiên DataGrip `hello_app` vào database `postgres` mở 1 phút trước reload vẫn sống sau reload (`pg_stat_activity`). Ghi vào chuẩn cách cắt phiên vi phạm khi thu hồi quyền thật.
  - TEMPORARY của PUBLIC: không xử lý ở nền tảng (là quyền bên trong database, owner mới thu hồi được); ghi thành mục cân nhắc cho migration đầu trong `db-migration.md` (ticket 27).
- [x] 6. `Pooler` `transaction` 1 pod, health check Lua. Kiểm: `hello_app` qua Pooler: `CREATE TABLE x()` → `permission denied`.
  - Chủ repo giao Claude làm. Kết quả: gitops `1b03f66` (health Lua `Pooler` trong `argocd-cm`, thử offline 8 trạng thái đúng cả 8; app `argocd` `Synced/Healthy`) rồi `dd406a4` (`infra/pg-main/pooler.yaml`). App `pg-main` `Synced/Healthy` 5 s sau push, pod PgBouncer Ready sau 22 s trên `k8s-w2`.
  - Tra mã nguồn: operator **không** đặt `default_pool_size`, PgBouncer mặc định **20** (chuẩn cũ ghi nhầm 10). Đặt tường minh `"10"` bằng `connectionLimit` của `_app`. Đặt thêm `client_tls_sslmode: require` (operator mặc định `prefer`). Image ghim `pgbouncer:1.25.2-202609221033-trixie@sha256:b15c4280…` (đúng bản mặc định của operator 1.30.1). `pgbouncer.ini` trong pod khớp: `pool_mode = transaction`, `default_pool_size = 10`, `client_tls_sslmode = require`, `server_tls_sslmode = verify-ca`, `auth_user = cnpg_pooler_pgbouncer`.
  - Qua Pooler (`hello_app`, `sslmode=require`): vào `hello` được; **`CREATE TABLE x()` → `permission denied for schema public`** (tiêu chí 2); `CREATE TEMP TABLE` thành công (đúng ghi chú TEMPORARY ở bước 5); vào `app` → `pg_hba.conf rejects connection for host "10.244.46.47"` (IP pod Pooler: `pg_hba` của Cluster vẫn quyết định); `sslmode=disable` → `SSL required`; sai mật khẩu → `SASL authentication failed`.
  - Pool: 25 client `pg_sleep(2)` song song → PostgreSQL thấy đúng 10 kết nối `hello_app` (đo 2 lần trong lúc chạy), 25/25 thành công trong 6 s (3 lượt × 2 s). _Đính chính ở bước 8: 10 kết nối đó gồm cả 1 phiên DataGrip nối thẳng, tức Pooler chỉ mở được 9; xem phát hiện về chỗ dư của `connectionLimit`._
  - Pod: QoS `Burstable` cố ý (memory 64 Mi requests = limits, CPU request 50m không limit); securityContext đạt PSS `restricted` (non-root, drop ALL, root FS chỉ đọc, seccomp `RuntimeDefault`); RAM 17 Mi. Init container `bootstrap-controller` dùng image operator ghim digest. Log Pooler và operator 0 lỗi.
  - Giới hạn health check: lúc app báo Healthy, pod PgBouncer còn `Init:0/1`. Status của `Pooler` không có số pod Ready và health app không kế thừa resource con; kiểm bằng `kubectl rollout status`, alert ở G0-13 (ghi vào chuẩn).
- [x] 7. Database `keycloak` (thứ ba, sau `app` và `hello`) trong đúng một commit; runbook "thêm service". Kiểm: diff một commit; Argo `Healthy`; `keycloak` đăng nhập thẳng `pg-main-rw`.
  - Chủ repo giao Claude làm. Kết quả: gitops `8c44be4`, **một commit, 4 file, 80 dòng** (`keycloak.yaml` mới, `pg-main-keycloak.sealedsecret.yaml` mới, `cluster.yaml` +1 dòng `hostssl keycloak keycloak all scram-sha-256`, `kustomization.yaml` +3). App `pg-main` `Synced/Healthy` 12 s sau push, qua wave 0 → 1 → 2 → 3; `DatabaseRole keycloak`, `Database keycloak` `APPLIED true`. `scripts/check-no-plain-secrets.sh` in `OK`.
  - Role `keycloak`: LOGIN, `rolbypassrls`/`rolsuper`/`rolcreatedb`/`rolcreaterole` đều `f`, `connectionLimit 20` (bằng `db-pool-max-size` 20 của keycloak.md), `SCRAM-SHA-256`; database `keycloak` thuộc `keycloak`. Role LOGIN có `BYPASSRLS` trong cụm vẫn chỉ `postgres` (tiêu chí D). Secret sinh ra `kubernetes.io/basic-auth`, nhãn `cnpg.io/reload=true`.
  - `keycloak` nối thẳng `pg-main-rw` (`ssl = t`): `CREATE TABLE`, `INSERT`, `DROP TABLE` thành công không cần `GRANT` (owner database, `public` thuộc `pg_database_owner`). `keycloak` vào `hello`, `app`, `postgres` và `hello_app` vào `keycloak` đều `pg_hba.conf rejects connection`. `pg_hba`: dòng 21 `keycloak` trước dòng 22 `reject`. Reload, không restart (`pg_postmaster_start_time` giữ nguyên).
  - Ghi nhận: `keycloak` qua Pooler vẫn vào được database `keycloak`. Pooler không giới hạn role; "nối thẳng `pg-main-rw`" là quy ước cấu hình của Keycloak (ghi vào runbook).
  - Runbook [`docs/runbooks/pg-main-them-service.md`](../../../runbooks/pg-main-them-service.md): mô hình 4 lớp, biến thể A (service G1) và B (ứng dụng tự migrate, lý do quyết định C), ngân sách kết nối (đang dùng 32/97), lệnh sinh mật khẩu, dòng `pg_hba`, kiểm sau sync, đưa mật khẩu sang namespace service (đã thử pipeline, không ghi file), đổi mật khẩu (một commit cho cả hai bản; lệnh `tee` **chưa diễn tập**), gỡ service (chưa diễn tập), bảng sự cố.
- [x] 8. Thí nghiệm `kubectl drain` node chạy `pg-main`. Kiểm: PDB chặn hay không; cách xử lý vào runbook, ADR-0004 nếu lệch.
  - Chủ repo giao Claude làm. Pod đo `pg-drain-probe` trên `k8s-w2` mở kết nối mới mỗi khoảng 0,55 s qua Pooler và thẳng `pg-main-rw` (đã xóa sau thí nghiệm). Drain dùng `--pod-selector=cnpg.io/cluster=pg-main` để không evict operator, Argo CD, CoreDNS cùng nằm trên `k8s-w1`.
  - **PDB chặn:** `kubectl drain k8s-w1 --timeout=40s` → node cordon, 9 lần evict đều `Cannot evict pod as it would violate the pod's disruption budget`, hết giờ; PostgreSQL không gián đoạn.
  - **Xử lý (giữ PDB, tạm 2 instance):** gitops `f716c46` `instances: 2` → replica `pg-main-2` Ready trên `k8s-w2` sau 13 s → operator **tự switchover** ngay vì primary nằm trên node đang cordon (chưa cần drain lần hai), 02:54:18–02:54:25 → gitops `814e7f4` `instances: 1` → operator xóa `pg-main-1` và PVC của nó sau 10 s, không chạm primary → drain lại xong ngay → `uncordon`.
  - **Gián đoạn kết nối mới:** thẳng `pg-main-rw` 7,5 s (`Connection refused`); qua Pooler khoảng 15 s (`timeout expired`, rồi `server login has been failing, cached error (server_login_retry)`); lúc về 1 instance 0 lỗi (96/96).
  - Sau thí nghiệm: primary `pg-main-2` trên `k8s-w2`, app `pg-main` `Synced/Healthy` ở `814e7f4`; đủ 5 role (thuộc tính đúng), 2 database đúng owner, 3 luật `pg_hba`, mọi CR `APPLIED true`.
  - Không lệch chuẩn (giữ `enablePDB: true`). ADR-0004: thay câu "cách xử lý **chưa xác minh**" bằng kết quả và cách đã chọn. Runbook mới [`pg-main-bao-tri-node.md`](../../../runbooks/pg-main-bao-tri-node.md). Runbook "thêm service" bỏ tên pod cứng `pg-main-1`, tìm primary bằng `status.currentPrimary`.
  - **Hai phát hiện về Pooler, chờ chủ repo quyết** (ghi ở chuẩn mục "Pooler"): (a) `default_pool_size` 10 = `connectionLimit` 10 không còn chỗ dư; một phiên `hello_app` nối thẳng (DataGrip) làm PgBouncer nhận `too many connections for role` rồi trả `FATAL` cho client trong 15 s (gặp lúc 02:52:21). Đề xuất pool 8, giữ giới hạn 10. (b) `server_login_retry` mặc định 15 s gấp đôi gián đoạn qua Pooler. Đề xuất 2 s, hoặc `paused: true` khi switchover có kế hoạch.
  - **Chủ repo duyệt áp cả hai** (2026-11-15): gitops `7932302`. `default_pool_size: "8"`, `server_login_retry: "2"` trong `pooler.yaml`; comment `connectionLimit` trong `hello.yaml` đổi thành "8 + 2 chỗ cho kết nối thẳng". PgBouncer nạp lại, pod không restart (`restartCount 0`, cùng tên pod); `pgbouncer.ini` trong pod mang giá trị mới. Đo: giữ 2 kết nối `hello_app` thẳng, 25 client `pg_sleep(2)` song song qua Pooler → 8 kết nối từ Pooler + 2 thẳng = 10, **25/25 thành công**, 8 s (4 lượt). Gián đoạn qua Pooler sau switchover với `server_login_retry` 2 s **chưa đo lại** (cần một lần switchover nữa).
- [x] 9. Kết ticket: `code-review`, số đo vào `docs/experiments/`, tick tiêu chí, ma trận truy vết, Bài học.
  - Chủ repo giao Claude làm. `kubectl kustomize` sạch cả 10 thư mục; dry-run server (server-side apply cho thư mục có CRD lớn) không lỗi manifest; `check-no-plain-secrets.sh` `OK`; 11/11 app `Synced/Healthy`. Review hai trục, sửa ở gitops `8354d61`. Số đo vào [bản ghi G0 mục 7](../../../experiments/2026-11-g0.md#7-postgresql-pg-main-trên-cloudnativepg-role-khai-báo-pg_hba-pooler-drain).

## Kết quả

- Bằng chứng: [bản ghi G0, mục 7](../../../experiments/2026-11-g0.md#7-postgresql-pg-main-trên-cloudnativepg-role-khai-báo-pg_hba-pooler-drain); runbook [thêm service](../../../runbooks/pg-main-them-service.md) và [bảo trì node](../../../runbooks/pg-main-bao-tri-node.md).
- `gitops`: `4f83d98` (operator), `d239b05` (`Cluster`), `68854bf` (health `DatabaseRole`), `da82fd6` (`hello`), `359a90e` (`pg_hba`), `1b03f66` (health `Pooler`), `dd406a4` (Pooler), `8c44be4` (`keycloak`, một commit), `f716c46` và `814e7f4` (thí nghiệm drain), `7932302` (pool 8, `server_login_retry`), `8354d61` (sửa theo review). 11 app `Synced/Healthy`; primary hiện là `pg-main-2` trên `k8s-w2`.
- `docs`: chưa commit (repo còn thay đổi khác của chủ repo, xem đề xuất commit).
- Ma trận truy vết: không có dòng tương ứng (ticket hạ tầng, như G0-03..07).
- Chuyển cho ticket sau:
  - G0-10 (Keycloak): `spec.db` dùng bản sao Secret `pg-main-keycloak` seal sang namespace `keycloak` (runbook "thêm service", mục đưa mật khẩu sang namespace service); `db-pool-max-size` 20 khớp `connectionLimit 20`; nối thẳng `pg-main-rw`, `sslmode` ít nhất `prefer`.
  - G0-27 (`hello`): Secret `pg-main-hello-app`, `pg-main-hello-migrator` seal sang namespace `hello`; runtime qua `pg-main-pooler-rw.postgres.svc`, Flyway thẳng `pg-main-rw`; cân nhắc `REVOKE TEMPORARY` trong migration đầu; NetworkPolicy namespace `postgres`.
  - G0-13 (monitoring): alert pod PgBouncer không Ready (health Argo CD không thấy), `cnpg_collector_up`, số kết nối theo role so với `connectionLimit`.
  - G0-09 (backup): trước đó không gỡ database nào (`retain`, `DROP` tay sau khi có backup).
  - Lần bảo trì node hoặc thí nghiệm failover kế tiếp: đo lại gián đoạn qua Pooler với `server_login_retry` 2 s; thử `paused: true`; diễn tập lệnh `tee` đổi mật khẩu khi có service thật.

## Review

Skill `code-review` hai trục (Standards, Spec) trên `gitops` `4f83d98^..7932302`. Claude sửa (chủ repo giao cả bước 9):

1. **[Nặng] Namespace `postgres` chỉ có `Prune=false`.** App có finalizer cascade nên xóa app sẽ xóa namespace, kéo theo `Cluster` và PVC; comment ở `apps/lab/pg-main.yaml` khẳng định sai. Sửa: thêm `Delete=false`, sửa comment, thêm mục vào chuẩn.
2. **Pooler ở wave 1 trái thứ tự `… → Database → Pooler` của chuẩn.** Giữ wave 1 và sửa chuẩn: role lỗi kẹt Progressing mãi, Pooler đặt sau `Database` sẽ bị chặn sync theo.
3. **SealedSecret wave 1 khác quy ước `-1`.** Ghi ngoại lệ vào `sealing-key.md`.
4. **Comment cũ**: "10 kết nối server" (giá trị là 8), "Database… thêm ở các bước sau", "ownerReference kiểm ở bước 3", "cách bảo trì chọn ở bước 8". Sửa cả bốn.
5. **Ngân sách kết nối và quy trình mật khẩu chép ở nhiều file** (Duplicated Code). Sửa: comment trỏ về runbook. Header SealedSecret cũ còn mâu thuẫn với runbook về cách đổi mật khẩu (seal bản sao từ Secret trong cụm thì không đổi được trong một commit); nay chỉ trỏ về runbook.
6. **ADR-0003 vẫn ghi `REVOKE CONNECT, TEMPORARY`; ADR-0010 ghi "không role nào đăng nhập được mà có `BYPASSRLS`".** Sửa: thêm ghi chú 2026-11-15 vào hai ADR (quyết định A, D), quyết định không đổi.
7. **Mô tả ghi "requests = limits" chung; tiêu chí 1 chưa sửa theo quyết định E.** Sửa: ghi chú ở Mô tả, viết lại tiêu chí 1.

Bỏ qua:

8. **Thêm một service chạm 4–5 file** (Shotgun Surgery). Chuẩn chọn "một commit, mỗi service một file CR"; gom vào một chart sẽ che mất chính sách `pg_hba` nằm ở một chỗ. Runbook liệt kê đủ các chỗ phải sửa.
9. **Tên `marketplace-sim` (comment `hello.yaml`, `apps/lab/pg-main.yaml`) và `shopee-sim` (ADR-0003) cùng tồn tại trong docs** (49 và 56 chỗ). Không thuộc phạm vi ticket; GLOSSARY chưa chốt.

## Bài học

- Đọc mã nguồn đúng tag rẻ hơn đoán từ docs: `default_pool_size` mặc định là 20 chứ không phải 10, `Pooler.status` không có số pod Ready, `DatabaseRole` lỗi không bao giờ chuyển Degraded. Cả ba đều chỉ lộ khi đọc `config.go`, `pooler_status.go`, `databaserole_funcs.go`, rồi thử trên object thật.
- Một giới hạn "khớp vừa đủ" là không có chỗ dư: pool 10 bằng `connectionLimit` 10 chạy tốt trong bài tải sạch, nhưng một phiên DataGrip làm PgBouncer trả `FATAL` cho client. Bảo vệ dữ liệu cũng vậy: `Delete=false` trên `Cluster` vô nghĩa khi namespace chứa nó không có; review mới bắt được.
- Câu chuyện kể được: "Tôi dựng PostgreSQL dùng chung cho nhiều service bằng CloudNativePG, khóa từng database bằng `pg_hba` theo database × role (đo trước và sau: `hello_app` từ vào được mọi database thành bị từ chối, kể cả qua PgBouncer), thêm database thứ ba trong một commit 4 file, và chứng minh PDB chặn drain node khi chỉ có 1 instance. Cách bảo trì tôi chọn là tạm 2 instance qua Git để operator switchover: kết nối mới gián đoạn 7,5 s, còn qua PgBouncer là 15 s vì `server_login_retry`, nên tôi hạ tham số đó."

