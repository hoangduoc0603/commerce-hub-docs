# 13: Prometheus và Grafana dạng code

Status: ready-for-human
Blocked by: 06, 11
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

kube-prometheus-stack chạy Prometheus 1 bản (retention 15 ngày, `ServerSideApply`), Alertmanager, kube-state-metrics, node-exporter; Grafana mở qua `https://grafana.lab.internal` với SSO client `grafana`. Datasource và dashboard là code trong `gitops`. Mọi thành phần trong namespace `observability`, limit theo bảng ticket 04 của map. Theo [observability.md](../../../standards/observability.md).

## Mục tiêu học

- Prometheus Operator: `ServiceMonitor`, recording rule, và ngân sách cardinality.

## Tiêu chí nghiệm thu

- [ ] Đăng nhập Grafana bằng Keycloak; group admin của realm thành Admin của Grafana.
- [ ] Dashboard mặc định của cụm có dữ liệu cho cả 3 node.
- [ ] Sửa một dashboard trên UI rồi sync lại thì bị ghi đè bằng bản trong Git.
- [ ] `prometheus_tsdb_head_series` ghi vào bản ghi thí nghiệm G0 làm mốc.
- [ ] Prometheus và Alertmanager không có route trên `edge` (chỉ `port-forward`).
