# 21: Chart `app` lõi, lint và publish OCI lên GHCR

Status: resolved
Blocked by: 17
Repos: platform, docs
Spec: [G0](../spec.md)

## Mô tả

Chart `app` dùng chung cho mọi workload, bản lõi: Deployment mặc định 2 replica, Service, probe theo nhóm health của Actuator, preStop, resources, Pod Security "restricted" (securityContext), ServiceAccount, ConfigMap, `jvm.enabled` với `JAVA_TOOL_OPTIONS` (`MaxRAMPercentage` chỉnh được), `secretRevision`. Reusable workflow `chart`: `helm lint --strict`, `kubeconform`, publish OCI lên GHCR bằng `GITHUB_TOKEN`. Theo [helm-chart.md](../../../standards/helm-chart.md), [zero-downtime.md](../../../standards/zero-downtime.md), [ADR-0017](../../../adr/0017-images-and-charts-on-ghcr.md).

## Mục tiêu học

- Thiết kế một chart dùng chung: mặc định an toàn, biến thể kiểm trong CI.

## Thu hẹp 2026-11-15

Theo quyết định D6, D7 (spec G0 mục "Sửa phạm vi 2026-11-15").

- Giữ: Deployment, Service, probe theo Actuator, resources, securityContext "restricted", `jvm.*`, `secretRevision`, `helm lint` và `kubeconform`. Truststore và `httpRoute` ở ticket 22; Job migrate `PreSync` và SealedSecret ở ticket 27.
- Đổi: publish OCI lên GHCR thay cho `10.20.0.5:5000/charts` qua tailnet.
- Hoãn tới G7: `ct install` trên kind, JSON schema cho values (digest image bắt buộc), PDB, `topologySpreadConstraints`.

Tiêu chí hoãn tới G7:

- `helm template` thiếu digest image thì thất bại với lỗi schema.
- `ct install` pass mọi biến thể trên kind trong CI.

## Tiêu chí nghiệm thu

- [x] `helm lint --strict` 0 lỗi, 0 cảnh báo với mọi file `ci/`; `kubeconform -strict` với 1.37.0: `Invalid: 0, Errors: 0`.
- [x] Label `pod-security.kubernetes.io/enforce=restricted` dry-run không có `Warning:`.
- [x] `helm show chart oci://ghcr.io/<owner>/charts/app --version <v>` trả đúng `Chart.yaml` (không cần `--plain-http`).
- [x] Đổi một key ConfigMap thì pod rollout (checksum).
- [x] Thiếu `image.digest`, `image.repository` hoặc `resources` thì `helm template` thất bại với thông điệp của `required` (thay schema tới G7).

## Quyết định khi lập lộ trình (2026-11-18)

Chốt với chủ repo trước bước 1.

- **Q1. ConfigMap vào pod bằng biến môi trường.** Values có map `env`, chart render thành ConfigMap, pod nạp bằng `envFrom.configMapRef`. Spring Boot map env sang property bằng relaxed binding; app Node đọc được như nhau. Loại: mount `application.yaml` vào `/config/` (giữ YAML lồng nhau nhưng app Node không dùng được, thêm một volume).
- **Q2. Publish khi push `main` có đổi `charts/**`.** Version lấy từ `Chart.yaml`; version đã có trên GHCR thì CI fail, buộc tăng version trong PR. Loại: tag riêng `chart-app-vX.Y.Z` (thêm một chỗ phải khớp với `Chart.yaml`, dễ lẫn với tag `v*` của reusable workflow).
- **Q3. Workflow thường `.github/workflows/chart.yml`**, chạy theo `paths: charts/**`. Lệch chữ "reusable workflow `chart`" ở mục Mô tả: chỉ có một chart và chỉ `platform` gọi. Tách thành reusable khi có repo thứ hai cần.
- **Q4. Chỉ annotation `secretRevision` ở ticket này.** `existingSecret` (`envFrom.secretRef`) làm ở ticket 27 cùng SealedSecret đầu tiên, khi có Secret thật để kiểm.

## Lộ trình

