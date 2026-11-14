# 03: Bootstrap Argo CD theo app-of-apps

Status: resolved
Blocked by: 02
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

Từ cụm trắng, hai lệnh tay dựng Argo CD v3.6.1, rồi Argo CD tự quản lý chính nó từ repo `gitops`. Root `Application` của môi trường `lab` quản lý mọi app khác. Project `default` bị khóa; có project `platform` cho hạ tầng và `commerce` cho service; có `ApplicationSet` quét thư mục values của service (G0 chưa có service nào). Theo mục "Cài đặt và bootstrap", "Cấu trúc Application", "AppProject", "Sync policy", "Sync waves" của [gitops-argocd.md](../../../standards/gitops-argocd.md). Dex và notifications tắt theo [ADR-0004](../../../adr/0004-single-instance-by-default-on-homelab.md).

## Mục tiêu học

- GitOps mô hình pull: app-of-apps, sync wave, health check của `Application`.
- AppProject làm ranh giới quyền: vì sao project `default` phải khóa.

## Tiêu chí nghiệm thu

- [x] Runbook bootstrap ghi đúng hai lệnh; đo số phút từ cụm trắng tới khi mọi app `Synced/Healthy`.
- [x] `argocd version --short` trả server `v3.6.1`; app tự quản lý Argo CD dùng `ServerSideApply=true`.
- [x] Health check Lua cho `Application` có trong `argocd-cm`; wave sau chờ app trước `Healthy`.
- [x] Self-heal: scale một Deployment thử về 0, Argo CD trả về; ghi số giây.
- [x] Prune: xóa một resource khỏi Git, nó biến khỏi cụm.
- [x] App trong `commerce` trỏ namespace `argocd` hoặc thêm `ClusterRole` thì sync bị từ chối.
- [x] Limit memory của các thành phần Argo CD đúng bảng ngân sách ticket 04 của map.

## Lộ trình

Duyệt ngày 2026-11-14. Hiện trạng lúc lập: cụm chưa có namespace `argocd`, `gitops` mới có commit khung, Mac chưa cài CLI `argocd`. Quyết định khi duyệt: ba AppProject (`default` khóa, `platform`, `commerce`) đặt trong `bootstrap/argocd/` để lệnh 1 tạo chúng trước root app (root app thuộc `platform`, `default` đã khóa).

**Đổi quyết định ở bước 4 (2026-11-14):** AppProject chuyển sang `apps/lab/projects.yaml`, đúng chỗ chuẩn ghi. Lý do: `kubectl apply` tra discovery một lần cho cả batch, nên CR `AppProject` nằm chung lệnh với CRD của nó bị bỏ qua và lệnh thoát mã 1 (thử bằng `--dry-run=server` với một CRD và CR mẫu: `resource mapping not found … ensure CRDs are installed first`). Lệnh 2 thành `kubectl apply -f apps/lab/projects.yaml -f apps/root-lab.yaml` (client-side, vì project `default` do Argo CD tự tạo, server-side apply sẽ xung đột field; kiểm ở bước 6); sau đó root app quản lý `projects.yaml`. Đánh đổi: hỏng project `platform` trong Git thì root app không tự sửa được, phải `kubectl apply` tay. Cập nhật dòng lệnh bootstrap trong [gitops-argocd.md](../../../standards/gitops-argocd.md) ở bước 12.

