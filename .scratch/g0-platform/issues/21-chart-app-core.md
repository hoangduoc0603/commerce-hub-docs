# 21: Chart `app` lõi, lint và publish OCI lên GHCR

Status: ready-for-human
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

- [ ] `helm lint --strict` 0 lỗi, 0 cảnh báo với mọi file `ci/`; `kubeconform -strict` với 1.37.0: `Invalid: 0, Errors: 0`.
- [ ] Label `pod-security.kubernetes.io/enforce=restricted` dry-run không có `Warning:`.
- [ ] `helm show chart oci://ghcr.io/<owner>/charts/app --version <v>` trả đúng `Chart.yaml` (không cần `--plain-http`).
- [ ] Đổi một key ConfigMap thì pod rollout (checksum).
- [ ] Thiếu `image.digest`, `image.repository` hoặc `resources` thì `helm template` thất bại với thông điệp của `required` (thay schema tới G7).
