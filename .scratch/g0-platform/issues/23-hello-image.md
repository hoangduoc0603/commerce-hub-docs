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
- Đổi: tạo project bằng generator Spring Boot của IntelliJ (hoặc start.spring.io), giữ mặc định của Initializr; layout hexagonal là quy ước (~~`package-info.java`~~ bỏ 2026-11-16, Q5), không có test kiến trúc. Repo GitHub `commerce-hub-hello` đã tạo ở lần làm bước 1 trước vẫn dùng; thư mục local tạo lại.
- Bỏ: phụ thuộc `service-kit` (plugin, `test-support`, GitHub Packages, PAT), `ArchitectureTest`, kiểm Dependabot đọc GitHub Packages.

## Sửa thứ tự 2026-11-15

Theo mục "Thứ tự làm" của spec G0 (vị trí 1 và 3). Ticket bắt đầu bằng các bước làm được trên máy: repo, app, Actuator, Dockerfile, Trivy chạy local, số đo image. Các bước cần workflow `java-service` của `platform` (push GHCR, digest trong output job, build ấm chỉ đẩy lại layer `application`) chờ ticket 17 xong. Cạnh chặn `17` vì vậy chỉ áp cho hai tiêu chí đánh dấu **(chờ 17)** bên dưới.

## Tiêu chí nghiệm thu

- [ ] `docker run --rm --entrypoint id <img>` trả `uid=10001`.
- [ ] Trivy 0 HIGH/CRITICAL đã có bản vá; đủ nhãn OCI.
- [ ] **(chờ 17)** Digest trong output job khớp tag SHA trên GHCR.
- [ ] Bản ghi `docs/experiments/` cho image: kích thước, build lạnh và ấm, thời gian khởi động có và không AOT cache.
- [ ] **(chờ 17)** Build ấm chỉ đẩy lại layer `application` và layer `app.aot`; `dependencies`, `spring-boot-loader`, `snapshot-dependencies` và layer user dùng lại (sửa 2026-11-16, Q6).

## Quyết định khi lập lộ trình (2026-11-15)

- Q1. Số đo trên máy (bước 6–8) build và chạy **arm64 native** trên Mac M1; bản ghi ghi rõ kiến trúc. Lý do: dưới giả lập amd64 (Rosetta/QEMU), training run và thời gian khởi động chủ yếu đo chi phí giả lập, không so được có và không AOT cache. Image chính thức vẫn là `linux/amd64` do CI build (container-image.md, mục "Đa kiến trúc"); số amd64 (kích thước, build lạnh và ấm) bổ sung ở bước 10.
- Q2. Trivy chạy local bằng image `aquasec/trivy:0.76.2` (đúng bản của container-image.md), quét file tar của image, không cài Trivy vào máy.
- ~~Q3. Kit ghim `0.1.1` (bản đầu có sửa review G0-18).~~ Bỏ cùng `service-kit` (2026-11-15).
- Q4 (2026-11-15). Wrapper giữ đúng version Gradle mà Initializr sinh (9.8.2 lúc tra), thêm `distributionSha256Sum` bằng lệnh `wrapper`; Dependabot ecosystem `gradle` lo nâng version sau.
- Q5 (2026-11-16). Bỏ bước 2 (`package-info.java` cho 4 package rỗng). Lý do: giữ đơn giản; luật phụ thuộc đã ở arc42 5.2; package ra đời cùng class đầu tiên (`adapter.out.persistence` ở G0-26, `adapter.in.web` ở G0-28), nên template vẫn có đủ khung trước khi service G1 sinh từ nó. Thêm `package-info.java` khi cần annotation cấp package. Sửa kèm [spring-service.md](../../../standards/spring-service.md), mục "Layout package".
- Q6 (2026-11-16). Giữ AOT cache trong image và sửa tiêu chí build ấm thành "chỉ đẩy lại layer `application` và `app.aot`" (phương án A). Lý do: `app.aot` (56,8 MB) phụ thuộc toàn bộ classpath, kể cả code của `hello`, nên đổi code là sinh lại; tiêu chí cũ chỉ đạt được nếu bỏ AOT cache. Đổi lại khởi động nhanh khoảng 2 lần (0,57 s so với 1,19 s, đo thử arm64). Loại: bỏ AOT cache (mất mục tiêu học thứ hai và story 71); sinh cache lúc container khởi động (lần đầu chậm, cần volume ghi được, không còn "build một lần, chạy y hệt").

## Lộ trình

Bước 1–8 làm ở vị trí 1 của "Thứ tự làm"; bước 9–10 ở vị trí 3, sau ticket 17.

