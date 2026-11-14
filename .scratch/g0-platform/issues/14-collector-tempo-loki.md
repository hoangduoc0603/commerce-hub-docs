# 14: Collector, Tempo và Loki: trace nối log

Status: ready-for-human
Blocked by: 13
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

OTel Collector contrib chạy DaemonSet (preset `kubernetesAttributes`, `logsCollection`), nhận OTLP và đọc log pod, đẩy trace tới Tempo monolithic (retention 7 ngày) và log tới Loki Monolithic (chart `grafana-community/loki`, tắt chunks-cache và results-cache, retention 14 ngày). Grafana có datasource Tempo, Loki với liên kết log → trace. Chưa có service nào; kiểm bằng `telemetrygen`. Theo [observability.md](../../../standards/observability.md).

## Mục tiêu học

- Pipeline của Collector: receiver → processor → exporter, và vì sao chạy DaemonSet.

## Tiêu chí nghiệm thu

- [ ] `telemetrygen traces` từ một pod gửi tới Collector cùng node; trace hiện trên Tempo qua Grafana Explore, có thuộc tính `k8s.*`.
- [ ] Log của một pod thử thấy trên Loki; dòng log có trace ID mở được trace bằng một click.
- [ ] Chart monolithic của Tempo đã chọn và ghi nguồn vào [observability.md](../../../standards/observability.md) (điểm chưa xác minh).
- [ ] Log không bị thu trùng.
- [ ] Limit memory đúng bảng ngân sách; không pod nào OOMKilled sau một ngày.
