# 13: Prometheus và Grafana dạng code

Status: ready-for-human
Blocked by: 06
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

kube-prometheus-stack chạy Prometheus 1 bản (retention 15 ngày, `ServerSideApply`), Alertmanager, kube-state-metrics, node-exporter; Grafana mở qua `https://grafana.lab.internal`, đăng nhập bằng tài khoản admin cục bộ (mật khẩu là `SealedSecret`). Datasource và dashboard là code trong `gitops`. Mọi thành phần trong namespace `observability`, limit theo bảng ticket 04 của map. Theo [observability.md](../../../standards/observability.md).

## Mục tiêu học

- Prometheus Operator: `ServiceMonitor`, recording rule, và ngân sách cardinality.

## Thu hẹp 2026-11-15

Theo quyết định D4 (spec G0 mục "Sửa phạm vi 2026-11-15"). Quan sát vẫn giữ đủ như thiết kế; chỉ phần đăng nhập đổi.

- Giữ: Prometheus, Alertmanager, kube-state-metrics, node-exporter, Grafana với datasource và dashboard dạng code, không route cho Prometheus và Alertmanager.
- Đổi: Grafana dùng tài khoản admin cục bộ, mật khẩu là `SealedSecret`. Bỏ phụ thuộc ticket 11.
- Hoãn tới G7: SSO Grafana qua client `grafana` của realm, map group admin của realm sang quyền Admin của Grafana.

Tiêu chí hoãn tới G7:

- Đăng nhập Grafana bằng Keycloak; group admin của realm thành Admin của Grafana.

## Tiêu chí nghiệm thu

- [ ] Đăng nhập Grafana bằng admin cục bộ; mật khẩu lấy từ `SealedSecret`, không nằm dạng rõ trong `gitops`.
- [ ] Dashboard mặc định của cụm có dữ liệu cho cả 3 node.
- [ ] Sửa một dashboard trên UI rồi sync lại thì bị ghi đè bằng bản trong Git.
- [ ] `prometheus_tsdb_head_series` ghi vào bản ghi thí nghiệm G0 làm mốc.
- [ ] Prometheus và Alertmanager không có route trên `edge` (chỉ `port-forward`).
