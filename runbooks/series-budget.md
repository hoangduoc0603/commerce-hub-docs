# Runbook: Prometheus vượt ngân sách series

Alert `PrometheusSeriesBudgetExceeded` bắn khi `prometheus_tsdb_head_series` vượt 200 000 trong 30 phút.

Alert `ServiceSeriesBudgetExceeded` (G0-30) bắn khi một pod service (target `container="app"`, `endpoint="management"`, tức ServiceMonitor của chart `app`) trả quá 5 000 sample mỗi lần scrape trong 30 phút. Chẩn đoán như dưới nhưng lọc theo namespace của pod trong alert: `topk(10, count by (__name__) ({namespace="<ns>", container="app"}))`.

- Ticket: [G0-13](../.scratch/g0-platform/issues/13-prometheus-grafana.md) bước 4. Chuẩn: [observability.md, mục "Metric: tên, nhãn, cardinality"](../standards/observability.md). Rule: `gitops/infra/kube-prometheus-stack/prometheusrule-series-budget.yaml`.
- Phiên bản: Prometheus v3.16.0 (chart `kube-prometheus-stack` 94.1.0), limit 1 Gi.
- Docs gốc: [Prometheus – Naming: labels](https://prometheus.io/docs/practices/naming/#labels), [Prometheus – TSDB status API](https://prometheus.io/docs/prometheus/latest/querying/api/#tsdb-stats).

## Vì sao quan trọng

Mỗi tổ hợp giá trị nhãn là một series. RAM của Prometheus tăng gần tuyến tính theo số series trong head (2 giờ gần nhất). Với limit 1 Gi, vượt ngân sách nhiều thì Prometheus bị OOMKill, mất giám sát cả cụm và mất dữ liệu chưa flush khỏi WAL. Nguyên nhân thường gặp: một nhãn không giới hạn giá trị (`workspace_id`, `order_id`, `trace_id`, URL thô) lọt vào metric, hoặc một exporter mới.

**Không tăng RAM trước khi tìm ra nguyên nhân** (observability.md).

## Chẩn đoán

Mở Prometheus (không có route trên `edge`):

```bash
kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus 9090
```

1. Job hay namespace nào tăng (recording rule của ticket 13, có lịch sử 15 ngày):

   ```promql
   sort_desc(job:scrape_samples_post_metric_relabeling:sum)
   sort_desc(namespace:scrape_samples_post_metric_relabeling:sum)
   ```

   So với mốc trong [bản ghi thí nghiệm G0](../experiments/2026-11-g0.md) bằng `offset 1d` hoặc biểu đồ 7 ngày.

2. Metric nào nhiều series nhất:

   ```promql
   topk(10, count by (__name__) ({__name__=~".+"}))
   ```

   Hoặc trang **Status → TSDB Status** (`http://localhost:9090/tsdb-status`): "Top 10 label names with high memory usage", "Highest cardinality labels", "Highest cardinality metric names".

3. Nhãn nào nổ trong metric đó (thay `<metric>`):

   ```promql
   count by (<nhãn nghi ngờ>) (<metric>)
   ```

   Kiểm riêng các nhãn bị cấm: `count({workspace_id!=""})`, `count({order_id!=""})`, `count({trace_id!=""})` phải rỗng.

## Xử lý

| Nguyên nhân | Cách sửa |
|---|---|
| Code service gắn nhãn không giới hạn | Sửa code: giá trị đó đi vào trace (`highCardinalityKeyValue`), không vào metric. Deploy lại; series cũ hết khỏi head sau 1–3 giờ |
| Histogram có quá nhiều bucket | Giới hạn bucket (`management.metrics.distribution.slo` hoặc `maximum-expected-value`) |
| Exporter hay hạ tầng mới (operator, Kafka…) | Bỏ metric không dùng bằng `metricRelabelings` `action: drop` trong ServiceMonitor của nó |
| Tăng thật, đúng thiết kế | Ghi số đo vào `docs/experiments/`, cập nhật ngân sách trong observability.md và ticket kiến trúc 04, rồi mới nâng limit |

Không cần khởi động lại Prometheus: sửa nguồn là đủ.

## Mốc

- 2026-11-27 (G0-13 bước 2–3, chưa có Alertmanager, Grafana, Keycloak): khoảng 78 000 series, apiserver chiếm khoảng 55 000. Số chốt ghi ở bước 8 của G0-13.
- 2026-11-28 (G0-30): `hello` 396 sample mỗi lần scrape (454 trước khi tắt bucket `http_server_requests_active`), tổng head 99 488 series.
