# PostgreSQL trên cụm home lab (operator, topology, HA, backup, pooling, RLS)

Tra cứu ngày 12/11/2026 cho ticket [03 PostgreSQL trên cụm home lab](../.scratch/architecture-g0-g1/issues/03-postgres-on-cluster.md). Bối cảnh: cụm kubeadm Kubernetes 1.37, 3 node (control plane nhận pod), `local-path-provisioner` v0.0.37, ngân sách khoảng 2 GB RAM cho PostgreSQL ([homelab](../../platform/docs/homelab-hyperv.md#chia-tài-nguyên-32-gb-ram-20-luồng)). Ở G1 có 5 service có DB (tenant, channel-connector, catalog, inventory, order), cộng Keycloak và có thể `shopee-sim`.

Tài liệu CloudNativePG được đọc từ mã nguồn docs ở tag `v1.30.1` (`github.com/cloudnative-pg/cloudnative-pg/tree/v1.30.1/docs/src`), nội dung giống trang `cloudnative-pg.io/docs/1.30/`. Plugin Barman Cloud đọc ở tag `v0.16.0`. Thông tin phiên bản lấy từ GitHub Releases API.

Nhãn: **[CT]** tài liệu hoặc mã nguồn chính thức · **[CXM]** chưa xác minh · **[SL]** suy luận của người viết, chưa có nguồn nói thẳng.

## Tóm tắt

- **Operator:** CloudNativePG 1.30.1. Dự án sống, Apache-2.0, operator nhẹ nhất (request 100 Mi), và là operator duy nhất trong ba bản so sánh có CRD riêng cho từng database (`Database`) và từng role (`DatabaseRole`). Argo CD 3.6 có sẵn health check cho `Cluster`, `Database`, `Backup`. Lưu ý: Kubernetes 1.37 hiện chỉ ở mức "đã test, chưa hỗ trợ" với 1.30.x.
- **Topology:** một `Cluster` dùng chung, mỗi service một database và bộ role riêng. Docs CloudNativePG khuyên mỗi microservice một cluster. Ở lab ta lệch khuyến nghị này vì RAM, nên cần ghi ADR.
- **HA:** 2 instance, anti-affinity `required`, synchronous `ANY 1` với `dataDurability: preferred`. Với `local-path`, node chết thì instance trên node đó kẹt cho tới khi node quay lại. Muốn dựng lại ở node khác phải `kubectl cnpg destroy` bằng tay.
- **Backup:** dùng plugin Barman Cloud (cách in-tree sẽ bị gỡ ở 1.31; plugin cần cert-manager) đẩy WAL và base backup lên object store S3-compatible chạy trên VM `gw`. MinIO community đã ngừng bảo trì, nên dùng RustFS. Đặt `archive_timeout = 1min` để đạt RPO ≤ 1 phút (N10). Khôi phục luôn ra một cluster mới.
- **Pooling:** Pooler PgBouncer ở chế độ `transaction` cho traffic runtime. Tenant context đặt bằng `SET LOCAL` hoặc `set_config(..., true)`. Job Flyway và Keycloak nối thẳng `<cluster>-rw`, vì advisory lock kiểu session và lệnh `SET` không dùng được qua transaction pooling.
- **Owner và RLS:** thực ra docs CloudNativePG không mâu thuẫn với cách tách role. Bootstrap nói "app kết nối bằng owner", nhưng FAQ khuyên tạo thêm user đọc ghi và `GRANT`. Giữ 3 role owner/migrator/app như [db-migration.md](../standards/db-migration.md), không dùng `app` mặc định cho runtime.

---

## 1. Chọn operator

### 1.1 So sánh

| Tiêu chí | CloudNativePG | Zalando postgres-operator | Crunchy PGO | StatefulSet tự viết |
|---|---|---|---|---|
| Bản mới nhất (12/11/2026) | **1.30.1** (23/09/2026); 1.29.3 cùng ngày [CT] | **v2.0.3** (02/10/2026); v2.0.0 là major mới (27/07/2026) [CT] | **v6.0.2** (02/06/2026); v5.8.8 [CT] | — |
| Hoạt động | Commit gần nhất 12/11/2026, không archived [CT] | Commit 11/11/2026 [CT] | Commit 11/11/2026 [CT] | Tự bảo trì |
| License mã nguồn | Apache-2.0 [CT] | MIT [CT] | Apache-2.0 [CT] | — |
| License image | Image cộng đồng `ghcr.io/cloudnative-pg/*` | `ghcr.io/zalando/*` (Spilo) | Image từ Crunchy Developer Portal theo **Developer Program terms**: tổ chức từ 50 nhân viên trở lên chỉ được dùng cho phát triển, chạy production phải mua subscription [CT] | — |
| Kubernetes | 1.30.x: hỗ trợ 1.34–1.36; **1.37 chỉ "tested, not supported"** [CT] | README ghi "1.27 trở lên" cho mọi bản đến v2.0.3, không có cận trên [CT] | 6.0: 1.32–1.36 (không có 1.37) [CT] | Mọi bản |
| PostgreSQL | 14–18; image mặc định `18.6-system-trixie` [CT] | 14–18 (v2 bỏ PG 13) [CT] | 14–18 [CT] | Tùy |
| HA | Instance manager tự viết, không dùng Patroni; 1.30 thêm `Lease` để tuần tự hóa promote [CT] | Patroni trong image Spilo [CT] | Patroni [CT] | Tự làm (khó) |
| Backup | Plugin Barman Cloud (CNPG-I); volume snapshot [CT] | WAL-G vào S3/GCS, logical backup CronJob [CT] | pgBackRest (full/incremental/differential) [CT] | Tự làm |
| Khai báo DB/role | CRD `Database`, `DatabaseRole` (mới ở 1.30), hoặc `spec.managed.roles` [CT] | Map `users`, `databases`, `preparedDatabases` trong CR `postgresql` [CT] | `spec.users` trong `PostgresCluster` [CXM chi tiết] | Script SQL |
| Pooler | CR `Pooler` (PgBouncer) [CT] | PgBouncer tích hợp [CT] | PgBouncer [CT] | Tự làm |
| Metric | Exporter có sẵn trong instance manager, cổng 9187 [CT] | Không kèm exporter; docs chỉ cách gắn sidecar để monitoring [CT] | Image `postgres-exporter` và OTel collector [CT] | Tự làm |
| RAM của operator (manifest mặc định) | request 100 Mi, limit 200 Mi [CT] | request 250 Mi, limit 500 Mi [CT] | `manager.yaml` không đặt `resources` [CT] | 0 |

Nguồn: GitHub Releases API và trang repo của `cloudnative-pg/cloudnative-pg`, `zalando/postgres-operator`, `CrunchyData/postgres-operator`; [CNPG Supported releases 1.30](https://cloudnative-pg.io/docs/1.30/supported_releases/); manifest `cnpg-1.30.1.yaml` (Deployment `cnpg-controller-manager`); `zalando/postgres-operator@v2.0.3` (`README.md`, `manifests/postgres-operator.yaml`, `docs/reference/cluster_manifest.md`, `docs/user.md`, `docs/administrator.md`); release notes v2.0.1; `CrunchyData/postgres-operator@v6.0.2` (`README.md`, `config/manager/manager.yaml`); [PGO Supported Platforms](https://access.crunchydata.com/documentation/postgres-operator/latest/overview/supported-platforms); [Crunchy Developer Program terms](https://www.crunchydata.com/developers/terms-of-use).

### 1.2 Điểm đáng chú ý

- **Kubernetes 1.37 chưa được hỗ trợ chính thức.** Bảng supported releases của CNPG ghi 1.37 là "tested, but not supported" cho cả 1.30.x lẫn 1.29.x [CT]. 1.30.x hết hạn khoảng 12/2026. 1.31 dự kiến ra khoảng 09/2026 nhưng tới ngày tra vẫn chưa phát hành [CT]. Việc 1.31 có đưa 1.37 vào danh sách hỗ trợ hay không thì **[CXM]**. Crunchy 6.0 còn chưa liệt kê 1.37. Zalando không công bố cận trên.
- **Thay đổi ở 1.30 có ích cho GitOps** [CT, release notes 1.30.0]:
  - CRD `DatabaseRole`: mỗi role là một object riêng, có reclaim policy `retain`/`delete`.
  - `spec.cluster` của `Database`, `Pooler`, `ScheduledBackup` không đổi được nữa (CEL chặn).
  - `Pooler` lấy image PgBouncer từ `ImageCatalog`.
  - Vá CVE-2026-55769: owner database có thể leo quyền qua `search_path`.
  - Operator SCRAM-hash mật khẩu role trước khi gửi `ALTER ROLE`.
- **In-tree Barman Cloud sẽ bị gỡ ở 1.31.0** [CT, release notes 1.30.0]. Bản 1.30 vẫn còn nhưng đã deprecated. Cách duy nhất cho các bản sau là plugin (mục 4).
- **Argo CD 3.6.1** có sẵn health check Lua cho `postgresql.cnpg.io/Cluster`, `Database`, `Backup`. Chưa có check cho `Pooler`, `DatabaseRole`, `ScheduledBackup` và `barmancloud.cnpg.io/ObjectStore` [CT, `argoproj/argo-cd@v3.6.1/resource_customizations/postgresql.cnpg.io/`]. Điều này trả lời điểm **chưa xác minh** ở [gitops-argocd.md](../standards/gitops-argocd.md): 3 CRD kia phải tự viết check, hoặc chấp nhận Argo CD coi chúng Healthy khi đã tạo.
- **StatefulSet tự viết** bị loại. Phải tự làm failover, fencing, `pg_rewind`, WAL archive, PITR và đổi Service khi failover. Đây là những phần operator đã giải sẵn, và việc tự viết không sinh thêm case kỹ thuật nào của ecommerce [SL].

### 1.3 Kết luận mục 1

Chọn **CloudNativePG 1.30.1**, kèm việc phải làm là theo dõi bản 1.31 để có hỗ trợ chính thức Kubernetes 1.37 và nâng trước khi 1.30 hết hạn (~12/2026). Lý do:

1. Khai báo được database và role bằng CRD, hợp GitOps (C12).
2. Operator nhẹ nhất và có exporter sẵn.
3. Không có ràng buộc license image.
4. Homelab và các standard ([db-migration.md](../standards/db-migration.md), [gitops-argocd.md](../standards/gitops-argocd.md)) đã giả định dùng nó.

Zalando là phương án dự phòng hợp lý (MIT, Patroni đã chín), nhưng khai báo DB/role là map trong một CR to, và không có exporter.

## 2. Database per service: một cluster hay nhiều cluster

### 2.1 Docs CNPG nói gì

FAQ của CNPG ("How many databases should be hosted in a single PostgreSQL instance?") **khuyên mỗi cluster chỉ chứa một database của một microservice**, với 4 lý do [CT, `faq.md`]:

1. CPU và RAM của PostgreSQL được quản lý ở mức instance, không ở mức database.
2. Backup liên tục và PITR chạy ở mức instance. Một database mỗi instance giúp PITR đơn giản hơn, mỗi database có retention riêng.
3. Mỗi ứng dụng tự quyết thời điểm cập nhật của mình.
4. Mỗi ứng dụng tự chọn bản PostgreSQL và thời điểm nâng major.

FAQ cũng nói vẫn có thể tạo bao nhiêu user và database cũng được, tùy tài nguyên. Plugin Barman Cloud khuyên mỗi cluster một `ObjectStore` [CT, `concepts.md`].

### 2.2 So sánh hai cách ở lab

| Khía cạnh | Một `Cluster`, N database | Mỗi service một `Cluster` |
|---|---|---|
| RAM | 1 bộ instance (ví dụ 2 × ~1 GiB) cùng chung `shared_buffers`. Khớp ngân sách ~2 GB của homelab | 7–8 cluster (5 service, Keycloak, `shopee-sim`) × 2 instance = 14–16 pod PostgreSQL, cộng mỗi pod một sidecar Barman. Ngay cả ở mức 256–512 Mi một pod cũng mất 4–8 GB, gấp 2–4 lần ngân sách [SL, chưa đo] |
| Backup/PITR | WAL chung. Muốn khôi phục **một** database về một thời điểm thì phải PITR cả cluster ra cluster mới rồi `pg_dump` database đó trả về [SL, suy ra từ "recovery không in-place" ở `recovery.md`] | PITR từng service độc lập [CT, FAQ] |
| Cô lập | Ranh giới bằng role và quyền: `REVOKE CONNECT ... FROM PUBLIC`, `pg_hba` theo database và role, `connectionLimit` cho từng role và database. Vẫn dùng chung `max_connections`, I/O, autovacuum (noisy neighbour) | Cô lập ở mức process và pod |
| Nâng cấp | Nâng major một lần cho mọi service (CNPG làm offline bằng `pg_upgrade --link`) [CT, `postgres_upgrades.md`] | Từng service nâng riêng |
| Blast radius | Một sự cố (đầy đĩa, OOM, failover) ảnh hưởng mọi service | Chỉ một service |
| Công vận hành | 1 `Cluster`, 1 `ObjectStore`, 1 `Pooler` | N lần mọi thứ |

**Hai điểm cần làm nếu dùng chung cluster:**

- **PUBLIC mặc định có `CONNECT` và `TEMPORARY` trên mọi database mới** [CT, [PG 18 – Privileges](https://www.postgresql.org/docs/18/ddl-priv.html)]. Không `REVOKE` thì `catalog_app` vẫn kết nối được vào database `inventory` (chưa đọc được bảng, nhưng đã qua lớp kết nối). Cần `REVOKE CONNECT, TEMPORARY ON DATABASE <db> FROM PUBLIC` rồi `GRANT CONNECT` cho role của service. Ngoài ra thêm `pg_hba` dạng `hostssl <db> <svc>_app,<svc>_migrator all scram-sha-256`. CNPG cho khai báo qua `spec.postgresql.pg_hba` [CT, `postgresql_conf.md`].
- **`max_connections` dùng chung.** PostgreSQL mặc định "typically 100" và CNPG không ghi đè trong cấu hình mặc định [CT, `postgresql_conf.md` không liệt kê `max_connections`]. Chia hạn mức bằng `connectionLimit` của role hoặc `Database` [CT, CRD `databases.postgresql.cnpg.io` có `connectionLimit`; `declarative_role_management.md`].

### 2.3 Khai báo bằng CRD (CNPG 1.30)

- **`Database`**: khai báo tên, `owner`, `extensions`, `schemas`, `connectionLimit`, `databaseReclaimPolicy` (`retain` mặc định, hoặc `delete`), `ensure: present|absent` [CT, `declarative_database_management.md`]. Có giới hạn: `Database` **không quản lý nội dung database** ngoài extension và schema, tức là bảng và quyền trên bảng vẫn do migration lo.
- **`DatabaseRole`**: docs gọi là cách "recommended" cho GitOps. Khai báo `login`, `inRoles`, `connectionLimit`, `passwordSecret`, `clientCertificate` [CT, `declarative_role_management.md`]. Hai điều cần biết:
  1. `DatabaseRole` chỉ được áp lại khi spec hoặc Secret đổi. Ai sửa tay bằng `ALTER ROLE` thì thay đổi đó **không bị phát hiện**. Ngược lại, `spec.managed.roles` được so định kỳ với catalog và kéo về đúng spec [CT].
  2. Nếu một role được khai báo ở cả hai nơi thì `managed.roles` thắng [CT].
- **Ràng buộc namespace:** `DatabaseRole`, `Cluster` nó trỏ tới và `passwordSecret` phải **cùng namespace**. `Pooler` cũng phải cùng namespace với `Cluster` [CT, `declarative_role_management.md`, `connection_pooling.md`].
- **Cảnh báo bảo mật:** quyền ghi `DatabaseRole` (hoặc `Pooler`) trong một namespace **tương đương superuser** của các cluster trong namespace đó, vì role có thể đặt `superuser: true` hoặc `inRoles: [postgres]` [CT, `security.md`]. Vì vậy `AppProject` của service **không được** có quyền tạo các CR này. Chúng thuộc app hạ tầng (`platform`).

Hệ quả cho thiết kế [SL]: Cluster, `Database`, `DatabaseRole` và Secret mật khẩu của role đều nằm ở namespace `postgres`, còn pod service ở namespace riêng. Cùng một mật khẩu do đó phải có mặt ở hai namespace. Cách đơn giản nhất là hai `SealedSecret` sinh từ cùng plaintext. Phương án khác: dùng `clientCertificate` của `DatabaseRole` (CNPG tự sinh và xoay vòng cert), nhưng Secret cert cũng chỉ nằm ở namespace `postgres`. Chọn cách nào để ticket secret quyết định.

## 3. HA và lưu trữ: 3 node, `local-path`

### 3.1 Docs nói gì

- CNPG khuyên kiến trúc **shared-nothing**: mỗi instance ở một node riêng, **dùng local volume** gắn vào node, không dùng chung storage [CT, `architecture.md`, `storage.md`]. `local-path` đúng tinh thần này.
- Anti-affinity mặc định là `preferred` theo `kubernetes.io/hostname`. Đặt `podAntiAffinityType: required` để bắt buộc mỗi instance một node [CT, `scheduling.md`].
- Mất primary: operator promote standby có lag thấp nhất, chuyển Service `-rw` sang nó. Primary cũ dùng `pg_rewind` nếu PVC còn, không thì tạo standby mới từ backup [CT, `failure_modes.md`].
- Mất standby: pod khởi động lại với PVC cũ nếu còn, không thì tạo pod mới từ backup của primary [CT].
- Drain node: nếu node chứa primary thì CNPG switchover trước khi drain. Cluster một instance thì PDB chặn drain. Từ 3 instance trở lên, mỗi lần drain chỉ tắt một replica. Mỗi `Cluster` có 2 PDB [CT, `kubernetes_upgrade.md`].
- Riêng với **local storage**: `nodeMaintenanceWindow.reusePVC: true` (mặc định) chờ node quay lại để dùng lại PVC. `false` thì dựng lại pod ở node khác bằng streaming replication, chỉ nên dùng khi DB nhỏ [CT, `kubernetes_upgrade.md`]. Docs ghi trường này vẫn được hỗ trợ nhưng là cách cũ.
- `kubectl cnpg destroy <cluster> <instance>` xóa một instance cùng PVC của nó, để operator dựng instance mới [CT, `kubectl-plugin.md`].
- Synchronous replication [CT, `replication.md`]:
  - Mặc định tắt.
  - `method: any` (quorum) hoặc `first`, kèm `number`.
  - `dataDurability: required` (mặc định) cho RPO = 0 nhưng **dừng ghi** khi thiếu standby.
  - `preferred` giảm số standby đồng bộ theo số standby đang có, và không dùng được cùng `standbyNamesPre`/`standbyNamesPost`.
- Khi có WAL archive, replica tự dùng `restore_command` lấy WAL từ archive nếu streaming hụt [CT, `replication.md`].

### 3.2 Điều gì xảy ra khi mất một node (với `local-path`)

PV của `local-path` gắn node bằng `nodeAffinity` (`volumeBindingMode: WaitForFirstConsumer`, xem [homelab mục 8.2](../../platform/docs/homelab-hyperv.md)). Ghép với các điểm ở 3.1 thì [SL]:

1. **Node chứa primary chết:** standby được promote, `-rw` đổi đích. Pod cũ ở `Pending`/`Terminating`, PVC vẫn trỏ về node chết. Cluster chạy một instance cho tới khi node quay lại (`pg_rewind` rồi thành replica) hoặc tới khi ta `kubectl cnpg destroy` instance đó để dựng replica mới ở node còn sống.
2. **Node chứa standby chết:** primary chạy tiếp. Với `dataDurability: required`, primary **dừng ghi** vì thiếu standby đồng bộ. Đây là lý do chọn `preferred` khi chỉ có 2 instance.
3. Operator có tự nhận ra "PVC còn nhưng node không quay lại" để dựng lại ở node khác hay không: **[CXM]**. Docs chỉ ghi "nếu PVC còn". Cần thí nghiệm `Stop-VM -TurnOff` như homelab mục 10 gợi ý.

### 3.3 Số instance

| Phương án | RAM | Hành vi |
|---|---|---|
| 1 instance | Thấp nhất | Không HA. PDB chặn drain, trừ khi `enablePDB: false` [CT] |
| **2 instance + sync `ANY 1` + `preferred`** | ~2 GB (khớp homelab) | RPO = 0 khi cả hai khỏe. Mất một node vẫn ghi được (RPO quay về mức WAL archive) |
| 3 instance + sync `ANY 1` + `required` | ~3 GB | RPO = 0 khi mất một node, vẫn ghi được. Mỗi node một instance, không còn chỗ trống để dựng lại khi một node chết (cụm chỉ có 3 node) |

Đề xuất 2 instance. Lên 3 khi nâng RAM lên 64 GB (homelab đã nêu hướng nâng này).

## 4. Backup và khôi phục

### 4.1 Cơ chế (CNPG 1.30 + plugin Barman Cloud v0.16.0)

- Từ 1.26 backup native được chuyển dần sang plugin CNPG-I. Plugin chính thức là **Barman Cloud Plugin**, dùng cho object storage. Native còn hỗ trợ volume snapshot nếu StorageClass hỗ trợ [CT, `backup.md`]. `local-path` không có CSI snapshot [SL], nên chỉ còn đường object storage.
- Plugin v0.16.0 (09/11/2026) **yêu cầu CNPG ≥ 1.30 và cert-manager**. cert-manager là cách khuyên dùng để có TLS giữa operator và plugin; nếu không thì tự cấp cert bundle. Plugin phải cài cùng namespace với operator [CT, `intro.md`, `installation.mdx`]. Đây là **phụ thuộc mới** cho G0: cert-manager thêm vài pod, RAM của chúng **[CXM]**.
- Khai báo gồm:
  - `ObjectStore` (`barmancloud.cnpg.io/v1`) với `destinationPath`, `endpointURL`, `s3Credentials`, `wal.compression`, `retentionPolicy` (ví dụ `"30d"`).
  - Trong `Cluster.spec.plugins`: `name: barman-cloud.cloudnative-pg.io`, `isWALArchiver: true`, `parameters.barmanObjectName`.
  - Base backup bằng `Backup`/`ScheduledBackup` với `method: plugin` [CT, `usage.md`, `retention.md`].
- Plugin chạy dưới dạng **sidecar trong mỗi pod instance**. Resources đặt qua `ObjectStore.spec.instanceSidecarConfiguration.resources` [CT, `usage.md`]. Giá trị mặc định **[CXM]**, phải đặt tường minh vì cụm sát RAM.
- **RPO:** CNPG đặt `archive_timeout = 5min`, nên RPO cho DR mặc định ≤ 5 phút [CT, `wal_archiving.md`, `backup.md`]. Docs PostgreSQL ghi "archive_timeout settings of a minute or so are usually reasonable"; đặt quá ngắn làm phình archive vì file đóng sớm vẫn đủ 16 MB [CT, [PG 18 – WAL config](https://www.postgresql.org/docs/18/runtime-config-wal.html)]. N10 đòi RPO ≤ 1 phút, nên đặt `archive_timeout: 1min` và nén WAL (`gzip`/`bzip2`/... trong `ObjectStore`).
- **Khôi phục không làm tại chỗ.** Recovery luôn dựng một **cluster mới** từ base backup cộng WAL (`bootstrap.recovery` + `externalClusters[].plugin` có `serverName` của cluster gốc), tùy chọn `recoveryTarget.targetTime` cho PITR [CT, `recovery.md`, `usage.md`]. Cluster khôi phục không tự archive WAL; muốn bật thì trỏ `spec.plugins` vào một `ObjectStore` khác (ví dụ trong docs dùng `s3-store-bis`) [CT].
- Metric: plugin xuất `barman_cloud_cloudnative_pg_io_last_available_backup_timestamp`, `..._last_failed_backup_timestamp` và metric điểm khôi phục sớm nhất. Các metric `cnpg_collector_*` cũ đã deprecated [CT, plugin `observability.md`, `monitoring.md`].

### 4.2 Đích lưu: object store trên VM `gw`

- **MinIO community đã ngừng bảo trì.** Repo `minio/minio` bị archived (04/2026), README ghi "THIS REPOSITORY IS NO LONGER MAINTAINED" và chỉ còn phát hành mã nguồn, không còn binary [CT, [github.com/minio/minio](https://github.com/minio/minio)]. Docs plugin Barman Cloud v0.16.0 cũng không còn dùng MinIO làm ví dụ mà chuyển sang **RustFS** [CT, `object_stores.md`, `usage.md`].
- **RustFS:** Apache-2.0, bản 1.0.0 ra 16/09/2026 (mới nhất 1.0.5, 10/11/2026). Hỗ trợ single-node single-drive (SNSD), có binary và Docker image [CT, GitHub `rustfs/rustfs`]. Bản 1.0 còn mới, độ chín **[CXM]**. RAM khi chạy trên `gw` (2 GB, đang chạy Tailscale và registry) cũng **[CXM]**. `gw` cố ý không cài Docker ([homelab mục 6](../../platform/docs/homelab-hyperv.md#6-registry-image-trên-gw)), nên cài bằng binary và systemd.
- **Lệch chuẩn cần ghi:** `gw` vẫn nằm trên cùng máy bàn và cùng ổ SSD. Đặt backup ở đây chống được việc hỏng cụm hoặc mất node, nhưng **không chống được mất máy**. [db-migration.md](../standards/db-migration.md#lệch-chuẩn-có-chủ-đích-ở-home-lab) đã chấp nhận rủi ro này với lý do dữ liệu lab dựng lại được từ simulator. Muốn chuẩn hơn thì thêm một đích off-site (S3 trên cloud) làm `ObjectStore` thứ hai [SL].
- Thứ tự dựng: RustFS trên `gw`, rồi cert-manager, rồi plugin, rồi `ObjectStore`, rồi `Cluster`. Docs dặn kiểm WAL đã xuất hiện trong bucket trước khi chạy backup đầu tiên [CT, `object_stores.md`].

### 4.3 RTO và diễn tập khôi phục

- **Failover trong cụm:** promote tự động, `.spec.failoverDelay` mặc định 0 giây [CT, `failover.md`]. Thời gian thực tế **[CXM]**, phải đo.
- **PITR:** thời gian phụ thuộc kích thước base backup và lượng WAL cần replay. Mục tiêu N10 là ≤ 15 phút. Với dữ liệu lab vài GB thì có vẻ đạt được [SL]; phải đo.
- **Diễn tập** (N10 ghi rõ "diễn tập khôi phục từ backup"). Đề xuất [SL]:
  1. Ghi lại một mốc thời gian T và checksum dữ liệu (đếm dòng các bảng chính, `flyway_schema_history`).
  2. Tạo `Cluster` `pg-restore-drill` với `bootstrap.recovery`, `recoveryTarget.targetTime: T`, **không** archive WAL.
  3. Chờ `Ready`, chạy truy vấn đối chiếu, ghi RTO (thời điểm apply tới `Ready`) và RPO (giao dịch cuối cùng thấy được so với T).
  4. Xóa cluster diễn tập.
  5. Ghi số đo vào `docs/experiments/`. Lặp lại sau mỗi lần nâng CNPG hoặc plugin.
- Thí nghiệm node chết: `Stop-VM -TurnOff` node chứa primary trong lúc chạy tải. Đo thời gian `-rw` đổi đích, số request lỗi và lượng dữ liệu mất (sẽ là 0 nếu sync replication đang khỏe).

## 5. Connection pooling (PgBouncer) với Flyway và RLS

### 5.1 PgBouncer ở chế độ transaction

Bảng tương thích chính thức [CT, [PgBouncer – Features](https://www.pgbouncer.org/features.html)]:

| Tính năng | Session | Transaction |
|---|---|---|
| `SET`/`RESET` | Có | **Không bao giờ** |
| Advisory lock kiểu session | Có | **Không bao giờ** |
| `PREPARE`/`DEALLOCATE` (SQL) | Có | Không bao giờ |
| Prepared statement mức protocol | Có | Có, khi `max_prepared_statements` ≠ 0 |
| `LISTEN` | Có | Không bao giờ |
| Temp table `ON COMMIT DROP` | Có | Có |

- Ở chế độ `transaction`, server connection trả về pool khi transaction kết thúc. `server_reset_query` (mặc định `DISCARD ALL`) **không chạy** ở chế độ này. `max_prepared_statements` mặc định 200. Lệnh `SET` trên tham số mà PostgreSQL không báo về client thì **có thể rò sang client khác**, trừ khi bật `server_reset_query_always` [CT, [PgBouncer – Config](https://www.pgbouncer.org/config.html)]. Bản PgBouncer mới nhất là 1.26.1 (14/10/2026) [CT, GitHub Releases]. CNPG cần PgBouncer ≥ 1.19 [CT].
- **`SET LOCAL` và `set_config(name, value, is_local => true)`** chỉ có hiệu lực tới hết transaction hiện tại, dù commit hay rollback [CT, [PG 18 – SET](https://www.postgresql.org/docs/18/sql-set.html), [PG 18 – Admin functions](https://www.postgresql.org/docs/18/functions-admin.html)]. Vì vậy chúng **an toàn** với transaction pooling: transaction nằm trọn trên một server connection, và giá trị mất khi connection quay về pool. Bảng của PgBouncer không có dòng `SET LOCAL`; kết luận này suy ra từ ngữ nghĩa của PostgreSQL [SL].
- Tên tham số tự đặt phải có hai phần, kiểu `app.tenant_id` [CT, [PG 18 – Customized options](https://www.postgresql.org/docs/18/runtime-config-custom.html)]. Policy đọc bằng `current_setting('app.tenant_id', true)`; khi chưa đặt thì trả về `NULL` thay vì báo lỗi, nên policy so sánh với `NULL` sẽ trả 0 dòng (fail closed) [CT cho `missing_ok`, [PG 18 – Admin functions](https://www.postgresql.org/docs/18/functions-admin.html)].

**Quy tắc cho code [SL]:** tenant context **chỉ** đặt bằng `set_config('app.tenant_id', :id, true)` ở đầu mỗi transaction, trong cùng transaction với truy vấn. Không bao giờ dùng `SET` thường. Quy tắc này đúng cả khi không có PgBouncer: HikariCP cũng tái dùng connection giữa các request, nên `SET` kiểu session cũng rò giữa các tenant. Cần một test tích hợp chứng minh request của Workspace B, chạy trên connection vừa phục vụ Workspace A, thấy 0 dòng của A (BR-04, N11).

### 5.2 Flyway

- Flyway 12.4.0 trên PostgreSQL gọi `pg_try_advisory_xact_lock` khi `postgresql.transactional-lock=true` (mặc định), và `pg_try_advisory_lock` cùng `pg_advisory_unlock` khi `false` [CT, mã nguồn `PostgreSQLAdvisoryLockTemplate.java` tag `flyway-12.4.0`; [Flyway – PostgreSQL transactional lock](https://documentation.red-gate.com/fd/flyway-postgresql-transactional-lock-setting-277579114.html)].
- [db-migration.md](../standards/db-migration.md) đặt `transactional-lock=false` (để `CREATE INDEX CONCURRENTLY` chạy được), và `init-sqls` dùng `SET lock_timeout` và `SET ROLE`. Cả ba đều thuộc nhóm "Không bao giờ" ở chế độ transaction. Vì vậy **Job migration phải nối thẳng `<cluster>-rw`** (hoặc qua một Pooler `session` riêng, nhưng không cần). Điều này xác nhận điểm **chưa xác minh** ở db-migration.md: Service `-rw` trỏ tới primary, `-ro` tới standby, `-r` tới mọi instance [CT, `architecture.md`].
- Advisory lock kiểu session giữ tới khi unlock hoặc hết session, và **không theo transaction**: rollback vẫn còn giữ lock [CT, [PG 18 – Explicit locking](https://www.postgresql.org/docs/18/explicit-locking.html)]. Đi qua pool transaction thì lock có thể kẹt trên một server connection mà client khác đang dùng [SL].

### 5.3 CNPG `Pooler`

- `Pooler` là một Deployment PgBouncer (số pod tùy chỉnh), `poolMode: session|transaction`, `default_pool_size` mặc định 10 cho mỗi cặp user/database. Nó chỉ đặt database `*` (fallback), nên **một Pooler phục vụ được mọi database của cluster** [CT, `connection_pooling.md`]. Pooler không trải qua nhiều cluster [CT].
- Xác thực: PgBouncer dùng `auth_query` qua `auth_user`/`auth_dbname`, nối tới PostgreSQL bằng client cert. TLS, phần `databases` và `users` do operator quản lý, không chỉnh được [CT].
- Metric PgBouncer có sẵn (`cnpg_pgbouncer_*`). Việc Pooler tự tạo `PodMonitor` đã deprecated [CT].
- Ai nên qua Pooler [SL]:
  - Pod runtime của service: **qua** Pooler `transaction`.
  - Job Flyway: **thẳng** `-rw`.
  - Keycloak: **thẳng** `-rw`. Keycloak tự migrate schema khi khởi động, và docs DB của Keycloak không nhắc tới pooler; chế độ khóa nó dùng **[CXM]**.
  - Keycloak hỗ trợ PostgreSQL 14–18, bản đã test là 18 [CT, [Keycloak – Configuring the database](https://www.keycloak.org/server/db)].

## 6. "Mâu thuẫn" owner và RLS

**Docs CNPG nói:**

- Bootstrap `initdb` tạo user **không đặc quyền** `app` và database `app` thuộc `app`, và viết "Applications should connect to the cluster with the user that owns the application database". Ngay sau đó docs trỏ sang Declarative role management để tạo thêm user [CT, `bootstrap.md`].
- Security: `enableSuperuserAccess` mặc định `false`, "providing developers with full powers inside the database through the database owner user" [CT, `security.md`].
- **FAQ:** user `app` cho phép dev "control migrations using the `app` user", và "Teams can then create another user for read-write operations through the Declarative role management feature and assign the required `GRANT` to the tables" [CT, `faq.md`].

**PostgreSQL nói:** superuser và role có `BYPASSRLS` luôn bỏ qua RLS. **Owner của bảng** thường cũng bỏ qua, trừ khi `ALTER TABLE ... FORCE ROW LEVEL SECURITY`. Chỉ owner bảng được bật, tắt RLS và thêm policy [CT, [PG 18 – Row Security Policies](https://www.postgresql.org/docs/18/ddl-rowsecurity.html)].

**Phân tích:**

- "Owner database" khác "owner bảng". RLS bị bỏ qua theo **owner bảng**. Bảng thuộc về role đã tạo nó. Nếu migration chạy bằng `app` (owner database) thì `app` cũng thành owner bảng, nên runtime chạy bằng `app` sẽ bỏ qua RLS [SL, ghép hai nguồn trên].
- Vì vậy chỗ "mâu thuẫn" chỉ nằm ở câu trong `bootstrap.md`. Chính FAQ của CNPG mô tả đúng mô hình tách quyền: user owner lo migration, user riêng cho đọc ghi và được `GRANT`. Mô hình 3 role của [db-migration.md](../standards/db-migration.md) là bản chặt hơn của mô hình đó, nên **không phải lệch khỏi CNPG**.

**Cách làm đúng:**

1. Mỗi service có các role sau (khai báo bằng `DatabaseRole` hoặc `managed.roles`, mục 2.3):
   - `<svc>_owner`: NOLOGIN, owner database (`Database.spec.owner`), schema và bảng.
   - `<svc>_migrator`: LOGIN, `inRoles: [<svc>_owner]`.
   - `<svc>_app`: LOGIN, chỉ DML.
   - Không role nào có `superuser` hay `bypassrls`.
2. Bootstrap của `Cluster` vẫn bắt buộc tạo một database và owner (mặc định `app`). Đặt nó thành database của một service, hoặc để `app` không dùng tới. Không đưa Secret `<cluster>-app` cho service nào [SL].
3. Migration bật `ENABLE` + `FORCE ROW LEVEL SECURITY` để có thêm lớp chặn khi lỡ chạy bằng owner. Hệ quả [CT, PG docs]: khi đã `FORCE`, backfill chạy bằng owner cũng **bị policy lọc**. Backfill phải tự đặt `app.tenant_id` theo từng tenant, hoặc dùng policy riêng cho role migrator; quyết định khi viết spec.
4. `<svc>_migrator` là thành viên của owner. Với `INHERIT` (mặc định), nó có được coi là "owner" khi xét RLS hay không: **[CXM]**. Đã có `SET ROLE <svc>_owner` cộng `FORCE` thì kết quả như nhau.

## 7. Monitoring

- Mỗi instance có exporter Prometheus ở cổng 9187, tên cổng `metrics`. Bộ query mặc định nằm trong ConfigMap `cnpg-default-monitoring`, có thể thêm query tự định nghĩa qua ConfigMap hoặc Secret, và bật TLS bằng `.spec.monitoring.tls.enabled` [CT, `monitoring.md`].
- `.spec.monitoring.enablePodMonitor` **deprecated**. Docs khuyên tự tạo `PodMonitor`, hợp với việc quản lý trong repo `gitops` [CT].
- Dashboard Grafana chính thức ở `cloudnative-pg/grafana-dashboards` (`charts/cluster/grafana-dashboard.json`). Có `PrometheusRule` mẫu ở `docs/src/samples/monitoring/prometheusrule.yaml`. Quickstart dùng `kube-prometheus-stack`, cũng là stack trong [observability.md](../standards/observability.md) [CT, `quickstart.md`].
- Metric backup lấy từ plugin (mục 4.1). Alert "không có backup thành công trong 25 giờ" và "WAL archive lỗi" nên dựa trên metric của plugin [SL].
- PgBouncer: metric `cnpg_pgbouncer_*` (pool, `xact_time`, `client_wait`...). 1.30.1 sửa lỗi metric trả về 0 khi PgBouncer đổi thứ tự cột [CT, release notes 1.30.1].

## 8. Điểm chưa xác minh và chỗ nguồn mâu thuẫn

**Chưa xác minh:**

1. CNPG 1.31 có hỗ trợ chính thức Kubernetes 1.37 không, và khi nào phát hành (dự kiến 09/2026 nhưng đã trễ).
2. Mất node hẳn: CNPG có tự dựng lại instance ở node khác khi PVC `local-path` mắc ở node chết không, hay bắt buộc `kubectl cnpg destroy`.
3. Resources mặc định của sidecar Barman Cloud và của pod `Pooler`. RAM của cert-manager và RustFS.
4. Độ chín của RustFS 1.0.x khi làm đích backup.
5. Keycloak dùng loại lock nào khi migrate, và có chạy được qua PgBouncer `transaction` không.
6. Thành viên `INHERIT` của owner có được tính là owner khi xét RLS không.
7. Thời gian failover và thời gian PITR thực tế. Cả hai cần số đo.

**Mâu thuẫn hoặc không nhất quán giữa các nguồn:**

- CNPG `bootstrap.md` ("app kết nối bằng owner") so với `faq.md` ("tạo user khác để đọc ghi và `GRANT`"). Xử lý ở mục 6.
- CNPG FAQ khuyên một database mỗi cluster, nhưng ngân sách RAM của homelab buộc dùng chung. Đây là lệch có chủ đích, cần ghi ADR.
- Supported releases ghi 1.31 "~ Sep 2026", nhưng tới 12/11/2026 chưa có release. Ngày trên trang đã lỗi thời.
- Homelab và standard hiện nói "MinIO/S3 trên `gw`" hoặc "backup lên đĩa trong lab". MinIO community đã archived, và plugin không ghi ra đĩa mà chỉ ghi ra object store. Hai tài liệu này cần cập nhật khi ticket chốt.
- Standard `db-migration.md` dùng `spec.managed.roles`, trong khi docs 1.30 gọi `DatabaseRole` là cách "recommended". Mỗi cách có lợi riêng (mục 2.3).

---

## Đề xuất cho ticket 03

| Quyết định | Đề xuất | Đã loại | Lý do chính |
|---|---|---|---|
| Operator | **CloudNativePG 1.30.1** (kế hoạch nâng 1.31 khi ra, để có hỗ trợ K8s 1.37) | Zalando (không exporter, DB/role là map trong CR lớn); Crunchy (image ràng buộc Developer terms, chưa hỗ trợ K8s 1.37); StatefulSet tự viết | Có CRD `Database`/`DatabaseRole`/`Pooler`, có health check Argo CD sẵn, operator 100 Mi |
| PostgreSQL | **18** (image `standard`, 18.6) | 17 | 18 là bản mới nhất được hỗ trợ (EOL 11/2030). Image `system` deprecated; `standard` dùng với plugin Barman [CT, `cloudnative-pg/postgres-containers` README]. Keycloak test trên 18 |
| Topology | **Một `Cluster` `pg-main` ở namespace `postgres`**, mỗi service (và Keycloak, `shopee-sim`) một `Database` cùng bộ role riêng; `REVOKE CONNECT ... FROM PUBLIC`, `pg_hba` theo database và role, `connectionLimit` từng role | Mỗi service một cluster | RAM. Ranh giới sở hữu giữ bằng role và quyền (C1 vẫn đúng ở mức logic) |
| HA | `instances: 2`, `podAntiAffinityType: required`, `synchronous: {method: any, number: 1, dataDurability: preferred}`, PDB bật, resources `requests = limits` (QoS Guaranteed, docs khuyên) | 3 instance (RAM); `required` durability (2 instance thì dừng ghi khi mất một node) | Mất một node vẫn ghi được, RPO = 0 khi cả hai khỏe |
| Backup | Plugin Barman Cloud v0.16.0 cùng cert-manager. `ObjectStore` trỏ tới **RustFS trên `gw`**, WAL nén, `archive_timeout: 1min`, `ScheduledBackup` hằng ngày, `retentionPolicy: "14d"` (số ngày [SL]) | In-tree `barmanObjectStore` (gỡ ở 1.31); volume snapshot (`local-path` không có); MinIO (archived); `pg_dump` (docs: không dùng được cho business continuity) | N10 (RPO ≤ 1 phút). Ghi lệch chuẩn: đích backup cùng máy vật lý |
| Diễn tập | Runbook PITR ra cluster mới (mục 4.3), đo RTO và RPO, ghi `docs/experiments/` | — | N10 bắt buộc diễn tập |
| Pooling | `Pooler` `pg-main-pooler-rw`, `poolMode: transaction`, 2 pod, cho runtime. Job Flyway và Keycloak nối thẳng `pg-main-rw` | Không pooler (pod runtime và surge khi rollout dễ vượt `max_connections` 100); pooler `session` (không giảm số connection) | Tenant context **bắt buộc** `set_config(..., true)` trong transaction, có test rò tenant |
| Role và RLS | 3 role `<svc>_owner`/`_migrator`/`_app` như db-migration.md; không dùng user `app` của bootstrap cho runtime; `FORCE ROW LEVEL SECURITY` | App dùng owner | Khớp FAQ của CNPG; owner bảng bỏ qua RLS |
| Khai báo role | `DatabaseRole` trong app `platform` (namespace `postgres`); Argo CD self-heal bù việc `DatabaseRole` không tự sửa drift | `managed.roles` (một CR `Cluster` to, mọi đổi role chạm vào Cluster) | Quyền ghi CR này tương đương superuser, nên chỉ project `platform` được ghi |
| Monitoring | `PodMonitor` tự viết cho `Cluster` và `Pooler`, dashboard chính thức, `PrometheusRule` mẫu cộng alert backup từ metric plugin | `enablePodMonitor` (deprecated) | |
| Argo CD | Tự viết health check Lua cho `Pooler`, `DatabaseRole`, `ScheduledBackup`, `ObjectStore`; `Delete=false` cho `Cluster` và `ObjectStore` | — | 3.6.1 mới có sẵn check cho `Cluster`, `Database`, `Backup` |

Cần cập nhật sau khi chốt (thuộc spec, không làm trong ticket này):

- [db-migration.md](../standards/db-migration.md): `-rw` đã xác minh; đổi "backup lên đĩa" thành object store trên `gw`; cân nhắc `DatabaseRole`.
- [gitops-argocd.md](../standards/gitops-argocd.md): danh sách health check built-in.
- [Homelab](../../platform/docs/homelab-hyperv.md): bảng operator, thêm cert-manager và RustFS.
- Có thể viết standard mới `docs/standards/postgres-cnpg.md`.

## Nên viết ADR

1. **Một cluster PostgreSQL dùng chung cho mọi service (lệch khuyến nghị của CNPG).** Đây là trade-off thật: RAM đổi lấy cô lập, PITR riêng và nâng cấp riêng. Đảo ngược thì tốn công (tách database ra cluster mới). Ghi điều kiện để tách, ví dụ khi nâng RAM lên 64 GB hoặc khi một service cần PITR riêng.
2. **Phân quyền DB 3 role và tenant context bằng `SET LOCAL` qua PgBouncer transaction.** Gộp vào ADR multi-tenancy (C8) mà db-migration.md đã gợi ý. Bối cảnh dễ gây bất ngờ: docs CNPG bảo dùng owner, và lệnh `SET` thường làm rò tenant khi đi qua pool.
3. (Tùy chọn) **Đích backup trên `gw` cùng máy vật lý.** Có thể chỉ cần ghi trong standard như một lệch chuẩn, không cần ADR riêng.

## Nguồn

- CloudNativePG 1.30.1, docs nguồn `github.com/cloudnative-pg/cloudnative-pg/tree/v1.30.1/docs/src` (tương ứng `cloudnative-pg.io/docs/1.30/`): `faq.md`, `bootstrap.md`, `security.md`, `declarative_database_management.md`, `declarative_role_management.md`, `connection_pooling.md`, `architecture.md`, `storage.md`, `scheduling.md`, `failure_modes.md`, `failover.md`, `replication.md`, `kubernetes_upgrade.md`, `kubectl-plugin.md`, `backup.md`, `wal_archiving.md`, `recovery.md`, `postgresql_conf.md`, `resource_management.md`, `postgres_upgrades.md`, `monitoring.md`, `quickstart.md`. [Supported releases](https://cloudnative-pg.io/docs/1.30/supported_releases/). [Release v1.30.0](https://github.com/cloudnative-pg/cloudnative-pg/releases/tag/v1.30.0), [v1.30.1](https://github.com/cloudnative-pg/cloudnative-pg/releases/tag/v1.30.1). Manifest `cnpg-1.30.1.yaml`.
- Plugin Barman Cloud v0.16.0: `github.com/cloudnative-pg/plugin-barman-cloud/tree/v0.16.0/web/docs` (`intro.md`, `installation.mdx`, `usage.md`, `object_stores.md`, `retention.md`, `concepts.md`, `observability.md`), tương ứng [cloudnative-pg.io/plugin-barman-cloud](https://cloudnative-pg.io/plugin-barman-cloud/).
- [cloudnative-pg/postgres-containers README](https://github.com/cloudnative-pg/postgres-containers), [cloudnative-pg/grafana-dashboards](https://github.com/cloudnative-pg/grafana-dashboards).
- Zalando postgres-operator v2.0.3: [README](https://github.com/zalando/postgres-operator), [release v2.0.1](https://github.com/zalando/postgres-operator/releases/tag/v2.0.1), `manifests/postgres-operator.yaml`, `manifests/configmap.yaml`, `docs/reference/cluster_manifest.md`, `docs/user.md`, `docs/administrator.md`.
- Crunchy PGO v6.0.2: [README](https://github.com/CrunchyData/postgres-operator), `config/manager/manager.yaml`, [Supported Platforms](https://access.crunchydata.com/documentation/postgres-operator/latest/overview/supported-platforms), [Developer Program terms](https://www.crunchydata.com/developers/terms-of-use).
- PostgreSQL 18: [Versioning policy](https://www.postgresql.org/support/versioning/), [Row Security Policies](https://www.postgresql.org/docs/18/ddl-rowsecurity.html), [Privileges](https://www.postgresql.org/docs/18/ddl-priv.html), [SET](https://www.postgresql.org/docs/18/sql-set.html), [System administration functions](https://www.postgresql.org/docs/18/functions-admin.html), [Customized options](https://www.postgresql.org/docs/18/runtime-config-custom.html), [Explicit locking](https://www.postgresql.org/docs/18/explicit-locking.html), [WAL configuration](https://www.postgresql.org/docs/18/runtime-config-wal.html).
- PgBouncer: [Features](https://www.pgbouncer.org/features.html), [Configuration](https://www.pgbouncer.org/config.html), [Releases](https://github.com/pgbouncer/pgbouncer/releases).
- Flyway: [PostgreSQL transactional lock](https://documentation.red-gate.com/fd/flyway-postgresql-transactional-lock-setting-277579114.html), mã nguồn `flyway-database-postgresql/.../PostgreSQLAdvisoryLockTemplate.java` tag `flyway-12.4.0`.
- Argo CD v3.6.1: `resource_customizations/postgresql.cnpg.io/{Cluster,Database,Backup}/health.lua`.
- Keycloak: [Configuring the database](https://www.keycloak.org/server/db).
- Object storage: [minio/minio](https://github.com/minio/minio) (archived), [rustfs/rustfs](https://github.com/rustfs/rustfs).