- [x] 1. `bootstrap/argocd/kustomization.yaml`: Namespace `argocd` + `install.yaml` ghim `v3.6.1`. Kiểm: `kubectl kustomize bootstrap/argocd` ra 61 resource; 8 image `quay.io/argoproj/argocd` đều `v3.6.1` (Dex `v2.46.0` và Redis `8.10.1-alpine` có tag riêng); mọi resource namespaced nằm ở `argocd`.
- [x] 2. Patch Kustomize: xóa Dex, notifications; memory request = limit theo ngân sách (controller 512, repo-server 256, server 128, redis 64, applicationset 64 MiB). Kiểm: kết quả build không còn `dex`/`notifications`, limit đúng bảng.
- [x] 3. Patch `argocd-cm`: health check Lua `resource.customizations.health.argoproj.io_Application`; cài CLI `argocd` v3.6.1 (đưa lên từ bước 5) để thử Lua offline. Kiểm: `argocd-cm` có 10 key (9 gốc + 1, merge không thay); `argocd admin settings resource-overrides health` trả `Progressing` (chưa có status), `Healthy`, `Degraded` + message; với `argocd-cm` gốc trả "Health script is not configured".
- [x] 4. Ba AppProject trong `apps/lab/projects.yaml`. Kiểm: `yq` thấy `argocd/default`, `argocd/platform`, `argocd/commerce`; `commerce` chỉ đích `hello`, cấm 4 Kind; sau bước 5 `kubectl apply --dry-run=server -f apps/lab/projects.yaml`; sau bước 6 `argocd proj get`.
- [x] 5. Lệnh tay 1 `kubectl apply --server-side -k bootstrap/argocd`; port-forward, đăng nhập `admin`. Kiểm: `argocd version --short` server `v3.6.1`; pod `Ready`; ghi `kubectl top pods -n argocd`; `kubectl apply --dry-run=server -f apps/lab/projects.yaml` không lỗi.
  - Kết quả 2026-11-14: chủ repo chạy lệnh 1 lúc 15:48:31 (47 `serverside-applied`, 0 lỗi, 3 s); Claude chạy lại cùng lệnh lúc 15:48:43 khi pod đang khởi động, cũng 47 `serverside-applied`, không conflict (cùng field manager `kubectl`, không đổi gì). Từ lệnh đầu tới khi pod cuối (`argocd-server`) `Ready` lúc 15:49:27: **56 s** (đọc `creationTimestamp` và `Ready.lastTransitionTime` của pod). `repo-server` có một event `secret "argocd-redis" not found` lúc 15:48:52: Secret này do init `secret-init` của Redis tạo, repo-server khởi động trước nên thử lại rồi tự ổn, không restart. 5 pod `Running`, 0 restart, QoS `Burstable`, request/limit đúng bước 2 (init `copyutil` 256Mi, `secret-init` 64Mi). Server `v3.6.1`: `/api/version` qua API server proxy, và sau khi chủ repo đăng nhập `admin` qua port-forward, `argocd version --short` trả `argocd: v3.6.1`, `argocd-server: v3.6.1`. Namespace `argocd` gắn Pod Security `restricted` (`enforce-version: v1.37`); pod `argocd-server` tạo lại sau khi gắn nhãn vẫn được nhận.
  - RAM lúc rảnh, chưa có app nào (`kubectl top pods --containers`, 15:49:46): controller 32Mi, applicationset 32Mi, redis 10Mi, repo-server 23Mi, server 47Mi; tổng 144Mi / ngân sách 1 024Mi. Node: `k8s-w1` 1 442→1 608Mi, `k8s-w2` 1 399→1 455Mi. 4/5 pod nằm trên `k8s-w1` do pod affinity "preferred" `part-of: argocd` trong `install.yaml`.
  - `projects.yaml` dry-run server: 3 project hợp lệ. `default` do Argo CD tự tạo đang mở hoàn toàn (`sourceRepos: [*]`, đích `*/*`); client-side apply chỉ cảnh báo thiếu `last-applied` rồi tự vá, khẳng định lệnh 2 dùng client-side được. API cảnh báo tên finalizer không có `/` (tên do Argo CD định nghĩa, bỏ qua).
  - Pod Security `restricted` dry-run cho namespace `argocd`: không cảnh báo nào.
