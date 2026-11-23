# 28: `hello` theo contract với Problem Details

Status: ready-for-human
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

- [ ] `name` dài 51 ký tự trả 400 có `errors[0].pointer` đúng field; ID lạ trả 404; method sai trả 405; tất cả có `traceId`.
- [ ] ~~Test validator OpenAPI chạy trên mọi test HTTP;~~ Test HTTP kiểm JSON bằng JsonPath trên đúng tên field (sửa 2026-11-24); đổi tên một field response trong code thì test đỏ.
- ~~Test của lib tự kiểm dạng Problem Details.~~ Thay bằng test HTTP của `hello` kiểm dạng Problem Details (2026-11-15).
- [ ] ~~`service-kit` và~~ `hello` ~~publish bản mới;~~ có image mới và deploy lên lab qua GitOps.
