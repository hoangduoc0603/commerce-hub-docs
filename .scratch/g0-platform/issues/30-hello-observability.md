# 30: `hello` có trace, log, metric và dashboard

Status: ready-for-human
Blocked by: 14, 27
Repos: services/hello, platform, gitops, docs
Spec: [G0](../spec.md)

## Mô tả

`hello` dùng `spring-boot-starter-opentelemetry` và `micrometer-registry-prometheus` (không OTel Java agent), đặt tường minh resource attributes (`service.name`, `service.namespace=commerce-hub`, `service.version`, `deployment.environment.name=lab`), log JSON có `traceId`, histogram và exemplar cho metric HTTP, và một span DB cho mỗi truy vấn. Chart gửi OTLP tới Collector cùng node (IP node qua downward API) và có `ServiceMonitor`. Dashboard dùng chung "Service overview" (RED, JVM, Hikari, chọn service bằng biến) là code trong `gitops`. Theo [observability.md](../../../standards/observability.md). Đây là "service hello có trace và dashboard" của C18, khung của N12.

## Mục tiêu học

- Micrometer Observation, Tracing và cầu nối OTel: một API cho metric lẫn trace.
- Exemplar nối metric với trace.

## Tiêu chí nghiệm thu

- [ ] Một request tạo lời chào ra một trace trên Tempo có span HTTP server và span DB của `service.name=hello`.
- [ ] Thư viện sinh span JDBC với Spring Boot 4.1 đã chọn, ghi vào [observability.md](../../../standards/observability.md) (điểm chưa xác minh).
- [ ] LogQL theo `traceId` ra dòng log của request; từ log mở được trace bằng một click.
- [ ] `/actuator/prometheus` có `http_server_requests_seconds_bucket`; có exemplar khi trace được sample.
- [ ] Dashboard "Service overview" có dữ liệu của `hello`; `count({workspace_id!=""})` trả rỗng.
- [ ] Chạy k6 ngắn với `sampling.probability` 1.0 và 0.0: ghi chênh lệch p99 và CPU. k6 chạy trên Mac; nếu k6 chưa tin root CA của lab thì dùng `--insecure-skip-tls-verify` và ghi lại (kiểm k6 đọc Keychain đã hoãn tới G7, 2026-11-15).
- [ ] Ma trận truy vết, dòng N12: G0 xong phần khung, kèm link dashboard và một trace ID mẫu.

## Ghi chú từ G0-28 (2026-11-26)

- `hello` đã có `spring-boot-starter-opentelemetry`, với `management.tracing.export.otlp.enabled: false` và `management.otlp.metrics.export.enabled: false` ([G0-28](28-hello-problem-details.md)). Ticket này chỉ cần bật export span; giữ tắt `OtlpMeterRegistry`.
- Sampling mặc định của Boot 4.1.2 là `management.tracing.sampling.probability: 0.1` (metadata của jar). Problem Details luôn trả `traceId`, nên nếu không đặt `1.0` (head sampling 100% theo [observability.md](../../../standards/observability.md)) thì khoảng 90% `traceId` dẫn tới trace không có trên Tempo.
- Bật export bằng property hoặc bằng biến `OTEL_*`, chọn một cách. Biến `OTEL_TRACES_EXPORTER` đè cả yaml lẫn `-D` (đã tái hiện ở G0-28). Kiểm env của pod bằng `kubectl -n hello exec deploy/hello -- env | grep OTEL`.


## Chuyển từ G0-13