- [x] 6. `apps/root-lab.yaml` + `apps/lab/argocd.yaml` (tự quản lý, `ServerSideApply=true`, automated + retry); lệnh tay 2 `kubectl apply -f apps/lab/projects.yaml -f apps/root-lab.yaml`. Kiểm: `root-lab`, `argocd` `Synced/Healthy`; `argocd app diff argocd` rỗng; `argocd proj get default` không còn nguồn, đích.
  - Thiết kế: root và app `argocd` không có finalizer (xóa nhầm không cascade); root không tự quản lý (nằm ngoài `apps/lab/`); Namespace `argocd` có `Prune=false`; AppProject wave `-1`, app `argocd` wave `0`. Trước khi push: `kubectl diff --server-side -k bootstrap/argocd` chỉ khác annotation `Prune=false`.
  - Kết quả 2026-11-14: lệnh 2 lúc 16:46:15; `root-lab` `Synced/Healthy` sau 10 s, `argocd` `Synced/Healthy` sau **11 s**, không restart pod nào. `argocd app diff` rỗng cho cả hai. `argocd-cm` và Namespace có hai field manager `kubectl` (Apply, từ lệnh 1) và `argocd-controller` (Apply).
  - **Phát hiện:** `argocd proj get default` vẫn `Allowed Cluster Resources: */*`. Project `default` do Argo CD tự tạo với `*/*`; apply giữ nguyên field manifest không nhắc tới, và diff cũng không so field đó, nên app vẫn `Synced`. Manifest khóa `default` trong docs cũng bỏ trống field này. Sửa: ghi tường minh `clusterResourceWhitelist: []` (commit `ad9564a`); sau sync `Allowed Cluster Resources: <none>`. Bài học: "không khai" khác "rỗng" khi apply lên object đã có sẵn.
  - RAM sau khi có 2 app (16:48): controller **365Mi**/512Mi (lúc rảnh 32Mi), repo-server 67Mi, server 67Mi, applicationset 34Mi, redis 10Mi. Controller tăng mạnh vì bắt đầu cache mọi resource của cụm; đo lại ở bước 8 và sau 24 giờ (ticket 34) trước khi kết luận limit 512Mi đủ.
- [x] 7. `ApplicationSet` service quét `envs/lab/*`, `project: commerce` viết cứng. Kiểm: 0 app; thêm thư mục giả sinh 1 app rồi xóa.
  - Thiết kế (`apps/lab/services.yaml`, commit `0ea941c`): `goTemplate` + `missingkey=error`; tên app `svc-{{.path.basename}}` để không trùng app hạ tầng; namespace và release là tên thư mục; multi-source chart `app` `0.1.0` từ `10.20.0.5:5000/charts` (không tiền tố `oci://`) + `ref: values`; chart version chung trong template; `PruneLast`, `FailOnSharedResource`; wave `100`. Chưa chạy được đầu-cuối: chart publish ở G0-21, registry vào `sourceRepos` của `commerce` ở G0-24.
  - Kết quả 2026-11-14: root tạo `services-lab` `Synced/Healthy`, condition `ResourcesUpToDate=True`, 0 app. Thêm `envs/lab/probe/` (commit `cc6c93a`) + annotation refresh: `svc-probe` xuất hiện sau 1 s, project `commerce`, finalizer `resources-finalizer` do ApplicationSet tự thêm, ownerReference `ApplicationSet/services-lab`; app bị chặn bởi hai `InvalidSpecError` của project (`namespace 'probe' do not match any of the allowed destinations`, `repo 10.20.0.5:5000/charts is not permitted`). Xóa thư mục (commit `3e217e2`): `svc-probe` bị xóa sau 2 s. RAM controller 369Mi.
