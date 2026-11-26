# 28: `hello` theo contract với Problem Details

Status: resolved
Blocked by: 26 (bỏ 19 ngày 2026-11-24, [ADR-0019](../../../adr/0019-no-contracts-repo.md))
Repos: services/hello, docs (bỏ `libs/service-kit` ngày 2026-11-15)
Spec: [G0](../spec.md)

## Mô tả

~~Module `web` của `service-kit` (bản G0)~~ Code trong `hello` (sửa 2026-11-15): lỗi HTTP chung (401/404/405) trả `ProblemDetail` với `type: about:blank`, mọi lỗi có `traceId`, lỗi validate có `errors[]` (`pointer`, `detail`). ~~`hello` dùng module này, và~~ ~~Test kiểm request, response thật với OpenAPI lấy từ artifact `contracts` (ví dụ `swagger-request-validator` gắn vào MockMvc).~~ Test kiểm JSON bằng JsonPath trên đúng tên field (sửa 2026-11-24, ADR-0019). Cursor, `Idempotency-Key`, `ETag` để G1. Theo ticket 11, 19 của map.

## Sửa phạm vi 2026-11-15 (bỏ `service-kit`)

Theo [ADR-0018](../../../adr/0018-self-contained-services-no-shared-library-yet.md).

- Giữ: dạng Problem Details, `traceId`, `errors[]`, ~~test validator OpenAPI~~, deploy lên lab.

## Sửa phạm vi 2026-11-24 (bỏ `contracts`)

Theo [ADR-0019](../../../adr/0019-no-contracts-repo.md): không có OpenAPI hay artifact `contracts`. Test HTTP kiểm JSON bằng JsonPath trên đúng tên field thay cho validator OpenAPI. Danh mục `code` nằm trong `hello`.
- Đổi: code xử lý lỗi (ví dụ `@RestControllerAdvice` trong `adapter.in.web`) nằm trong `hello`; test dạng Problem Details là test HTTP của `hello`.
- Bỏ: test riêng của lib, publish `service-kit`.

## Mục tiêu học

- RFC 9457 Problem Details, và test giữ code không trôi khỏi contract.

## Tiêu chí nghiệm thu

- [x] `name` dài 51 ký tự trả 400 có `errors[0].pointer` đúng field; ID lạ trả 404; method sai trả 405; tất cả có `traceId`.
- [x] ~~Test validator OpenAPI chạy trên mọi test HTTP;~~ Test HTTP kiểm JSON bằng JsonPath trên đúng tên field (sửa 2026-11-24); đổi tên một field response trong code thì test đỏ.
- ~~Test của lib tự kiểm dạng Problem Details.~~ Thay bằng test HTTP của `hello` kiểm dạng Problem Details (2026-11-15).
- [x] ~~`service-kit` và~~ `hello` ~~publish bản mới;~~ có image mới và deploy lên lab qua GitOps.

## Lộ trình

Duyệt 2026-11-26. Quyết định khi lập lộ trình:

- **Q1 `traceId`**: thêm `spring-boot-starter-opentelemetry` ngay ở ticket này, `management.tracing.export.enabled: false` (ticket 30 bật export). `traceId` lấy từ `Tracer.currentSpan()`, trùng ID mà ticket 30 export. Loại: tự đọc `traceparent` hoặc tự sinh ID (phải viết lại ở 30, ID không khớp trace thật).
- **Q2 lỗi 500**: có handler cho `Exception`: 500 Problem Details có `traceId`, `detail` chung chung, stack trace chỉ vào log. Thiếu handler thì lỗi lạ rơi xuống `/error` của Boot, không phải `problem+json`, không có `traceId`.
- **Q3 chuẩn**: Claude viết `docs/standards/rest-api.md` (mức đầy đủ, chưa có file chuẩn cho API).
- 404 ID lạ dùng `type: about:blank`: G0 chưa có lỗi nghiệp vụ, danh mục `code` rỗng (spec G0). 401 thuộc ticket 29.