Viết lại bước 1–2 ngày 2026-11-15 (bỏ `service-kit`). Lần làm bước 1 trước đã tạo repo GitHub `commerce-hub-hello` bằng `repo-bootstrap.sh`; thư mục local đã xóa.

- [x] 1. Tạo project bằng generator Spring Boot của IntelliJ (Gradle Groovy, Java 25, Boot 4.1.2, jar, group `io.github.hoangduoc0603.commercehub`, artifact `hello`, dependency Spring Web và Spring Boot Actuator) ở `services/hello`; thêm `distributionSha256Sum` cho wrapper; `git init -b main`; `repo-bootstrap.sh hello --local . --ecosystems gradle,docker` (repo GitHub đã có, chỉ còn scaffold); `.gitignore` bỏ cả `.idea/`; commit, audit, push; bật template repository. Kiểm: `./gradlew test` xanh (test `contextLoads` của Initializr); SHA-256 của wrapper khớp `services.gradle.org`; `repo-audit.sh hello --local . --ecosystems gradle,docker` PASS; `is_template` là `true`.
- ~~2. Layout hexagonal theo quy ước: `package-info.java` cho `domain`, `application`, `adapter.in.web`, `adapter.out.persistence`, mỗi file ghi lớp này được phụ thuộc vào đâu. Kiểm: `./gradlew build` xanh; `bootRun` lên và log có `Started HelloApplication`.~~ Bỏ 2026-11-16 (Q5). Kiểm `bootRun` gộp vào bước 3.
- [x] 3. Test request chạy trên virtual thread (đỏ) → `spring.threads.virtual.enabled`. Kiểm: test xanh; tắt property thì đỏ.
- [x] 4. Test Actuator chỉ ở cổng quản trị, `/livez` `/readyz` ở cổng chính (đỏ) → `management.server.port: 8081`, `add-additional-paths`. Kiểm: test xanh; `bootRun` thì `curl :8080/livez` là `UP`, `curl :8080/actuator/health` là 404.
- [x] 5. `.dockerignore`, Dockerfile multi-stage (4 layer, base ghim digest, `USER 10001:10001`, nhãn OCI, `ENTRYPOINT` exec), chưa AOT. Kiểm: `docker run --rm --entrypoint id` ra `uid=10001`; container trả `/livez` `UP`; đủ 7 nhãn OCI.
- [x] 6. AOT cache: training run trong runtime stage, `-XX:AOTCache=app.aot`. Kiểm: `-Xlog:aot` cho thấy cache được nạp.
- [ ] 7. Trivy local. Kiểm: `--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1` thoát 0; ngoại lệ (nếu có) trong `.trivyignore` kèm hạn.
- [ ] 8. Số đo arm64: kích thước, build lạnh và ấm, khởi động có và không AOT. Kiểm: `docs/experiments/2026-11-container-image-hello.md` đủ số.
- [ ] 9. **(chờ 17)** `java-service.yml` trong `platform` (check, Buildx `--pull` amd64, tag SHA, Trivy chặn và SARIF, push GHCR, output digest) và `ci.yml` mỏng trong `hello`. Kiểm: digest trong output job khớp `docker buildx imagetools inspect ghcr.io/…:<sha>`.
- [ ] 10. **(chờ 17)** Build ấm trên CI, số đo amd64, kết ticket. Kiểm: log push chỉ có layer `application` và `app.aot` mới (Q6).

## Kết quả

Bằng chứng theo mục "Bằng chứng cần có" của [spring-service.md](../../../standards/spring-service.md).

### Bước 1 (2026-11-16)

Commit đầu `abfc269` của `commerce-hub-hello`. Project sinh lần đầu nhầm Language Groovy (`id 'groovy'`, `src/main/groovy`); xóa, sinh lại với Language Java.

| Số đo | Kết quả |
|---|---|
| `./gradlew build` | Xanh, có `contextLoads`. Cảnh báo CDS "Sharing is only supported for boot loader classes" đến từ JVM test do Mockito tự gắn agent byte-buddy; giữ mặc định Initializr |
| `distributionSha256Sum` (Gradle 9.8.2) | `21bd5da2de49b642904077f38c0efdc7778e92b3ed0889392dca61b97e389607`, khớp `gradle-9.8.2-bin.zip.sha256` |
| SHA-256 `gradle-wrapper.jar` | `3b8a25775a69158b5ad2b1d17a80a88dc7b40a352a73eb27d06c612a7ce68e98`, khớp `gradle-9.8.2-wrapper.jar.sha256` |
| `javap -v … HelloApplication.class \| grep major` | `major version: 69` (Java 25) |
| `repo-audit.sh hello --local . --ecosystems gradle,docker` | Tất cả PASS (sau push; trước push mục "license MIT (GitHub nhận diện)" FAIL vì repo GitHub còn rỗng) |
| `gh api repos/hoangduoc0603/commerce-hub-hello --jq .is_template` | `true` |