- Prometheus chọn **mọi** ServiceMonitor, PodMonitor, PrometheusRule ở mọi namespace (`*SelectorNilUsesHelmValues: false`), không cần nhãn `release`. Chart `app` chỉ cần sinh `ServiceMonitor` trỏ cổng quản trị (`/actuator/prometheus`) trong namespace `hello`; project `commerce` của Argo CD hiện không cấm Kind `ServiceMonitor` (kiểm lại blacklist khi thêm). Lưu ý quyền: ServiceMonitor của một service có thể khai `namespaceSelector` trỏ namespace khác và Prometheus sẽ scrape theo. Chặn bằng `prometheusSpec.ignoreNamespaceSelectors: true` thì vỡ các monitor của chart (kubelet, CoreDNS ở `kube-system`, apiserver ở `default` đều nằm ở `observability`), nên nếu cần thì chặn ở Argo CD (blacklist hoặc policy), quyết khi làm.
- Dashboard "Service overview" là ConfigMap nhãn `grafana_dashboard: "1"` đặt ở `gitops/infra/kube-prometheus-stack/dashboards/` (sidecar chỉ tìm trong `observability`), `configMapGenerator` có `disableNameSuffixHash: true` (lý do ở `infra/kube-prometheus-stack/kustomization.yaml`). Dashboard mẫu: `cardinality.json`.
- Ngân sách: tổng 96 293 series lúc G0-13 (48% của 200 000). Alert "5 000 series mỗi pod service" chưa có: thêm vào `prometheusrule-series-budget.yaml` khi có ServiceMonitor đầu tiên của service, với nhãn tách được pod service khỏi pod hạ tầng (ví dụ `namespace="hello"` hoặc nhãn `service`). Kiểm lại panel "Series mang nhãn bị cấm" của dashboard `Cardinality` vẫn 0 sau khi `hello` có metric.
- Grafana không có route cho Prometheus; smoke test đọc Prometheus qua `https://grafana.lab.internal/api/datasources/proxy/uid/prometheus/...`.

## Chuyển từ G0-14

- Endpoint OTLP cho `hello`: `http://otel-collector.observability.svc:4318/v1/traces` (HTTP) hoặc `:4317` (gRPC). Service có `internalTrafficPolicy: Local`: request luôn vào Collector cùng node; trong lúc Collector của node đó rollout, request rơi và SDK thử lại. Nhớ bật lại export OTLP của `hello` (đang tắt từ G0-28).
- Trace được gắn `k8s.pod.name`, `k8s.namespace.name`, `k8s.node.name`, `k8s.deployment.name` ở Collector (tra pod theo IP nguồn); app không cần downward API. Processor không đè `service.name` app tự đặt, nhưng tự suy `service.namespace` (namespace), `service.version` (tag image, hoặc digest khi ghim digest), `service.instance.id`.
- Log: Collector đọc stdout mọi pod, dòng JSON được parse và khóa `traceId`, `spanId` (khóa MDC của Micrometer Tracing) thành trường trace của log record; Loki lưu `trace_id`, `span_id` là structured metadata. **Cần kiểm ở ticket này**: JSON ECS thật của Spring Boot 4.1 (`logging.structured.format.console: ecs`) đặt trace ID ở khóa `traceId` phẳng hay `trace.id`; nếu khác, sửa `parse_from` của operator `json-parser` trong `gitops/apps/lab/otel-collector.yaml`.
- Nhãn index Loki chỉ `service_name`, `service_namespace`, `k8s_namespace_name`. Truy vấn mẫu: `{k8s_namespace_name="hello"} | trace_id="<id>"`. `service_name` của log do Collector suy từ pod (nhãn `app.kubernetes.io/name` hoặc tên Deployment/container), có thể khác `service.name` của trace (`spring.application.name`): đặt hai cái trùng nhau.
- Grafana: datasource uid `tempo`, `loki`, `prometheus`; từ log mở trace (derived field `trace_id`), từ span mở log (lọc theo namespace + `trace_id`), từ exemplar (nhãn `trace_id`) mở trace. Dashboard của `hello` dùng các uid này.
- Bẫy API Tempo khi viết test e2e: `/api/search` không truyền `start`/`end` chỉ xem dữ liệu rất mới; search ngay sau khi gửi có thể thiếu, chờ khoảng 30 s.