- [x] 0. (Claude) [`docs/standards/rest-api.md`](../../../standards/rest-api.md), phần lỗi: RFC 9457, `ProblemDetail` của Spring 7, `about:blank`/`urn:`, `traceId`, `errors[]` (`pointer` dạng `#/name`), không lộ giá trị gửi lên (N11). Kiểm: chủ repo duyệt.
- [x] 1. Test đỏ: 405, 404 đường dẫn lạ, 400 UUID sai dạng và JSON hỏng là `application/problem+json` với `title`, `status`, không có `type` (vắng mặt = `about:blank`, Spring 7.0 không ghi ra; đo 2026-11-26) (không kiểm `instance`: Spring 7.1 thôi tự điền, xem `rest-api.md`); `detail` của 400 UUID sai dạng không lặp giá trị gửi lên. Rồi `ApiExceptionHandler extends ResponseEntityExceptionHandler`, override `handleTypeMismatch`. Test ở class mới `ProblemDetailsTests` (dạng lỗi chung, không riêng lời chào). Kiểm: `./gradlew test` xanh.
- [x] 2. Test đỏ: ID lạ → 404 Problem Details. Controller ném `ErrorResponseException(NOT_FOUND)`. Kiểm: test xanh.
- [x] 3. Test đỏ: `name` 51 ký tự, `{}`, `""` có `errors[0].pointer == "#/name"` và `detail`. Override `handleMethodArgumentNotValid`; `@Pattern` có `message` tường minh; khóa locale `en` (`Accept-Language: de` đang đổi message sang tiếng Đức, đo 2026-11-26); unit test đổi field path sang JSON Pointer. Kiểm: test xanh, body không chứa giá trị gửi lên.
- [x] 4. Test đỏ: mọi lỗi có `traceId` 32 hex; request có `traceparent` thì `traceId` trùng. Starter OTel: tắt export span bằng `management.tracing.export.otlp.enabled: false` (không dùng `management.tracing.export.enabled`: property đó tắt cả propagation, đo 2026-11-26), tắt `OtlpMeterRegistry` (`management.otlp.metrics.export.enabled: false`, nó đẩy tới localhost:4318). Override `createResponseEntity`. Kiểm: test xanh; `bootTestRun` chạy hơn 1 phút không có `ConnectException`.
- [x] 5. Test đỏ: controller chỉ có trong test ném `RuntimeException("secret")` → 500 có `traceId`, body không chứa "secret". `@ExceptionHandler(Exception.class)` ghi log. Kiểm: test xanh, log có stack trace.
- [x] 6. Đổi tạm tên field (`traceId` hoặc `pointer`) trong code → test đỏ → đổi lại. Kiểm: đỏ rồi xanh.
- [x] 7. Push, CI, `update-gitops`, Argo CD sync; `curl -i` trên lab cho 404, 405, 400. Kiểm: `application/problem+json`, có `traceId`.
  - Làm 2026-11-26 (chủ repo giao Claude). [hello#10](https://github.com/hoangduoc0603/commerce-hub-hello/pull/10). Lần CI đầu đỏ ở `ci / image / build`: training run AOT trong Dockerfile khởi động app, và BuildKit trên runner gắn biến `OTEL_*` trỏ tới `unix:///dev/otel-grpc.sock` vào bước `RUN`; Boot 4 đọc biến `OTEL_*` thành property nên tạo `OtlpGrpcSpanExporter` và lỗi `Invalid endpoint, must start with http:// or https://`. Tái hiện trên máy: `OTEL_TRACES_EXPORTER=otlp` cộng endpoint đó và protocol `grpc` thì app không khởi động, **kể cả khi có** `management.tracing.export.otlp.enabled=false` ở yaml lẫn `-D`. Sửa: Dockerfile gỡ mọi `OTEL_*` trong lệnh `RUN` training (`0ebcc23`, trên `main` là `2745b06`). CI xanh, có dòng `writing AOTCache app.aot`. Merge rebase; bot ghi `gitops` `a32fac5` lúc 16:25:22 UTC; Argo CD sync xong 16:29:39 (Job migrate `Schema "public" is up to date`).
- [x] 8. Kết ticket theo `docs/agents/huong-dan.md` mục 4.

  - Làm 2026-11-26: `./gradlew test` của `hello` 47 test xanh, CI [hello#10](https://github.com/hoangduoc0603/commerce-hub-hello/pull/10) xanh. `code-review` (mức cơ bản) trên `b28780d...2745b06` ra 5 phát hiện, đều là nit, không sửa code: (1) `@ExceptionHandler(Exception.class)` che `@ResponseStatus` → ghi quy ước "lỗi nghiệp vụ dùng `ErrorResponseException`" vào `rest-api.md`; (2) sampling mặc định 0.1 → ghi vào ticket 30; (3) `toJsonPointer` tách sai key `Map` có dấu chấm → ghi giới hạn vào `rest-api.md`; (4) tên test N11 chưa mang mã yêu cầu (CLAUDE.md) → bỏ qua, các ticket `hello` trước cũng chưa ghi; (5) `OTEL_*` ở runtime đè yaml → ghi vào ticket 30. Ma trận truy vết: không có dòng tương ứng (ticket của template `hello`, như G0-26, G0-27); dòng N12 cập nhật ở G0-30.

## Kết quả

### Test giữ tên field (tiêu chí nghiệm thu 2, bước 6, 2026-11-26)

Trên nhánh `g0-28` sau commit `c6ea970`, mỗi lần đổi một tên rồi chạy `./gradlew test`, xong khôi phục bằng `git checkout`.

| Đổi trong code | Test đỏ | Ở đâu |
|---|---|---|
| Extension `traceId` → `traceID` (`ApiExceptionHandler.createResponseEntity`) | 11 | `ProblemDetailsTests` 10, `UnexpectedErrorTests` 1 |
| `errors[].pointer` → `path` (`FieldViolation`) | 4 | `ProblemDetailsTests` (4 case validate) |
| Field response `createdAt` → `created` (`GreetingResponse`) | 1 | `GreetingApiTests.createdGreetingCanBeReadBack` |
| Khôi phục | 0 | 47 test xanh |

Không phủ, có chủ ý: thêm field mới (thay đổi tương thích, client là tolerant reader; RFC 9457 §3.2) và `instance` (không thuộc contract, xem `rest-api.md`).

### Trên lab (bước 7, 2026-11-26 16:30 UTC, image `sha256:11fa29cb…`, commit `2745b06`)

Trước deploy (image `aef028f`): `GET /v1/greetings/<id lạ>` trả `HTTP/2 404`, `content-length: 0`.

| Request qua `https://hello.lab.internal` | Kết quả |
|---|---|
| `GET /v1/greetings/<id lạ>` kèm `traceparent: 00-4bf92f35…4736-…-01` | `404`, `application/problem+json`, `"detail":"Greeting not found"`, `"traceId":"4bf92f3577b34da6a3ce929d0e0e4736"`: header đi qua Envoy `edge` nguyên vẹn |
| `DELETE /v1/greetings/<id>` | `405`, `allow: GET`, Problem Details có `traceId` |
| `POST` `name` 51 ký tự | `400`, `"errors":[{"pointer":"#/name","detail":"size must be between 1 and 50"}]`, có `traceId`, không chứa giá trị gửi lên |
| `GET /khong-co` (Tomcat thật, không MockMvc) | `404` Problem Details có `traceId` |
| `GET /v1/greetings/%zz` | `400` **`text/html`** trang lỗi của Tomcat: URL hỏng bị Tomcat từ chối trước Spring, handler không chạm tới. Giới hạn đã biết (`rest-api.md`, lỗi ngoài DispatcherServlet), không sửa ở G0 |

- Log sau hơn 2 phút chạy: 0 dòng khớp `4318|ConnectException|v1/logs|v1/metrics|otlp`, tức là starter không tự gửi log hay metric qua OTLP khi đã tắt như `observability.md`. Một `WARN … PageNotFound : Request method 'DELETE' is not supported` do chính Spring ghi cho 405 (mức WARN, không phải ERROR).
- Log có `traceId` của client: 3 dòng `[4bf92f35…4736-…]`, là lúc Hikari mở pool ở request đầu tiên. Pool mở lười: request đầu sau khi pod khởi động chịu thêm khoảng 220 ms. Ghi lại cho G0-33 (zero-downtime).
- Bộ nhớ pod mới: 160Mi ở phút thứ 2,5 (limit 512Mi). Pod cũ 174Mi sau 22 giờ chạy, nên không so trực tiếp được; đo lại ở G0-30 khi bật export.

## Bài học

- Problem Details trong Spring 7 gần như có sẵn: một advice kế thừa `ResponseEntityExceptionHandler` cộng một override `createResponseEntity` là đủ phủ mọi lỗi. Phần khó nằm ở những gì mặc định để lộ hoặc làm lệch: `detail` của type mismatch lặp lại giá trị client gửi, `@Pattern` lộ regex, message validate đổi ngôn ngữ theo `Accept-Language`, và `type` vắng mặt trong JSON ở Spring 7.0.
- Ba bẫy chỉ lộ ra khi chạy thật, không đọc docs mà thấy: `management.tracing.export.enabled=false` tắt luôn propagation; starter OTel kéo `OtlpMeterRegistry` đẩy metric tới `localhost:4318`; BuildKit gắn biến `OTEL_*` vào bước `RUN`, và biến này đè cả yaml lẫn `-D`, làm đỏ build image.
- Câu chuyện phỏng vấn: "Lỗi API trả body rỗng, người dùng báo lỗi mà không tìm được log. Tôi chuẩn hóa theo RFC 9457, mọi lỗi mang `traceId` lấy từ Micrometer Tracing. Đo trên lab: `traceparent` từ client đi qua gateway và quay về nguyên vẹn trong body; lỗi 500 có dòng log ERROR mang đúng `traceId` đó. Đổi tên một field thì 1–11 test đỏ, đó là contract test thay cho OpenAPI."

