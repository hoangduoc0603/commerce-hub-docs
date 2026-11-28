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

- [x] Một request tạo lời chào ra một trace trên Tempo có span HTTP server và span DB của `service.name=hello`.
- [x] Thư viện sinh span JDBC với Spring Boot 4.1 đã chọn, ghi vào [observability.md](../../../standards/observability.md) (điểm chưa xác minh).
- [x] LogQL theo `traceId` ra dòng log của request; từ log mở được trace bằng một click.
- [x] `/actuator/prometheus` có `http_server_requests_seconds_bucket`; có exemplar khi trace được sample.
- [x] Dashboard "Service overview" có dữ liệu của `hello`; `count({workspace_id!=""})` trả rỗng.
- [x] Chạy k6 ngắn với `sampling.probability` 1.0 và 0.0: ghi chênh lệch p99 và CPU. k6 chạy trên Mac; nếu k6 chưa tin root CA của lab thì dùng `--insecure-skip-tls-verify` và ghi lại (kiểm k6 đọc Keychain đã hoãn tới G7, 2026-11-15).
- [x] Ma trận truy vết, dòng N12: G0 xong phần khung, kèm link dashboard và một trace ID mẫu.

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

## Lộ trình

Duyệt 2026-11-28. Quyết định khi lập lộ trình:

- App tìm Collector qua Service `otel-collector.observability.svc:4318` (`internalTrafficPolicy: Local`, G0-14 Q2), không dùng downward API lấy IP node như mô tả ticket.
- Khóa trace trong log ECS của Boot 4.1.2: `traceId` phẳng ở gốc JSON (formatter ghép MDC bằng `contextPairs.nested`, chỉ khóa có dấu chấm mới lồng). `parse_from: attributes.json.traceId` của Collector giữ nguyên; bước 5 kiểm bằng dòng log thật.
- `namespaceSelector` chéo namespace của ServiceMonitor: không chặn ở G0, ghi rủi ro, xử lý ở G7.
- Ứng viên span JDBC: `net.ttddyy.observation:datasource-micrometer-spring-boot` 2.3.1 (POM build trên Boot 4.1.2) hoặc `io.opentelemetry.instrumentation:opentelemetry-jdbc`; chọn ở bước 4.
- `service.version`: đề xuất lấy từ nhãn pod `app.kubernetes.io/version` (git SHA) qua downward API; chốt ở bước 6.

- [x] 1. `micrometer-registry-prometheus`, expose `prometheus` trên cổng 8081, `percentiles-histogram` cho `http.server.requests`. Kiểm: `./gradlew test`, test thấy `http_server_requests_seconds_bucket` ở `:8081/actuator/prometheus`.
- [x] 2. `sampling.probability: 1.0`; exemplar khi scrape bằng OpenMetrics. Kiểm: test thấy `# {trace_id="<id gửi vào>"}` trên dòng bucket.
- [x] 3. Bật export span, `resource-attributes`; seam `InMemorySpanExporter`. Kiểm: test thấy span server có `service.name=hello`, `service.namespace=commerce-hub`.
- [x] 4. Chọn thư viện span JDBC, ghi vào `observability.md`. Kiểm: test thấy span JDBC cùng trace, con của span HTTP.
- [x] 5. `logging.structured.format.console: ecs`. Kiểm: test bắt output thấy JSON có `traceId` ở gốc; `bootTestRun` nhìn tận mắt.
- [x] 6. Chart `app` 0.4.0: `serviceMonitor.enabled`, env `service.version`, schema kubeconform. Kiểm: CI `platform` xanh, chart trên GHCR.
- [x] 7. Merge `hello`, values lab (chart 0.4.0, endpoint Collector, `deployment.environment.name`, ServiceMonitor). Kiểm: target `hello` `up`, bucket có exemplar qua Grafana proxy.
- [x] 8. Request có token `smoke-test` → trace trên Tempo, LogQL theo `trace_id`, click log → trace. Kiểm: tiêu chí 1 và 3.
- [x] 9. Alert 5 000 series mỗi pod service; panel "Series mang nhãn bị cấm" vẫn 0. Kiểm: `count({workspace_id!=""})` rỗng, rule có trong `/rules`.
- [x] 10. Dashboard "Service overview" (RED, JVM, Hikari, biến `service`). Kiểm: chọn `hello` có dữ liệu, exemplar mở Tempo.
- [x] 11. k6 với sampling 1.0 và 0.0, ghi p99 và CPU vào `docs/experiments/`. Kiểm: bảng số đo kèm kết luận.

