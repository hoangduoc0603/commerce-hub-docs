# 19: `contracts`: OpenAPI của `hello`, chặn thay đổi phá vỡ, publish

Status: ready-for-human
Blocked by: 01
Repos: contracts, platform, docs
Spec: [G0](../spec.md)

## Mô tả

`contracts` chứa OpenAPI của `hello` (tạo lời chào từ `name` 1–50 ký tự trả 201 với ID và `Location`; đọc theo ID trả 200 hoặc 404; tiền tố `/v1`; bảo mật bearer JWT) và schema `Problem` dùng chung (RFC 9457, `traceId`, `errors[]`, danh mục `code` còn rỗng). Reusable workflow `contracts`: lint → `oasdiff breaking` so với tag trước → sinh code bằng `org.openapi.generator` → publish Maven và npm lên GitHub Packages chỉ từ tag. Theo ticket 11, 19 của map và [ci-cd.md](../../../standards/ci-cd.md).

## Sửa 2026-11-15 (bỏ `service-kit`)

Reusable workflow `java-library.yml` của `platform` (viết ở ticket 18 để publish Maven từ tag) đã xóa cùng `service-kit` ([ADR-0018](../../../adr/0018-self-contained-services-no-shared-library-yet.md)). Bước publish Maven của `contracts` viết trong workflow của ticket này; phần version, publish, bất biến của [java-library.md](../../../standards/java-library.md) vẫn áp dụng, mã cũ của `java-library.yml` xem trong history của `platform` (commit `f836c28`).

## Mục tiêu học

- Contract-first: OpenAPI là nguồn, code sinh ra, thay đổi phá vỡ bị chặn bằng máy.

## Tiêu chí nghiệm thu

- [ ] PR đổi kiểu một field response hoặc xóa endpoint làm CI đỏ ở bước `oasdiff breaking`.
- [ ] Công cụ lint OpenAPI đã chọn, có nguồn, ghi vào [ci-cd.md](../../../standards/ci-cd.md).
- [ ] Tag `v0.1.0` publish cả Maven lẫn npm; version không ghi đè được.
- [ ] Thử đọc package Maven từ CI của một repo khác bằng `GITHUB_TOKEN`; ghi kết quả (điểm chưa xác minh). Không được thì chuyển sang PAT `read:packages` trong secret.
