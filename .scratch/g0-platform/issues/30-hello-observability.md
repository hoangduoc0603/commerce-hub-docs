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