## Ghi chú thực hiện (2026-11-28)

Bước 1–5 chủ repo giao Claude làm hộ từ bước 2; bước 6–11 Claude làm theo yêu cầu "làm hết các bước tiếp theo".

- **Commit:** `hello` 28977e6 (bước 1–5), b4b15f0 (tên pool Hikari), 667d7b4 (log `Greeting created`), a8b8459 (tắt bucket `http.server.requests.active`); `platform` 9d033bf (chart `app` 0.4.0); `gitops` 5332940 (chart 0.4.0, values lab), 8b22330 (alert), cefccd5 (dashboard).
- **Lệch lộ trình, bước 6:** `service.version` không lấy từ nhãn pod qua downward API mà từ `image.tag` ngay trong chart (cùng giá trị, nhãn `app.kubernetes.io/version` cũng render từ `image.tag`), qua biến chuẩn `OTEL_RESOURCE_ATTRIBUTES`; `deployment.environment.name` qua value mới `otel.resourceAttributes`. Lý do ở `observability.md` dòng resource attributes.
- **Sự cố bước 7:** Job migrate của image 28977e6 lỗi `FATAL: too many connections for role "hello_migrator"` 3/3 lần, sync dừng, Deployment giữ bản cũ (đúng thiết kế PreSync). Gốc: `DefaultDataSourceNameResolver` của datasource-micrometer mở pool `HikariPool-1` lúc khởi động để đọc catalog, Hikari lấp `minimumIdle` trong nền và chiếm 2 kết nối của role. Sửa bằng `spring.datasource.hikari.pool-name: hello`; `MigrateProfileTests` tái hiện được lỗi (đỏ) rồi xanh nhờ kiểm pool chưa chạy.
- **Bước 8:** request bình thường không ghi log nào, nên thêm một dòng INFO `Greeting created id=…` (không ghi name, N11); `TracingExportTests` kiểm dòng log mang đúng `traceId` của span server. Trace mẫu `51e7a2fee892be06eb5e3388419355c5`: 8 span, có `http post /v1/greetings` và `INSERT greeting SELECT` (`db.system.name=postgresql`), resource `service.namespace=commerce-hub`, `service.version=667d7b4…`, `deployment.environment.name=lab`. LogQL `{k8s_namespace_name="hello"} | trace_id="51e7a2fe…"` ra dòng `Greeting created`; trong Grafana bấm link "Mở trace" của dòng log mở đúng trace trên Tempo.
- **Bước 7, exemplar:** `/api/v1/query_exemplars` trên Prometheus trả exemplar `trace_id=51e7a2fe…` ở bucket `le=0.626…` của `/v1/greetings`.
- **Bước 9:** rule `ServiceSeriesBudgetExceeded` có trong `/api/v1/rules`, health `ok`; `count({workspace_id!=""})`, `count({order_id!=""})`, `count({trace_id!=""})` rỗng.
- **Bước 10:** lần mở đầu tiên ngay sau khi sidecar nạp dashboard, Grafana 13.3.2 vẽ các row trống; tải lại trang thì đủ panel. Panel độ trễ có chấm exemplar.
- **Cảnh báo Dependabot có từ trước (2026-11-26):** `io.opentelemetry:opentelemetry-api` 1.62.0 (BOM Boot 4.1.2) dính lỗi CPU bậc hai khi parse `tracestate` W3C, sửa ở 1.67.0. Không do ticket này gây ra, nhưng từ nay `hello` nhận header trace từ ngoài; xử lý khi nâng Boot hoặc ghim BOM OTel.
- **Bước 11:** [bản ghi](../../../experiments/2026-11-g0-30-tracing-cost.md). 50 request/s, cùng pod, xen kẽ cờ `traceparent` `01` và `00` (tương đương probability 1.0 và 0.0 với request gốc, không phải deploy lại): p99 ≈ 13,4 ms và ≈ 13,0 ms, CPU 0,07 và 0,06–0,07 core, nằm trong nhiễu; giữ sampling 100%. k6 2.4.0 tin root lab qua Keychain, không cần `--insecure-skip-tls-verify`.

