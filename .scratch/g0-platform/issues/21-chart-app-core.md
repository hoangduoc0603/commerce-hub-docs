# 21: Chart `app` lõi, kiểm bằng `ct install` trên kind, publish OCI

Status: ready-for-human
Blocked by: 17
Repos: platform, docs
Spec: [G0](../spec.md)

## Mô tả

Chart `app` dùng chung cho mọi workload, bản lõi: Deployment mặc định 2 replica, Service, probe theo nhóm health của Actuator, preStop, PDB, `topologySpreadConstraints`, Pod Security "restricted", ServiceAccount, ConfigMap, `jvm.enabled` với `JAVA_TOOL_OPTIONS` (`MaxRAMPercentage` chỉnh được), `secretRevision`, JSON schema cho values (digest image bắt buộc). Reusable workflow `chart`: `helm lint --strict`, `kubeconform`, `ct install` trên kind trần, publish OCI lên `10.20.0.5:5000/charts` qua tailnet. Theo [helm-chart.md](../../../standards/helm-chart.md), [zero-downtime.md](../../../standards/zero-downtime.md).

## Mục tiêu học

- Thiết kế một chart dùng chung: values có schema, mặc định an toàn, biến thể kiểm trong CI.

## Tiêu chí nghiệm thu

- [ ] `helm lint --strict` 0 lỗi, 0 cảnh báo với mọi file `ci/`; `kubeconform -strict` với 1.37.0: `Invalid: 0, Errors: 0`.
- [ ] `helm template` thiếu digest image thì thất bại với lỗi schema.
- [ ] Label `pod-security.kubernetes.io/enforce=restricted` dry-run không có `Warning:`.
- [ ] `ct install` pass mọi biến thể trên kind trong CI.
- [ ] `helm show chart oci://10.20.0.5:5000/charts/app --version <v> --plain-http` trả đúng `Chart.yaml`.
- [ ] Đổi một key ConfigMap thì pod rollout (checksum).
