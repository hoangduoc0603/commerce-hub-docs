# 23: Image `hello` build một lần, quét, push lên GHCR

Status: ready-for-human
Blocked by: 01 (các bước CI chờ 17, xem mục "Sửa thứ tự 2026-11-15"; bỏ 18 ngày 2026-11-15, [ADR-0018](../../../adr/0018-self-contained-services-no-shared-library-yet.md))
Repos: services/hello, platform, docs
Spec: [G0](../spec.md)

## Mô tả

Repo `services/hello` ra đời: Spring Boot 4.1.2, Java 25, MVC trên virtual thread, ~~convention plugin của `service-kit`~~ project do Spring Initializr sinh và giữ mặc định theo [spring-service.md](../../../standards/spring-service.md), layout hexagonal rỗng ~~(luật ArchUnit chạy)~~ là quy ước, Actuator ở management port riêng, bật "template repository". Dockerfile theo [container-image.md](../../../standards/container-image.md) (layer Spring Boot, AOT cache, uid 10001, chỉ `linux/amd64`). Reusable workflow `java-service`: `./gradlew check`, build Buildx một lần, tag git SHA, ghi digest, Trivy chặn HIGH/CRITICAL có bản vá, push lên GHCR bằng `GITHUB_TOKEN`.

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

## Sửa phạm vi 2026-11-15 (bỏ `service-kit`)

Theo [ADR-0018](../../../adr/0018-self-contained-services-no-shared-library-yet.md) (spec G0 mục "Sửa phạm vi 2026-11-15", gạch đầu dòng "Bỏ thư viện dùng chung"). Quyết định khi đang làm bước 1: chủ repo thấy convention plugin, GitHub Packages và PAT làm rối phần cấu hình muốn tự học.

- Giữ: mọi tiêu chí nghiệm thu, Dockerfile, Trivy, CI, số đo; virtual thread, Actuator ở cổng riêng, template repository.
- Đổi: tạo project bằng generator Spring Boot của IntelliJ (hoặc start.spring.io), giữ mặc định của Initializr; layout hexagonal là quy ước (`package-info.java`), không có test kiến trúc. Repo GitHub `commerce-hub-hello` đã tạo ở lần làm bước 1 trước vẫn dùng; thư mục local tạo lại.
- Bỏ: phụ thuộc `service-kit` (plugin, `test-support`, GitHub Packages, PAT), `ArchitectureTest`, kiểm Dependabot đọc GitHub Packages.

## Sửa thứ tự 2026-11-15

Theo mục "Thứ tự làm" của spec G0 (vị trí 1 và 3). Ticket bắt đầu bằng các bước làm được trên máy: repo, app, Actuator, Dockerfile, Trivy chạy local, số đo image. Các bước cần workflow `java-service` của `platform` (push GHCR, digest trong output job, build ấm chỉ đẩy lại layer `application`) chờ ticket 17 xong. Cạnh chặn `17` vì vậy chỉ áp cho hai tiêu chí đánh dấu **(chờ 17)** bên dưới.

## Tiêu chí nghiệm thu

- [ ] `docker run --rm --entrypoint id <img>` trả `uid=10001`.
- [ ] Trivy 0 HIGH/CRITICAL đã có bản vá; đủ nhãn OCI.
- [ ] **(chờ 17)** Digest trong output job khớp tag SHA trên GHCR.
- [ ] Bản ghi `docs/experiments/` cho image: kích thước, build lạnh và ấm, thời gian khởi động có và không AOT cache.
- [ ] **(chờ 17)** Build ấm chỉ đẩy lại layer `application`.

## Quyết định khi lập lộ trình (2026-11-15)

