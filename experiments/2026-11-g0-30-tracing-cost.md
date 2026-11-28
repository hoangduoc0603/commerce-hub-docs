# Chi phí tracing 100% của `hello` (G0-30 bước 11)

- Ngày đo: 2026-11-28. Ticket: [G0-30](../.scratch/g0-platform/issues/30-hello-observability.md). Chuẩn: [observability.md](../standards/observability.md), bảng "Kiểm chứng", dòng "Chi phí tracing".
- Câu hỏi: head sampling 100% (lựa chọn của observability.md cho N12) làm p99 và CPU của service tăng bao nhiêu so với không sample?

## Cách đo

- Đối tượng: `hello` image `a8b8459` trên lab, 1 pod, request CPU 250m, không CPU limit, `-XX:ActiveProcessorCount=2`, heap 60% của 512Mi. Ghi qua Pooler PgBouncer vào `pg-main`.
- Tải: k6 2.4.0 trên MacBook, kịch bản [`platform/load-tests/hello-tracing-cost.js`](https://github.com/hoangduoc0603/commerce-hub-platform/blob/main/load-tests/hello-tracing-cost.js). Mỗi request là `POST /v1/greetings` có JWT thật (client `smoke-test`, decoder kiểm chữ ký, iss, aud) và một INSERT. Executor `constant-arrival-rate` 50 request/s (open model), đi qua Tailscale và Gateway `edge` bằng HTTPS. k6 tin root của lab qua Keychain, **không** cần `--insecure-skip-tls-verify`.
- Hai cấu hình, khác đúng một điểm: mọi request đều mang `traceparent` với trace-id ngẫu nhiên; cờ `01` (được sample) hoặc `00` (không sample). Sampler `parent_based_trace_id_ratio` theo cờ của bên gọi, nên `01` tương đương `sampling.probability: 1.0` và `00` tương đương `0.0` với request gốc, mà không cần deploy lại pod. Nhờ vậy cả bốn lượt chạy trên **cùng một pod**, cùng trạng thái JIT và pool, và chạy xen kẽ được. Lệch so với tiêu chí của ticket (đổi property rồi deploy) là có chủ đích, để giảm nhiễu.
- Thứ tự: khởi động JVM 60 s (cờ `01`), nghỉ 20 s, rồi a1 (`01`), b1 (`00`), a2 (`01`), b2 (`00`). Mỗi lượt 120 s, nghỉ 40 s giữa các lượt.
- Độ trễ: `http_req_duration` của k6 (gồm mạng Mac → lab). CPU: hiệu của counter `container_cpu_usage_seconds_total{namespace="hello",container="app"}` trong cửa sổ [đầu lượt + 20 s, cuối lượt − 10 s], chia cho độ dài cửa sổ (cAdvisor được scrape mỗi 30 s).
- Kiểm cờ `00` thật sự không sample: Tempo có 15 023 trace `http post /v1/greetings` của `hello`, đúng bằng warmup (2 996) + a1 (6 002) + a2 (6 001) + khoảng 24 request smoke trước đó. Hai lượt `00` không thêm trace nào.

## Số đo

| Lượt | Cờ | Request | Lỗi | avg (ms) | p50 (ms) | p95 (ms) | p99 (ms) | max (ms) | CPU (core) |
|---|---|---|---|---|---|---|---|---|---|
| a1 | 01 | 6 002 | 0 | 7,26 | 6,66 | 10,88 | 13,68 | 48,69 | 0,14 |
| b1 | 00 | 6 002 | 0 | 7,07 | 6,71 | 10,10 | 12,90 | 47,51 | 0,07 |
| a2 | 01 | 6 001 | 0 | 6,73 | 6,20 | 8,91 | 13,05 | 211,28 | 0,07 |
| b2 | 00 | 6 002 | 0 | 6,97 | 6,18 | 10,42 | 13,15 | 244,25 | 0,06 |

Gộp hai lượt mỗi cấu hình: p99 sample 100% ≈ 13,4 ms, không sample ≈ 13,0 ms (chênh khoảng 0,3 ms, khoảng 3%). CPU của a2 so với b1, b2: 0,07 so với 0,06–0,07 core. Không lượt nào bị k6 bỏ request (`dropped_iterations` 0).

## Kết luận

- Ở 50 request/s, chi phí tracing 100% (tạo span HTTP, Security, JDBC; exemplar; gửi OTLP theo lô) **nằm trong nhiễu đo**: chênh p99 giữa hai cấu hình (≈ 0,3 ms) nhỏ hơn chênh giữa hai lượt cùng cấu hình, và max dao động lớn hơn nhiều (48 ms → 244 ms ở các lượt sau, do mạng và GC, không theo cấu hình).
- CPU của a1 (0,14) gấp đôi các lượt sau vì JIT còn biên dịch sau 60 s warmup, không phải do tracing: a2 cùng cấu hình chỉ 0,07. Lần đo sau cần warmup dài hơn (2–3 phút) hoặc bỏ lượt đầu.
- **Giữ head sampling 100% ở lab** như observability.md đã chọn. Phép đo này chưa trả lời được chi phí ở tải N6 (500 đơn/s): khi đó thử lại cùng kịch bản với tốc độ cao hơn và đo cả CPU của Collector (Collector chưa được Prometheus scrape, nên chưa có metric `otelcol_*`).

## Giới hạn

- Một pod, một lần đo mỗi cấu hình hai lượt; độ trễ gồm mạng Tailscale nên p99 có nhiễu cỡ vài ms.
- Cờ `00` vẫn tạo context và đọc header; khác `probability: 0.0` ở chỗ request gốc không mang header thì không phải parse. Chênh này nhỏ hơn nhiều so với việc ghi và gửi span.
