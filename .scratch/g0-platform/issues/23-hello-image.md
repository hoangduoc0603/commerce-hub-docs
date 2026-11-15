# 23: Image `hello` build một lần, quét, push lên GHCR

Status: ready-for-human
Blocked by: 17, 18
Repos: services/hello, platform, docs
Spec: [G0](../spec.md)

## Mô tả

Repo `services/hello` ra đời: Spring Boot 4.1.2, Java 25, MVC trên virtual thread, convention plugin của `service-kit`, layout hexagonal rỗng (luật ArchUnit chạy), Actuator ở management port riêng, bật "template repository". Dockerfile theo [container-image.md](../../../standards/container-image.md) (layer Spring Boot, AOT cache, uid 10001, chỉ `linux/amd64`). Reusable workflow `java-service`: `./gradlew check`, build Buildx một lần, tag git SHA, ghi digest, Trivy chặn HIGH/CRITICAL có bản vá, push lên GHCR bằng `GITHUB_TOKEN`.

## Mục tiêu học

- Chuỗi cung ứng image mức tối thiểu: build một lần, tag theo SHA, deploy theo digest, chặn lỗ hổng đã có bản vá.
- AOT cache của Java 25 so với không có.

## Thu hẹp 2026-11-15

Theo quyết định D6, D8 (spec G0 mục "Sửa phạm vi 2026-11-15").

- Giữ: build một lần, tag git SHA, ghi digest, Dockerfile theo [container-image.md](../../../standards/container-image.md), Trivy chặn HIGH/CRITICAL, số đo image.
- Đổi: push lên GHCR thay cho registry lab.
- Hoãn tới G7: SBOM, `actions/attest`, `gh attestation verify`.

Tiêu chí hoãn tới G7:

- SBOM có gói Java và gói OS.
- `gh attestation verify oci://ghcr.io/<owner>/hello@<digest>` chạy được trước bước sửa `gitops`.

## Tiêu chí nghiệm thu

- [ ] `docker run --rm --entrypoint id <img>` trả `uid=10001`.
- [ ] Trivy 0 HIGH/CRITICAL đã có bản vá; đủ nhãn OCI.
- [ ] Digest trong output job khớp tag SHA trên GHCR.
- [ ] Bản ghi `docs/experiments/` cho image: kích thước, build lạnh và ấm, thời gian khởi động có và không AOT cache.
- [ ] Build ấm chỉ đẩy lại layer `application`.