- [x] 1. Cài `kubeconform`, nâng Helm lên 4.3.2. Khung chart: `Chart.yaml`, `.helmignore`, `values.yaml` rỗng có comment, `_helpers.tpl` (tên, 7 nhãn chung, selector), `serviceaccount.yaml`. Kiểm: `helm lint --strict charts/app` 0 lỗi 0 cảnh báo; `helm template` ra ServiceAccount đủ nhãn, `automountServiceAccountToken: false`.
- [x] 2. `deployment.yaml`, `service.yaml` tối thiểu: image `repo@digest`, `required` cho `image.repository`, `image.digest`, `resources`; `limits.memory = requests.memory`, không CPU limit; `ci/default-values.yaml`. Kiểm: thiếu từng key ra thông điệp `required`; đủ thì `kubeconform -strict -kubernetes-version 1.37.0` `Invalid: 0, Errors: 0`.
- [x] 3. securityContext restricted, `readOnlyRootFilesystem`, `emptyDir` `/tmp`. Kiểm: `kubectl apply --dry-run=server` vào namespace thử có nhãn `enforce=restricted` không có `Warning:`; bỏ `runAsNonRoot` thì có `Warning: would violate PodSecurity`. (Sửa 2026-11-19, đo trên cụm: `enforce` chỉ từ chối Pod; Deployment vi phạm vẫn được nhận, chỉ kèm cảnh báo, rồi ReplicaSet không tạo được pod. Pod dry-run thì `Forbidden`.)
- [x] 4. Probe theo Actuator, rolling update, `minReadySeconds`, `preStop.sleep`, `terminationGracePeriodSeconds` theo `zero-downtime.md`. Kiểm: `kubeconform` xanh, đối chiếu từng giá trị.
- [x] 5. `jvm.*` ghép `JAVA_TOOL_OPTIONS`; `ci/jvm-off-values.yaml`. Kiểm: biến thể lab ra `-XX:MaxRAMPercentage=60`; `jvm-off` không có `JAVA_TOOL_OPTIONS`.
- [x] 6. `configmap.yaml` + `checksum/config`, annotation `secretRevision`, `ci/lab-values.yaml`. Kiểm: render hai lần giống từng byte; đổi một key thì checksum đổi.
- [x] 7. Cài thật vào namespace thử với image `hello` theo digest, 1 replica; dry-run nhãn PSS; `helm upgrade` đổi config; dọn. Kiểm: pod `Ready`, không `Warning:`, `rollout history` tăng revision.
- [x] 8. Workflow `chart.yml`: PR lint + `kubeconform` mọi `ci/*`; push `main` kiểm version chưa có, package, push GHCR. Kiểm: PR xanh; `helm show chart oci://ghcr.io/hoangduoc0603/charts/app --version 0.1.0` đúng; `helm pull` không đăng nhập được.
- [x] 9. Kết ticket: bằng chứng, cập nhật `helm-chart.md` (kubeconform 1.37 đã xác minh, Helm 4.3.2, package chart public), README `platform`, ma trận truy vết, `## Bài học`.

## Bằng chứng

Gom dần theo bước, chốt ở bước 9. Helm 4.3.2, kubeconform 0.8.0, cụm `homelab` v1.37.2.

