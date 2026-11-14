# 18: `service-kit` v0.1: convention plugin, ArchUnit, publish từ tag

Status: ready-for-human
Blocked by: 01
Repos: libs/service-kit, platform, docs
Spec: [G0](../spec.md)

## Mô tả

Repo `libs/service-kit` nhiều module, một version, với hai module đầu: `gradle-plugin` (convention `commercehub.spring-service`: ghim Java 25, minor Spring Boot 4.1, repository, bật ArchUnit) và `test-support` (luật ArchUnit cho layout hexagonal, cấu hình Testcontainers, bảng tag image). Reusable workflow `java-library` trong `platform` build, test và publish lên GitHub Packages chỉ từ tag `vX.Y.Z`. Theo ticket 11 của map và [ci-cd.md](../../../standards/ci-cd.md).

## Mục tiêu học

- Convention plugin của Gradle (precompiled script plugin) để gom cấu hình build.
- Publish artifact bất biến theo SemVer.

## Tiêu chí nghiệm thu

- [ ] Tag `v0.1.0` tạo package trên GitHub Packages; push lại cùng tag bị từ chối.
- [ ] Một project Gradle thử áp plugin, tải được artifact bằng PAT `read:packages` trên Mac.
- [ ] Luật ArchUnit tự kiểm: một package cố ý vi phạm (`domain` import Spring) làm test đỏ.
- [ ] Composite build `--include-build` từ project thử chạy được, không dùng SNAPSHOT.
- [ ] Workflow ghim SHA, có `timeout-minutes`, cache Gradle chỉ ghi trên nhánh mặc định; Dependabot có ecosystem `gradle`.