### Bước 3 (2026-11-16)

Commit `8612707`. `VirtualThreadTests` gọi endpoint chỉ có trong test (`@TestConfiguration`) qua Tomcat thật (`RANDOM_PORT`), so `Thread.currentThread().toString()`.

| Trạng thái | Thread xử lý request |
|---|---|
| Chưa bật (đỏ) | `Thread[#44,http-nio-auto-1-exec-1,5,main]` |
| `spring.threads.virtual.enabled: true` (xanh) | `VirtualThread[#54,tomcat-handler-0]/runnable@ForkJoinPool-1-worker-1` |

`./gradlew test` xanh (2 class); `bootRun`: `Started HelloApplication in 1.03 seconds`.

### Bước 4 (2026-11-16)

`ActuatorPortTests` (3 test, `RestTestClient` của Spring Framework 7 qua Tomcat thật): trước cấu hình đỏ 2/3 (`/livez` 404; `/actuator/health` ở cổng chính 200). Sau `management.server.port: 8081` và `management.endpoint.health.probes.add-additional-paths: true`: `./gradlew test` xanh 5/5. Không cần `probes.enabled` ở Boot 4.1.2 khi chạy ngoài K8s.

`bootRun`: `:8080/livez` và `:8080/readyz` trả `{"status":"UP"}`, `:8080/actuator/health` 404, `:8081/actuator/health` trả `{"groups":["liveness","readiness"],"status":"UP"}`. Vấp: `curl localhost:8080` ra `404 page not found` vì một `kubectl port-forward` của Lens giữ `127.0.0.1:8080` và `[::1]:8080`, che socket `*:8080` của Spring; kiểm qua IP LAN thì đúng.

### Bước 5 (2026-11-16)

Base `eclipse-temurin:25-jre-noble@sha256:e3b6f7887a50f20d8f07abf279d8a81a5953fb398a9555bd9edd56b9bd15968c` (image index, JRE `25.0.5+8`). `.dockerignore` dạng allowlist (`*`, `!build/libs/*.jar`). Tắt task `jar` (plain jar) để `COPY build/libs/*.jar` khớp một file; vấp: `-plain.jar` cũ vẫn nằm trong `build/libs` cho tới `./gradlew clean`.

| Kiểm | Kết quả (arm64, chưa AOT) |
|---|---|
| `docker run --rm --entrypoint id hello:dev` | `uid=10001(app) gid=10001(app) groups=10001(app)` |
| Nhãn OCI | Đủ 7: `source`, `revision`, `version`, `created`, `title`, `base.name`, `base.digest` |
| `curl :18080/livez` (container) | `{"status":"UP"}`; `Started HelloApplication in 1.557 seconds` |
| PID 1 | `java -jar application.jar` |
| `docker stop` | 0,16 s, log có `Graceful shutdown complete` |
| Layer | `dependencies` 21,9 MB; `spring-boot-loader` 4,1 kB; `snapshot-dependencies` 4,1 kB; `application` 12,3 kB |

### Bước 6 (2026-11-16)

Commit `0bb4b87` (bước 4 và 5 nằm chung commit `ae26026`, vì phần `src/` của bước 4 không được commit riêng). Training run `java -XX:AOTCacheOutput=app.aot -Dspring.context.exit=onRefresh -jar application.jar` trong runtime stage, `ENTRYPOINT` thêm `-XX:AOTCache=app.aot`.

| Kiểm | Kết quả (arm64) |
|---|---|
| `-Xlog:aot` | `[info][aot] Opened AOT cache app.aot.`, không warning, không error |
| `-XX:AOTMode=on` | exit 0 |
| Layer `app.aot` | 56,8 MB; training 4,9 s lúc build |
| Khởi động (đo thử, 3 lần) | Có AOT 0,57–0,62 s; `-XX:AOTMode=off` 1,17–1,32 s. Số chính thức ở bước 8 |
| Jar bị `touch` sau khi train | `auto`: in `timestamp has changed` rồi chạy tiếp không cache; `on`: dừng với `shared class paths mismatch` |

Vấp: `ARG REVISION/VERSION/CREATED` đặt đầu runtime stage làm mọi `RUN` phía sau mất cache mỗi lần build, vì `CREATED` đổi mỗi lần (chỉ 4 bước `CACHED`, training chạy lại). Dời `ARG` và `LABEL` xuống sau training: đủ 10 bước `CACHED`, training không chạy lại. Nguồn: [Dockerfile reference – Impact on build caching](https://docs.docker.com/reference/dockerfile/#impact-on-build-caching).