- **Lint, schema API** (bước 6, 2026-11-20): `helm lint --strict` với `ci/default`, `ci/jvm-off`, `ci/lab`: `0 chart(s) failed` (chỉ `[INFO] icon is recommended`). `kubeconform -strict -kubernetes-version 1.37.0`: `Valid: 3`, `3`, `4`; `Invalid: 0, Errors: 0`. Kho schema mặc định của kubeconform có bản 1.37.0 (xác minh 2026-11-17).
- **`required`** (bước 2): thiếu `image.repository`, `image.digest`, `resources.requests.cpu`, `resources.requests.memory` thì `helm template` lỗi `… là bắt buộc …`. `helm lint` bỏ qua `required` (lint mode), nên CI phải chạy `helm template`.
- **PSS** (bước 3, 7): server dry-run Deployment vào namespace `enforce=restricted` không có `Warning:`; bỏ `runAsNonRoot` thì `Warning: would violate PodSecurity "restricted:v1.37"`. Sau khi cài thật, `kubectl label --dry-run=server --overwrite ns chart-test pod-security.kubernetes.io/enforce-version=latest` không có `Warning:`. Ghi chú: dry-run đặt lại đúng giá trị nhãn đang có (`enforce=restricted`) trả `not labeled` và **không** đánh giá lại pod, nên phải đổi một giá trị (version) thì kiểm mới có nghĩa.
- **Cài thật** (bước 7, 2026-11-20): image `ghcr.io/hoangduoc0603/commerce-hub-hello@sha256:5f13c9cc…e1c739` (commit `16efc28`), 1 replica, 512Mi, `ci/lab-values.yaml`. Pod `1/1 Running`, nhãn `version` đúng SHA. Log: `Picked up JAVA_TOOL_OPTIONS: -XX:MaxRAMPercentage=60 -XX:ActiveProcessorCount=2`, profile `lab` (từ ConfigMap qua `envFrom`), `Started HelloApplication in 0.726 seconds`. Pod tạo tới `Ready`: 5 s. `kubectl top`: 2m CPU, **129Mi** working set lúc rảnh (heap tối đa 60% × 512Mi ≈ 307Mi); chưa phải số đo dưới tải.
- **Rollout theo config** (bước 7): `helm upgrade --set env.LOGGING_LEVEL_ROOT=DEBUG` thì Deployment lên revision 2 (pod mới trước, pod cũ tắt sau). Upgrade lại cùng values: Helm revision 3, Deployment vẫn 2 (checksum ổn định). `secretRevision=2`: Deployment lên 3. Dọn: `helm uninstall`, xóa namespace `chart-test`.
- **Publish** (bước 8, 2026-11-20): [platform#4](https://github.com/hoangduoc0603/commerce-hub-platform/pull/4) (rebase vào `main`, `93c99f7`, `5c843cc`). PR: job `lint` xanh (3 biến thể, test âm `required`), `publish` bị bỏ qua. `main`: `publish` đẩy `oci://ghcr.io/hoangduoc0603/charts/app:0.1.0`, digest `sha256:b312a941499d4114e76c0880d6d7220a4dc43b91653c54eb33c9a7a332c7b981`. Không đăng nhập: `helm show chart … --version 0.1.0` in đúng `Chart.yaml`, `helm pull` ra 11 file (gồm `ci/`). Trang package nằm dưới repo `commerce-hub-platform`. Chạy lại `publish` thì fail: `app:0.1.0 đã có trên GHCR. Tăng version trong Chart.yaml.` Lần publish đầu, GHCR (đã đăng nhập) trả `not found` cho package chưa tồn tại; gọi ẩn danh thì trả 403 `denied`.
- **Review** (`code-review` mức medium trên platform#4): 7 phát hiện. Sửa ở [platform#5](https://github.com/hoangduoc0603/commerce-hub-platform/pull/5), chart 0.1.1: pod đặt `automountServiceAccountToken` (trước đó `serviceAccount.create=false` thì pod dùng SA `default` và có token); push `main` chỉ chạy khi `charts/**` đổi (commit chỉ sửa workflow sẽ làm `publish` đỏ vì version không tăng); bước kiểm version chỉ nhận `not found`. Không sửa, ghi vào lệch chuẩn của `helm-chart.md`: cổng 8081 mở trong cụm tới khi có NetworkPolicy (G7); `jvm.activeProcessorCount` không nguyên và tên cổng dài quá 15 ký tự chờ schema (G7); hai job cài Helm lặp script (chấp nhận, một file). platform#5 rebase vào `main` (`08824da`); `publish` đẩy `app:0.1.1`, digest `sha256:872baac2eccc34d36554018f3e4205ee8fb87f5fa6a00c18444f8559dd8a1331`; render không đăng nhập từ GHCR với `serviceAccount.create=false` ra `automountServiceAccountToken: false` ở pod. Dùng 0.1.1 từ ticket 22 trở đi.

## Bài học

- `helm lint` không phải lưới an toàn cho value bắt buộc: lint mode bỏ qua `required`, kubeconform không kiểm tham chiếu chéo (probe trỏ cổng `http` không tồn tại vẫn `Valid`), API server cũng nhận. Mỗi lớp kiểm có điểm mù riêng, nên chart tự chặn bằng `required`/`fail` và CI có test âm.
- Chỗ vấp: tưởng `enforce=restricted` từ chối Deployment vi phạm. Thực tế chỉ Pod bị từ chối, Deployment được nhận kèm cảnh báo rồi pod không bao giờ lên. Và dry-run đặt lại đúng giá trị nhãn đang có không đánh giá lại pod. Cả hai chỉ thấy khi chạy trên cụm thật, không đọc docs mà ra.
- YAML đổi kiểu ngầm (`1000000` thành `1e+06`, `on` thành `true`, `010` thành `8`) nên ConfigMap từ values phải từ chối giá trị không phải chuỗi, không cố đổi lại.
- Câu chuyện kể được: "Một Helm chart dùng chung cho mọi service, mặc định an toàn: Pod Security restricted, root chỉ đọc, image theo digest, memory limit bằng request, rollout `maxUnavailable 0` có `preStop`. Đổi config thì pod tự rollout nhờ checksum, render ổn định nên Argo CD không lệch; đo trên cụm: upgrade lại cùng values không tạo revision mới. CI lint và kiểm schema K8s 1.37 mọi biến thể, publish OCI lên GHCR, chặn ghi đè version."
