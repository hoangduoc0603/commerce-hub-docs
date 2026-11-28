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
- [ ] Limit memory đúng bảng ngân sách; không pod nào OOMKilled lúc kiểm (theo dõi dài ngày sang G7, cùng bản đo 24 giờ của ticket 34).

## Chuyển từ G0-13

- Grafana 13.3.2 nằm trong app `kube-prometheus-stack` (`gitops/apps/lab/kube-prometheus-stack.yaml`). Datasource Loki, Tempo thêm bằng `grafana.additionalDataSources` trong values đó (chart sinh ConfigMap, sidecar datasources nạp); giữ uid cố định (`loki`, `tempo`) để link trace ↔ log và exemplar trỏ được. Datasource Prometheus có uid `prometheus`.
- Prometheus đã bật `exemplar-storage`; liên kết metric → trace cần `exemplarTraceIdDestinations` trên datasource Prometheus (`grafana.sidecar.datasources.exemplarTraceIdDestinations` của kube-prometheus-stack) trỏ uid `tempo`.
- Sidecar Grafana chỉ đọc ConfigMap trong `observability` (Role, không ClusterRole; mặc định chart đọc mọi Secret của cụm). Datasource cần secret (nếu có) phải đi qua values, không qua Secret có nhãn.
- RAM: Grafana và hai sidecar đã dùng 640 Mi so với ngân sách 320 Mi của ticket kiến trúc 04; tổng `observability` limit 2 256 Mi trước khi có Loki, Tempo, Collector ([bản ghi G0 mục 10](../../../experiments/2026-11-g0.md)). Đo kỹ trước khi đặt limit cho Loki, Tempo: hai lần OOM ở G0-13 đều xảy ra trong 2 giây đầu, mẫu 30 s của cAdvisor không bắt được.
- Namespace `observability` đã có (PSA `privileged`, nhãn route); Collector DaemonSet đặt cùng namespace.