- Q1. Số đo trên máy (bước 6–8) build và chạy **arm64 native** trên Mac M1; bản ghi ghi rõ kiến trúc. Lý do: dưới giả lập amd64 (Rosetta/QEMU), training run và thời gian khởi động chủ yếu đo chi phí giả lập, không so được có và không AOT cache. Image chính thức vẫn là `linux/amd64` do CI build (container-image.md, mục "Đa kiến trúc"); số amd64 (kích thước, build lạnh và ấm) bổ sung ở bước 10.
- Q2. Trivy chạy local bằng image `aquasec/trivy:0.76.2` (đúng bản của container-image.md), quét file tar của image, không cài Trivy vào máy.
- ~~Q3. Kit ghim `0.1.1` (bản đầu có sửa review G0-18).~~ Bỏ cùng `service-kit` (2026-11-15).
- Q4 (2026-11-15). Wrapper giữ đúng version Gradle mà Initializr sinh (9.8.2 lúc tra), thêm `distributionSha256Sum` bằng lệnh `wrapper`; Dependabot ecosystem `gradle` lo nâng version sau.

## Lộ trình

Bước 1–8 làm ở vị trí 1 của "Thứ tự làm"; bước 9–10 ở vị trí 3, sau ticket 17.

Viết lại bước 1–2 ngày 2026-11-15 (bỏ `service-kit`). Lần làm bước 1 trước đã tạo repo GitHub `commerce-hub-hello` bằng `repo-bootstrap.sh`; thư mục local đã xóa.

- [ ] 1. Tạo project bằng generator Spring Boot của IntelliJ (Gradle Groovy, Java 25, Boot 4.1.2, jar, group `io.github.hoangduoc0603.commercehub`, artifact `hello`, dependency Spring Web và Spring Boot Actuator) ở `services/hello`; thêm `distributionSha256Sum` cho wrapper; `git init -b main`; `repo-bootstrap.sh hello --local . --ecosystems gradle,docker` (repo GitHub đã có, chỉ còn scaffold); `.gitignore` bỏ cả `.idea/`; commit, audit, push; bật template repository. Kiểm: `./gradlew test` xanh (test `contextLoads` của Initializr); SHA-256 của wrapper khớp `services.gradle.org`; `repo-audit.sh hello --local . --ecosystems gradle,docker` PASS; `is_template` là `true`.
- [ ] 2. Layout hexagonal theo quy ước: `package-info.java` cho `domain`, `application`, `adapter.in.web`, `adapter.out.persistence`, mỗi file ghi lớp này được phụ thuộc vào đâu. Kiểm: `./gradlew build` xanh; `bootRun` lên và log có `Started HelloApplication`.
- [ ] 3. Test request chạy trên virtual thread (đỏ) → `spring.threads.virtual.enabled`. Kiểm: test xanh; tắt property thì đỏ.
- [ ] 4. Test Actuator chỉ ở cổng quản trị, `/livez` `/readyz` ở cổng chính (đỏ) → `management.server.port: 8081`, `add-additional-paths`. Kiểm: test xanh; `bootRun` thì `curl :8080/livez` là `UP`, `curl :8080/actuator/health` là 404.
- [ ] 5. `.dockerignore`, Dockerfile multi-stage (4 layer, base ghim digest, `USER 10001:10001`, nhãn OCI, `ENTRYPOINT` exec), chưa AOT. Kiểm: `docker run --rm --entrypoint id` ra `uid=10001`; container trả `/livez` `UP`; đủ 7 nhãn OCI.
- [ ] 6. AOT cache: training run trong runtime stage, `-XX:AOTCache=app.aot`. Kiểm: `-Xlog:aot` cho thấy cache được nạp.
- [ ] 7. Trivy local. Kiểm: `--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1` thoát 0; ngoại lệ (nếu có) trong `.trivyignore` kèm hạn.
- [ ] 8. Số đo arm64: kích thước, build lạnh và ấm, khởi động có và không AOT. Kiểm: `docs/experiments/2026-11-container-image-hello.md` đủ số.
- [ ] 9. **(chờ 17)** `java-service.yml` trong `platform` (check, Buildx `--pull` amd64, tag SHA, Trivy chặn và SARIF, push GHCR, output digest) và `ci.yml` mỏng trong `hello`. Kiểm: digest trong output job khớp `docker buildx imagetools inspect ghcr.io/…:<sha>`.
- [ ] 10. **(chờ 17)** Build ấm trên CI, số đo amd64, kết ticket. Kiểm: log push chỉ có layer `application` mới.