- [x] 8. Sandbox hai app wave 1 (pod `Ready` chậm 60 giây) và wave 2. Kiểm: mốc thời gian cho thấy wave 2 bắt đầu sau khi wave 1 `Healthy`.
  - Thiết kế (commit `0c4eb71`): `apps/lab/sandbox-slow.yaml` (wave 1) và `sandbox-fast.yaml` (wave 2), project `platform`, có finalizer; `sandbox/slow` = Namespace `sandbox` (Pod Security `restricted`) + Deployment busybox `readinessProbe` `initialDelaySeconds: 60`; `sandbox/fast` = Deployment không delay + ConfigMap `prune-me` cho bước 9.
  - Kết quả 2026-11-14 (UTC): root sync 10:13:48 → 10:15:01. `sandbox-slow` tạo 10:13:53, `Healthy` 10:14:58 (**65 s**, pod Ready đúng lúc đó); `sandbox-fast` tạo **10:14:59**, 1 s sau khi wave 1 `Healthy`. Trong lúc chờ, `root-lab` ở `Running` với message `waiting for healthy state of argoproj.io/Application/sandbox-slow` (trước đó cũng chờ `Application/argocd` ở wave 0).
  - Quan sát: `argocd app get root-lab --refresh` lúc 17:12:43 (giờ VN) nhưng root chỉ thấy commit mới và bắt đầu sync lúc 17:13:48 (~65 s). Refresh thường còn dùng cache phân giải `main` → SHA; muốn thấy ngay dùng `--hard-refresh`. Production dùng webhook GitHub để bỏ độ trễ polling (3 phút); ghi lại cho ticket 24 khi đo lead time.
  - RAM controller sau khi có 4 app: **451Mi**/512Mi (working set). Đọc metrics Go qua port-forward cổng 8082: `heap_alloc` 131MiB, `heap_inuse` 147MiB, `heap_idle` 227MiB (156MiB đã trả OS), `sys` 399MiB, RSS 390MiB, `GOMEMLIMIT` không đặt (= MaxInt64), `GOGC` 100; cache 615 object của cụm. Phần lớn là bộ nhớ Go chưa trả lại chứ không phải dữ liệu sống; Go không biết trần 512Mi của container nên có rủi ro OOMKilled lúc cache phình.
  - **Thêm ngoài lộ trình (chủ repo duyệt):** `GOMEMLIMIT` ≈ 90% memory limit cho 4 thành phần Go (controller 460MiB, repo-server 230MiB, server 115MiB, applicationset 58MiB) trong `resources-patch.yaml` (commit `2c27118`); SMP trộn `env` theo `name`, giữ nguyên env gốc. Đây cũng là lần đầu Argo CD tự nâng cấp chính nó qua Git: push 17:17:13 → `--hard-refresh` → app `argocd` `OutOfSync` → rollout 4 pod → `Synced/Healthy` sau ~43 s, pod `argocd-server` cũ terminate xong ở ~65 s; 0 restart, server vẫn `v3.6.1`. `kubectl diff --server-side -k bootstrap/argocd` (không `--force-conflicts`) giờ báo `conflict with "argocd-controller"`, đúng dự đoán: sau khi Argo CD tiếp quản, chạy lại lệnh 1 phải kèm `--force-conflicts` (ghi vào runbook bước 11). Metrics sau rollout: `go_gc_gomemlimit_bytes` 460MiB; controller working set 261Mi (vừa khởi động lại, đo lại ở bước 9 và 12 để so).
- [x] 9. Self-heal và prune trên sandbox. Kiểm: scale 0 → ghi số giây tới khi trả về; xóa resource khỏi Git → biến khỏi cụm.
  - Self-heal (2026-11-14 17:26, script poll 0,2 s): `kubectl -n sandbox scale deploy fast --replicas=0` ba lần liên tiếp. `spec.replicas` trở lại 1 sau **0,3 s / 0,6 s / 5,0 s**; pod `Ready` sau 1,2 / 1,4 / 5,6 s. Lần 1 heal ngay vì controller nhận event qua watch; lần 3 chậm vì backoff self-heal (`controller.self.heal.backoff.timeout.seconds` 2, factor 3, cap 300) tính từ lần heal trước: heal 2 lúc ~33,3 s → heal 3 không sớm hơn ~6 s sau. Event: `Initiated automated sync`, `Partial sync operation … succeeded` (self-heal chỉ sync resource lệch), `initiatedBy.automated: true`.
  - Prune: xóa `sandbox/fast/configmap.yaml` (commit `8d09866`), push 17:26:58, `--hard-refresh` mất 2,0 s, `prune-me` biến khỏi cụm sau **2,1 s** tính từ push. `argocd app get sandbox-fast`: `ConfigMap prune-me … Pruned`. Không refresh tay thì phải chờ poll Git (120 s + jitter 60 s).
  - Sau phép thử: 4 app `Synced/Healthy`, 0 restart. RAM controller 320Mi (10 phút sau khi thêm `GOMEMLIMIT`; trước đó 451Mi khi chưa có).
