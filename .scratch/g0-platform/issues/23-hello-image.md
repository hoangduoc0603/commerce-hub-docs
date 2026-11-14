# 23: Image `hello` build một lần, quét, ký

Status: ready-for-human
Blocked by: 17, 18
Repos: services/hello, platform, docs
Spec: [G0](../spec.md)

## Mô tả

Repo `services/hello` ra đời: Spring Boot 4.1.2, Java 25, MVC trên virtual thread, convention plugin của `service-kit`, layout hexagonal rỗng (luật ArchUnit chạy), Actuator ở management port riêng, bật "template repository". Dockerfile theo [container-image.md](../../../standards/container-image.md) (layer Spring Boot, AOT cache, uid 10001, chỉ `linux/amd64`). Reusable workflow `java-service`: `./gradlew check`, build Buildx một lần, tag git SHA, Trivy chặn HIGH/CRITICAL có bản vá, SBOM, push lên registry lab, `actions/attest` rồi `gh attestation verify`.

## Mục tiêu học

- Chuỗi cung ứng image: build một lần, SBOM, provenance được verify.
- AOT cache của Java 25 so với không có.

## Tiêu chí nghiệm thu

- [ ] `docker run --rm --entrypoint id <img>` trả `uid=10001`.
- [ ] Trivy 0 HIGH/CRITICAL đã có bản vá; SBOM có gói Java và gói OS; đủ nhãn OCI.
- [ ] Digest trong output job khớp tag SHA trong registry.
- [ ] `gh attestation verify oci://10.20.0.5:5000/hello@<digest>` chạy được, hoặc ghi lý do bỏ vào lệch chuẩn của [ci-cd.md](../../../standards/ci-cd.md) (điểm chưa xác minh).
- [ ] Bản ghi `docs/experiments/` cho image: kích thước, build lạnh và ấm, thời gian khởi động có và không AOT cache.
- [ ] Build ấm chỉ đẩy lại layer `application`.
