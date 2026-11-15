# Runbook: bảo trì node đang chạy `pg-main`

Đưa node đang chứa primary của `pg-main` ra bảo trì (cập nhật OS, nâng Kubernetes, thay phần cứng) khi cluster chỉ có 1 instance và dùng volume `local-path` gắn với node.

- Ticket: [G0-08](../.scratch/g0-platform/issues/08-pg-main.md) bước 8. Chuẩn: [postgres-cnpg.md, mục "Drain node và PDB"](../standards/postgres-cnpg.md). ADR: [0004](../adr/0004-single-instance-by-default-on-homelab.md).
- Phiên bản: CloudNativePG **1.30.1**, PostgreSQL 18.7, PgBouncer 1.25.2, Kubernetes 1.37.2 (2 worker `k8s-w1`, `k8s-w2`).
- Diễn tập ngày 2026-11-15 trên `k8s-w1`: commit gitops `f716c46` (lên 2 instance) và `814e7f4` (về 1). Primary chuyển từ `pg-main-1` (`k8s-w1`) sang `pg-main-2` (`k8s-w2`).
- Docs gốc: [Kubernetes upgrade and maintenance](https://cloudnative-pg.io/docs/1.30/kubernetes_upgrade/).

## Mô hình trong một đoạn

- Operator tạo PDB `pg-main-primary` (`minAvailable: 1`) cho pod primary. Với 1 instance, `ALLOWED DISRUPTIONS` luôn là 0, nên **`kubectl drain` không evict được pod PostgreSQL**: drain thử lại mỗi 5 giây tới khi hết `--timeout`. Docs nói thẳng: cluster 1 instance thì không switchover được, nên operator chặn drain node chứa nó.
- Pod không chuyển được sang node khác vì PVC `local-path` gắn với node. Tắt PDB (`enablePDB: false`) thì drain qua được, nhưng pod nằm `Pending` và database ngừng suốt thời gian bảo trì.
- Có replica thì operator **tự switchover** khi node của primary bị cordon (docs: "a switchover happens ahead of the drain"). Đã thấy trong diễn tập: chỉ cần node đang cordon, replica vừa Ready là operator switchover ngay, chưa cần chạy drain lần hai.
- Cách chọn: giữ PDB, **tạm lên 2 instance** để switchover, rồi về 1. Gián đoạn chỉ bằng thời gian switchover thay vì cả thời gian bảo trì, và không phải lệch chuẩn (giữ `enablePDB: true`).

## Kết quả diễn tập (2026-11-15)

Một pod đo trên `k8s-w2` mở kết nối mới mỗi khoảng 0,55 giây, mỗi lần thử cả qua Pooler lẫn thẳng `pg-main-rw` (`hello_app`, `connect_timeout=2`).

| Mốc (UTC) | Sự kiện |
|---|---|
| 02:52:35 | `kubectl drain k8s-w1 --pod-selector=cnpg.io/cluster=pg-main --timeout=40s`: node bị cordon; 9 lần evict trong 40 giây đều `Cannot evict pod as it would violate the pod's disruption budget`; drain hết giờ. PostgreSQL không gián đoạn |
| 02:53:56 | Push commit `instances: 2` |
| 02:54:09 | Replica `pg-main-2` Ready trên `k8s-w2` (13 giây; database nhỏ, `pg_basebackup` qua job `-join`) |
| 02:54:18 | Operator tự switchover (`Switchover in progress`) |
| 02:54:25 | `pg-main-2` là primary; `pg-main-1` thành replica |
| 02:54:49 | Push commit `instances: 1`; 10 giây sau operator xóa `pg-main-1` **và PVC của nó**, không chạm primary |
| 02:55:0x | Drain lại `k8s-w1`: xong ngay (không còn pod PostgreSQL); `uncordon` |

| Đường kết nối | Gián đoạn (lần OK cuối → lần OK đầu) | Lỗi client thấy |
|---|---|---|
| Thẳng `pg-main-rw` | **7,5 s** (02:54:17,5 → 02:54:25,0) | `Connection refused` |
| Qua `pg-main-pooler-rw` | **khoảng 15 s** (02:54:17,5 → sau 02:54:32,3) | `timeout expired`, rồi `FATAL: server login has been failing, cached error ... (server_login_retry)` |
| Lúc về 1 instance | 0 lỗi (96/96 OK) | — |

Qua Pooler gián đoạn lâu hơn khoảng 8 giây vì PgBouncer cache lỗi đăng nhập vào server trong `server_login_retry` (mặc định 15 s): PostgreSQL đã sống lại nhưng PgBouncer vẫn trả lỗi đã cache. Sau diễn tập đã đặt `server_login_retry: "2"` cho Pooler ([postgres-cnpg.md](../standards/postgres-cnpg.md) mục "Pooler"); gián đoạn qua Pooler sau thay đổi **chưa đo lại**, đo ở lần bảo trì kế tiếp và cập nhật bảng này.

Dữ liệu sau switchover: đủ 5 role (thuộc tính đúng), 2 database (`hello`, `keycloak`) đúng owner, 3 luật `pg_hba`; mọi `DatabaseRole`, `Database` vẫn `APPLIED true`.

## Quy trình

Làm khi Pooler và service có thể chịu khoảng 15 giây không mở được kết nối mới. Mọi thay đổi số instance đi qua Git: sửa tay thì Argo CD `selfHeal` trả về.

1. **Kiểm node còn lại đủ chỗ** cho instance thứ hai (1 CPU, 1 024 Mi, QoS `Guaranteed`):
   ```bash
   kubectl describe node <node-còn-lại> | sed -n '/Allocated resources/,/Events/p'
   ```
2. **Cordon node cần bảo trì**, để replica mới không rơi vào chính node đó:
   ```bash
   kubectl cordon <node>
   ```
3. **Lên 2 instance**: sửa `instances: 2` trong `gitops/infra/pg-main/cluster.yaml`, commit, push. Theo dõi tới khi primary đã sang node khác:
   ```bash
   kubectl get cluster pg-main -n postgres -w      # PRIMARY đổi sang pod trên node khác, STATUS "Cluster in healthy state"
   ```
4. **Về 1 instance**: sửa lại `instances: 1`, commit, push. Operator xóa replica (pod cũ trên node bảo trì) và PVC của nó.
   ```bash
   kubectl get pod,pvc -n postgres -l cnpg.io/cluster=pg-main
   ```
5. **Drain node** (giờ không còn pod PostgreSQL trên đó). Bảo trì thật thì drain cả node, không dùng `--pod-selector`:
   ```bash
   kubectl drain <node> --ignore-daemonsets --delete-emptydir-data --timeout=5m
   ```
6. Làm việc bảo trì, rồi `kubectl uncordon <node>`.
7. **Kiểm**: `kubectl get application pg-main -n argocd` `Synced/Healthy`; `kubectl get databaserole,database -n postgres` đều `APPLIED true`; `kubectl get cluster pg-main -n postgres` 1/1 healthy.

Ghi chú:
- Primary ở lại node mới sau bảo trì; không cần đưa về. Mọi lệnh tìm pod primary bằng `kubectl get cluster pg-main -n postgres -o jsonpath='{.status.currentPrimary}'`, không ghi cứng `pg-main-1`.
- Trong lúc 2 instance, cả hai đều giữ `max_connections` riêng; ngân sách kết nối của từng role không đổi vì role chỉ ghi được trên primary.
- PV `local-path` có `reclaimPolicy: Delete`: PVC của replica bị xóa ở bước 4 là dữ liệu trên node cũ mất theo. Đúng ý, vì primary mới giữ đủ dữ liệu; nhưng **đừng** về 1 instance trước khi primary đã chuyển xong (bước 3).
- Diễn tập dùng `--pod-selector=cnpg.io/cluster=pg-main` để không evict workload khác trên `k8s-w1` (operator, Argo CD, CoreDNS). Operator chỉ có 1 replica và webhook `failurePolicy: Fail`: drain cả node làm operator khởi động lại, trong khoảng đó API server từ chối tạo/sửa CR của CNPG.

## Phương án đã loại

| Cách | Gián đoạn | Vì sao không chọn |
|---|---|---|
| `enablePDB: false` tạm thời (docs khuyên cho cluster dev 1 instance) | Cả thời gian bảo trì: pod `Pending` vì PVC gắn node | Gián đoạn dài; phải lệch chuẩn (tắt PDB) dù chỉ tạm |
| `nodeMaintenanceWindow` với `reusePVC: true` | Như trên | Docs gọi là cách cũ, giữ để tương thích ngược |
| Để nguyên 1 instance, drain không `--timeout` | Drain treo vô hạn | Không bảo trì được |