- [x] 10. App tạm trong `commerce` trỏ namespace `argocd` và app tạm có `ClusterRole`. Kiểm: sync bị từ chối ("not permitted"); xóa app tạm.
  - Cách làm: manifest bị cấm đưa vào Git ở `sandbox/forbidden/clusterrole-quota.yaml` (commit `6e23d50`; `commerce` chỉ đọc nguồn từ repo `gitops`): `ClusterRole` đọc mọi Secret + `ResourceQuota` trong `hello`. Hai app thử tạo tay bằng `kubectl apply` (không qua root, không automated, không finalizer), sync tay bằng `argocd app sync`, rồi xóa.
  - `probe-commerce-dest` (đích `argocd`): ngay khi tạo đã có `InvalidSpecError: application destination server 'https://kubernetes.default.svc' and namespace 'argocd' do not match any of the allowed destinations in project 'commerce'`; sync tay → `Phase: Error`, cùng message.
  - `probe-commerce-kinds`: sync tay → `Phase: Failed`, `one or more synchronization tasks are not valid: resource :ResourceQuota is not permitted in project commerce; resource rbac.authorization.k8s.io:ClusterRole is not permitted in project commerce`. Kiểm ở dry-run của Argo CD, chưa gửi gì lên API server.
  - Phía cụm sau phép thử: `clusterrole probe-commerce-forbidden` `NotFound`, không có `ResourceQuota` nào tên đó, namespace `hello` không tồn tại. Đã xóa hai app thử; 4 app còn lại `Synced/Healthy`.
- [x] 11. Gỡ sandbox; diễn tập cụm trắng (gỡ Argo CD theo thứ tự an toàn, chạy lại hai lệnh, bấm giờ); viết runbook. Kiểm: số phút tới khi mọi app `Synced/Healthy`; runbook ghi đúng hai lệnh.
  - Gỡ sandbox qua Git (commit `c1e1cbb`, 2026-11-14 20:37): xóa `apps/lab/sandbox-{slow,fast}.yaml` và thư mục `sandbox/`, hard-refresh root. Root prune hai app; nhờ finalizer, Argo CD dọn luôn resource, kể cả namespace `sandbox` (`NotFound` sau **19 s**).
  - Gỡ Argo CD theo thứ tự: `root-lab` → `argocd` → `services-lab` → `appproject --all` → `kubectl delete -k bootstrap/argocd`.
    - Bước 1–4 xong trong dưới 1 s. Xóa hai app không kéo theo gì vì chúng không có finalizer. Controller còn sống nên gỡ được finalizer của `platform`/`commerce`.
    - Bước 5 mất 35 s (lần 2: 15 s).
    - Cụm trắng: không namespace `argocd`, 0 CRD `argoproj.io`, 0 ClusterRole/ClusterRoleBinding `argocd-*`, 0 namespace `Terminating`. Các namespace của ticket 02 vẫn nguyên.
  - Diễn tập lần 1 (đúng hai lệnh và lệnh chờ CRD): mọi app `Synced/Healthy` sau **179 s**.
    - Workload Ready ở +38 s, nhưng `root-lab` nằm `Unknown` từ +12 s tới +169 s.
    - Nguyên nhân: lệnh 2 chạy lúc repo-server chưa Ready. Lần so sánh đầu thất bại (`git_ms` 2951), log ghi `Skipping auto-sync: application status is Unknown`. Controller chỉ so sánh lại khi hết `timeout.reconciliation` (log: `comparison expired … expiry: 2m0s`; mặc định 120 s cộng jitter 60 s).
    - Không có retry nào áp dụng ở đây vì sync chưa bắt đầu.
  - Sửa runbook: thêm lệnh chờ chỉ-đọc `kubectl -n argocd wait --for=condition=Available deployment --all` và `rollout status statefulset/argocd-application-controller` trước lệnh 2.
  - Diễn tập lần 2 (gỡ lại theo đúng thứ tự, 2026-11-14 20:42:51), mốc tính từ T0:

    | Mốc | Thời điểm |
    |---|---|
    | Lệnh 1 xong (47 object) | +3 s |
    | CRD `Established` | +4 s |
    | 5 workload Ready, chạy lệnh 2 | +36 s |
    | `argocd` `Synced/Healthy` | +49 s |
    | `root-lab` `Synced/Healthy` và `services-lab` `ResourcesUpToDate=True` | **+50 s** |

    Image đã có sẵn trên node. Lần cài đầu ở bước 5 phải kéo image, pod Ready sau 56 s.
  - Kiểm không lệch sau diễn tập:
    - `kubectl diff --server-side --force-conflicts -k bootstrap/argocd` exit 0.
    - Project `default` vẫn khóa (`sourceRepos`/`destinations`/`clusterResourceWhitelist` rỗng).
    - Namespace `argocd` có `restricted`/`v1.37` và `Prune=false`; `GOMEMLIMIT` đủ 4 thành phần; 0 restart.
  - Bộ nhớ controller: 427Mi ở 79 s sau khi cài, 354Mi ở ~2,5 phút, dù chỉ có 2 app. Mức này gần giống lần trước, nên gánh nặng chủ yếu là cache tài nguyên của cả cụm chứ không phải số app. Theo dõi tiếp ở ticket 34.
  - Runbook: `gitops/bootstrap/README.md` (commit `d8d1b7c`), có link từ `gitops/README.md`. Gồm:
    - điều kiện; hai lệnh và hai lệnh chờ, kèm lý do; bảng số đo; lệnh kiểm;
    - các cảnh báo vô hại; đăng nhập lần đầu (mật khẩu đổi sau mỗi lần cài);
    - nâng cấp (sau bước 12: thay bản vendor `upstream/install.yaml`); `GOMEMLIMIT` đi cùng limit; `--hard-refresh`;
    - cứu hộ bằng lệnh 1 kèm `--force-conflicts`; thứ tự gỡ và lý do.
  - Sau diễn tập, token CLI và tab port-forward cũ đã hết hiệu lực. Cần CLI thì đăng nhập lại theo runbook.
- [x] 12. Kết ticket: số đo vào `docs/experiments/2026-11-g0.md`, `code-review`, sửa chuẩn, mục Bài học. Kiểm: mọi tiêu chí nghiệm thu đã tick.
  - Số đo: [bản ghi G0, mục 2](../../../experiments/2026-11-g0.md#2-argo-cd-bootstrap-ram-self-heal-prune).
  - `code-review` (high) và các bản sửa: xem mục Review. Kiểm sau sửa (2026-11-14 20:59): `kubectl diff --server-side --force-conflicts -k bootstrap/argocd` chỉ khác 3 annotation `Prune=false` trên CRD; push → `root-lab`, `argocd` `Synced/Healthy` sau 9 s, 0 restart.
  - Chuẩn [gitops-argocd.md](../../../standards/gitops-argocd.md) cập nhật: vendor manifest, hai lệnh kèm lệnh chờ, AppProject ở `apps/<env>/`, `--force-conflicts`, ngoại lệ finalizer, `Prune=false` (namespace, CRD, ApplicationSet), `GOMEMLIMIT`, Pod Security, `default` ghi tường minh `clusterResourceWhitelist: []`, `commerce` cấm `Role`/`RoleBinding`, files generator.

## Kết quả

- Bằng chứng: [bản ghi G0, mục 2](../../../experiments/2026-11-g0.md#2-argo-cd-bootstrap-ram-self-heal-prune).
  - Bootstrap từ cụm chưa có Argo CD: **50 s** tới khi mọi app `Synced/Healthy` (179 s nếu thiếu lệnh chờ workload).
  - Self-heal 0,3 / 0,6 / 5,0 s; prune 2,1 s; app wave 2 tạo 1 s sau khi app wave 1 `Healthy`.
  - `commerce` từ chối đích `argocd`, `ClusterRole`, `ResourceQuota`, `RoleBinding`.
  - RAM Argo CD khoảng 500–570 / 1 024 MiB; controller 354–451 / 512 MiB.
- Server `v3.6.1`: `argocd version --short` ở bước 5; sau diễn tập, image `quay.io/argoproj/argocd:v3.6.1`.
- Commit trong `gitops` (từ `bd167a7` tới `d6b1b77`): bootstrap, AppProject, root app, ApplicationSet, runbook [`bootstrap/README.md`](https://github.com/hoangduoc0603/commerce-hub-gitops/blob/main/bootstrap/README.md), các bản sửa theo review. Sandbox và thư mục thử đã gỡ khỏi Git và khỏi cụm.
- Ma trận truy vết: không có dòng tương ứng. Ticket là hạ tầng, không gắn mã F/N riêng (giống G0-02); N12 "0 (khung)" thuộc ticket `hello` có trace.
- Chuyển cho ticket sau:
  - Ticket 34: đo controller 24 giờ sau khi có Kafka, Keycloak, rồi mới chốt limit 512 MiB; CPU request lúc tải; 4/5 pod dồn trên `k8s-w1`.
  - Ticket 12: thay `admin` bằng SSO.
  - Ticket 24: webhook GitHub để bỏ độ trễ poll; thêm registry chart vào `sourceRepos` của `commerce`.

## Review

`code-review` (high) trên `gitops` `ca05ce9..7084dce` ra 8 điểm. Claude sửa cả 8 theo yêu cầu chủ repo (commit `7084dce`):

1. **Root prune ApplicationSet sẽ cascade xóa mọi service.** Sửa: `Prune=false` trên `services-lab`.
2. **CRD `argoproj.io` không được che khỏi prune.** Xóa CRD là xóa mọi Application. Sửa: patch Kustomize gắn `Prune=false` cho kind `CustomResourceDefinition`.
3. **`commerce` cho phép `Role`/`RoleBinding`.** Service có thể tự cấp `cluster-admin` trong namespace rồi vượt blacklist từ trong pod. Sửa: cấm hai Kind này. Kiểm bằng app thử: `resource rbac.authorization.k8s.io:RoleBinding is not permitted in project commerce`.
4. **`install.yaml` tải từ `raw.githubusercontent.com` mỗi lần render, ghim bằng tag dời được.** Sửa: vendor vào `bootstrap/argocd/upstream/install.yaml` (sha256 `7be23ca7…2913e`). Output `kubectl kustomize` trùng từng byte với bản URL, ngoài annotation của điểm 2.
5. **Runbook đòi `ghcr.io` dù Dex đã gỡ.** Sửa điều kiện, thêm quy trình nâng cấp bản vendor.
6. **Comment CPU request lỗi thời.** Ghi số đo và lý do giữ request.
7. **Directory generator sinh app lỗi cho thư mục thiếu `values.yaml`.** Sửa: files generator `envs/lab/*/values.yaml`. Kiểm: thư mục chỉ có README không sinh app; thêm `values.yaml` thì `svc-probe` xuất hiện sau 3 s với `valueFiles` đúng; xóa thì app mất sau 2 s.
8. **Link docs trỏ `stable`.** Ghim `release-3.6`, trừ link trang upgrade (cố ý trỏ bản mới nhất).

## Bài học

- "Không khai" khác "rỗng". Apply lên một object đã có sẵn giữ nguyên field mà manifest không nhắc tới, và diff cũng không so field đó, nên project `default` báo `Synced` mà vẫn còn `clusterResourceWhitelist: */*`. Khóa thứ gì thì ghi tường minh `[]` và kiểm trạng thái thật trên cụm, đừng tin trạng thái `Synced`.
- kubectl dò kiểu (discovery) một lần cho cả lệnh, nên một CR không đi chung lệnh với CRD của nó. Cũng vì thế mà "hai lệnh" thật ra cần các lệnh chờ ở giữa. Diễn tập từ cụm trắng mới lộ ra lần so sánh đầu thất bại khiến root kẹt `Unknown` gần 3 phút. Runbook chỉ đúng khi đã chạy lại từ đầu.
- Bảo vệ hệ thống tự quản lý khỏi chính nó: không finalizer ở root và app `argocd`, `Prune=false` cho namespace, CRD, ApplicationSet. Câu hỏi để soát là "commit lỡ tay nào có thể xóa dây chuyền?". Review tìm ra hai chỗ (CRD, ApplicationSet) mà lúc thiết kế chỉ nghĩ tới namespace.
- Câu chuyện kể được: "Argo CD trên lab dựng từ cụm trắng bằng hai lệnh trong 50 s. Lần diễn tập đầu mất 179 s vì root app tạo lúc repo-server chưa sẵn sàng; đọc log controller thấy nó chờ hết `timeout.reconciliation` mới so sánh lại, nên tôi thêm lệnh chờ. Controller chạm 451/512 MiB dù heap thật chỉ 131 MiB, vì Go không biết trần container; đặt `GOMEMLIMIT` 90% limit đưa nó về khoảng 260–350 MiB."
