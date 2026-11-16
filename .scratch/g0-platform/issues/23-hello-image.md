# 23: Image `hello` build một lần, quét, push lên GHCR

Status: resolved
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

- [x] `docker run --rm --entrypoint id <img>` trả `uid=10001`.
- [x] Trivy 0 HIGH/CRITICAL đã có bản vá; đủ nhãn OCI.
- [x] **(chờ 17)** Digest trong output job khớp tag SHA trên GHCR.
- [x] Bản ghi `docs/experiments/` cho image: kích thước, build lạnh và ấm, thời gian khởi động có và không AOT cache.
- [x] **(chờ 17)** Build ấm chỉ đẩy lại layer `application` và layer `app.aot`; `dependencies`, `spring-boot-loader`, `snapshot-dependencies` và layer user dùng lại (sửa 2026-11-16, Q6).

## Quyết định khi lập lộ trình (2026-11-15)

- Q1. Số đo trên máy (bước 6–8) build và chạy **arm64 native** trên Mac M1; bản ghi ghi rõ kiến trúc. Lý do: dưới giả lập amd64 (Rosetta/QEMU), training run và thời gian khởi động chủ yếu đo chi phí giả lập, không so được có và không AOT cache. Image chính thức vẫn là `linux/amd64` do CI build (container-image.md, mục "Đa kiến trúc"); số amd64 (kích thước, build lạnh và ấm) bổ sung ở bước 10.
- Q2. Trivy chạy local bằng image `aquasec/trivy:0.76.2` (đúng bản của container-image.md), quét file tar của image, không cài Trivy vào máy.
- ~~Q3. Kit ghim `0.1.1` (bản đầu có sửa review G0-18).~~ Bỏ cùng `service-kit` (2026-11-15).
- Q4 (2026-11-15). Wrapper giữ đúng version Gradle mà Initializr sinh (9.8.2 lúc tra), thêm `distributionSha256Sum` bằng lệnh `wrapper`; Dependabot ecosystem `gradle` lo nâng version sau.
- Q5 (2026-11-16). Bỏ bước 2 (`package-info.java` cho 4 package rỗng). Lý do: giữ đơn giản; luật phụ thuộc đã ở arc42 5.2; package ra đời cùng class đầu tiên (`adapter.out.persistence` ở G0-26, `adapter.in.web` ở G0-28), nên template vẫn có đủ khung trước khi service G1 sinh từ nó. Thêm `package-info.java` khi cần annotation cấp package. Sửa kèm [spring-service.md](../../../standards/spring-service.md), mục "Layout package".
- Q6 (2026-11-16). Giữ AOT cache trong image và sửa tiêu chí build ấm thành "chỉ đẩy lại layer `application` và `app.aot`" (phương án A). Lý do: `app.aot` (56,8 MB) phụ thuộc toàn bộ classpath, kể cả code của `hello`, nên đổi code là sinh lại; tiêu chí cũ chỉ đạt được nếu bỏ AOT cache. Đổi lại khởi động nhanh khoảng 2 lần (0,57 s so với 1,19 s, đo thử arm64). Loại: bỏ AOT cache (mất mục tiêu học thứ hai và story 71); sinh cache lúc container khởi động (lần đầu chậm, cần volume ghi được, không còn "build một lần, chạy y hệt").

## Quyết định cho bước CI (2026-11-17)

Chốt với chủ repo khi bắt đầu bước 9 (sau ticket 17). Bước 9 tách thành 9a–9c.

- Q7. `java-service.yml` **gọi lồng** `container-image.yml`; tham chiếu bằng đường dẫn đầy đủ `hoangduoc0603/commerce-hub-platform/.github/workflows/container-image.yml@<SHA>`, không dùng `./` (trong workflow ở giữa chuỗi, `./` trỏ về repo nào: **chưa xác minh**). Chỉ thêm 2 input `artifact`, `artifact-path`; mọi phần khác (nhãn, cache, Trivy, SARIF) dùng chung cho mọi image. GitHub cho lồng tới 10 tầng, quyền chỉ giữ hoặc hạ dọc chuỗi ([Reuse workflows – Nesting](https://docs.github.com/en/actions/how-tos/reuse-automations/reuse-workflows#nesting-reusable-workflows)). Loại: `java-service.yml` tự build (hai nơi giữ Trivy, cache, kiểm tag).
- Q8. Nhãn `revision`, `version`, `created` do workflow đặt qua `labels:` của `build-push-action` (chỉ CI biết giá trị); Dockerfile giữ 4 nhãn tĩnh (`source`, `title`, `base.name`, `base.digest`) và bỏ 3 `ARG`. Image build ở máy thiếu 3 nhãn này; tiêu chí đo trên image CI. Loại: `build-args` (thêm input nhiều dòng, mọi Dockerfile phải khai `ARG`).
- Q9. Quét trước push theo mẫu "Test before push" của Docker: `load: true` → `docker save` → Trivy (image `aquasec/trivy:0.76.2` ghim digest như Q2, không dùng `trivy-action` vì tag bị dời 3/2026) → build lại với `push: true`, cùng input, mọi bước lấy từ cache của builder. Bằng chứng: Image ID của bản đã quét bằng config digest trên GHCR. Cache BuildKit `type=gha`, scope theo image; PR chỉ đọc, `main` ghi `mode=max`. Loại: OCI tar + `skopeo` (thêm công cụ); `docker push` bản đã load (nén lại, digest khác); cache `type=registry` (tag `:buildcache` đổi được, trái luật tag = SHA).
- Q10. Lịch hằng tuần trong `ci.yml` của `hello` chỉ chạy job `build` (không push): base ghim digest nên build lại không nhận bản vá; bản vá đến qua PR Dependabot đổi digest. Lịch tuần là **quét lại** với DB Trivy mới. Câu hỏi (5) của bước 9 cũ không còn.
- Q11. Làm luôn SARIF (`security-events: write`) và dependency graph Gradle (`contents: write`, chỉ `main`). `ci.yml` của `hello` cấp `contents: write`, `packages: write`, `security-events: write`; từng job tự hạ. `platform` ra `v0.2.0` (SemVer mục 4: bản 0.x đổi được ở MINOR).

## Lộ trình

Bước 1–8 làm ở vị trí 1 của "Thứ tự làm"; bước 9–10 ở vị trí 3, sau ticket 17.

Viết lại bước 1–2 ngày 2026-11-15 (bỏ `service-kit`). Lần làm bước 1 trước đã tạo repo GitHub `commerce-hub-hello` bằng `repo-bootstrap.sh`; thư mục local đã xóa.

- [x] 1. Tạo project bằng generator Spring Boot của IntelliJ (Gradle Groovy, Java 25, Boot 4.1.2, jar, group `io.github.hoangduoc0603.commercehub`, artifact `hello`, dependency Spring Web và Spring Boot Actuator) ở `services/hello`; thêm `distributionSha256Sum` cho wrapper; `git init -b main`; `repo-bootstrap.sh hello --local . --ecosystems gradle,docker` (repo GitHub đã có, chỉ còn scaffold); `.gitignore` bỏ cả `.idea/`; commit, audit, push; bật template repository. Kiểm: `./gradlew test` xanh (test `contextLoads` của Initializr); SHA-256 của wrapper khớp `services.gradle.org`; `repo-audit.sh hello --local . --ecosystems gradle,docker` PASS; `is_template` là `true`.
- ~~2. Layout hexagonal theo quy ước: `package-info.java` cho `domain`, `application`, `adapter.in.web`, `adapter.out.persistence`, mỗi file ghi lớp này được phụ thuộc vào đâu. Kiểm: `./gradlew build` xanh; `bootRun` lên và log có `Started HelloApplication`.~~ Bỏ 2026-11-16 (Q5). Kiểm `bootRun` gộp vào bước 3.
- [x] 3. Test request chạy trên virtual thread (đỏ) → `spring.threads.virtual.enabled`. Kiểm: test xanh; tắt property thì đỏ.
- [x] 4. Test Actuator chỉ ở cổng quản trị, `/livez` `/readyz` ở cổng chính (đỏ) → `management.server.port: 8081`, `add-additional-paths`. Kiểm: test xanh; `bootRun` thì `curl :8080/livez` là `UP`, `curl :8080/actuator/health` là 404.
- [x] 5. `.dockerignore`, Dockerfile multi-stage (4 layer, base ghim digest, `USER 10001:10001`, nhãn OCI, `ENTRYPOINT` exec), chưa AOT. Kiểm: `docker run --rm --entrypoint id` ra `uid=10001`; container trả `/livez` `UP`; đủ 7 nhãn OCI.
- [x] 6. AOT cache: training run trong runtime stage, `-XX:AOTCache=app.aot`. Kiểm: `-Xlog:aot` cho thấy cache được nạp.
- [x] 7. Trivy local. Kiểm: `--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1` thoát 0; ngoại lệ (nếu có) trong `.trivyignore` kèm hạn.
- [x] 8. Số đo arm64: kích thước, build lạnh và ấm, khởi động có và không AOT. Kiểm: `docs/experiments/2026-11-container-image-hello.md` đủ số.
- [x] 9a. `container-image.yml` trên nhánh của `platform`: input `artifact`, `artifact-path`; nhãn động (Q8); cache `type=gha` (Q9); `load` → Trivy chặn + SARIF → push đúng bản (Q9). Thử bằng PR `ghcr-smoke`: commit đầu `FROM` alpine cũ, commit sau trả lại. Kiểm: PR đỏ ở bước Trivy rồi xanh; merge thì `publish` xanh; Image ID bản quét bằng config digest trên GHCR; alert trong Code scanning.
- [x] 9b. `java-service.yml` (`check`, `dependency-graph`, `image` gọi lồng `container-image.yml@<SHA>`) và `ci.yml` của `hello` ghim SHA nhánh; Dockerfile bỏ 3 `ARG` (Q8). Kiểm: `actionlint` sạch, grep ghim SHA 0 dòng; PR của `hello`: `check`, `image / build` xanh, `publish` skipped.
- [x] 9c. Release `platform` `v0.2.0`, `ci.yml` ghim SHA release, push `main` của `hello`. Kiểm: digest trong output khớp `imagetools inspect ghcr.io/…/commerce-hub-hello:<sha>`; `uid=10001`; đủ 7 nhãn; Trivy 0 HIGH/CRITICAL.
- ~~9. **(chờ 17)** `java-service.yml` trong `platform` (check, Buildx `--pull` amd64, tag SHA, Trivy chặn và SARIF, push GHCR, output digest) và `ci.yml` mỏng trong `hello`. Kiểm: digest trong output job khớp `docker buildx imagetools inspect ghcr.io/…:<sha>`.~~ Tách thành 9a–9c ngày 2026-11-17 (mục "Quyết định cho bước CI").
  - Chuyển từ review G0-17 (2026-11-16): `container-image.yml` `v0.1.1` (ghim `c4b5d70da6b2b2f82edff675938c3d254b23129a`) chưa dùng nguyên được cho `hello`. `java-service.yml` gọi lồng nó thì phải thêm vào `container-image.yml` và ra `v0.2.0` (MINOR, input mới có mặc định): (1) nhận jar từ job `check` bằng artifact (Dockerfile `COPY build/libs/*.jar`, mà job image checkout lại từ đầu); (2) `build-args` cho `REVISION`, `VERSION`, `CREATED` (nhãn OCI, [container-image.md](../../../standards/container-image.md)); chốt nhãn nào đặt trong workflow, nhãn nào trong Dockerfile; (3) cache BuildKit (`cache-from`/`cache-to`), không có thì trượt Q6 (layer user sinh lại mỗi lần); (4) tách build → `load` → Trivy → push đúng bản đã build, không build hai lần; (5) quyết định lần build lại hằng tuần (container-image.md) có push không, vì `publish` hiện chỉ chạy trên `push` vào nhánh mặc định, trong khi tag = SHA không đổi và bước "kiểm tag chưa tồn tại" sẽ chặn. Nếu thấy gọi lồng làm workflow quá nhiều input thì `java-service.yml` tự build, ghi lý do.
- [x] 10. **(chờ 17)** Build ấm trên CI, số đo amd64, kết ticket. Kiểm: log push chỉ có layer `application` và `app.aot` mới (Q6).

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

### Bước 7 (2026-11-16)

Image `hello:dev` commit `0bb4b87` (arm64), `docker save` ra `build/image/hello.tar`, quét bằng `aquasec/trivy:0.76.2@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb` (mount tar chỉ đọc, không mount `docker.sock`; DB cache trong volume `trivy-cache`, DB cập nhật 2026-11-16 13:03 UTC).

| Kiểm | Kết quả |
|---|---|
| `--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1` | exit 0. 42 target đều `0`: Ubuntu 24.04 (108 gói) và 41 jar trong `application/lib/`. Không thấy secret |
| Mọi mức, kể cả chưa vá | 0 HIGH, 0 CRITICAL; 38 MEDIUM, 4 LOW |
| MEDIUM đã có bản vá | 18, đều ở glibc của base (`libc-bin`, `libc6`, `locales`); hết khi Temurin ra digest mới và Dependabot mở PR |
| Cổng chặn: `--severity MEDIUM --ignore-unfixed --exit-code 1` | exit 1, cổng hoạt động |
| `.trivyignore` | Không cần |

Lần quét đầu 1 phút 14 giây (tải DB), các lần sau vài giây.

### Bước 8 (2026-11-16)

Bản ghi [2026-11-container-image-hello.md](../../../experiments/2026-11-container-image-hello.md), link từ [2026-11-g0.md](../../../experiments/2026-11-g0.md). Image commit `0bb4b87`, arm64 native trên Mac M1 Pro.

| Số đo | Kết quả |
|---|---|
| Kích thước | 563 MB giải nén, 136,1 MB nén; base 102,4 MB nén, `hello` thêm 33,8 MB (`dependencies` 19,6 MB, `app.aot` 14,1 MB, `application` 1,8 kB) |
| Build lạnh (`--no-cache`, trung vị 3 lần) | Docker 7,00 s; Gradle `clean bootJar` 0,81 s |
| Build ấm (sửa 1 class, trung vị 3 lần) | 8,25 s; chỉ layer 11 và 12 (`application`, `app.aot`) đổi |
| Build không đổi code | 1,31 s |
| Khởi động, trung vị 5 lần (`process running for`) | Có AOT 0,729 s; không AOT 1,545 s; nhanh hơn 2,1 lần |

Vấp: lần đo build ấm đầu chỉ 2,05 s, vì hằng số thêm vào trùng giá trị đã build ở bản chép; jar tái lập được nên BuildKit dùng lại cache. Đo lại với giá trị mới mỗi lần.

Ghi cho bước 9: hai lần `--no-cache` từ cùng jar ra layer `groupadd`, `WORKDIR`, `dependencies`, `application`, `app.aot` khác nhau, vì mtime ghi lúc build. Runner CI không có BuildKit cache thì mỗi lần đẩy lại cả `dependencies`; cần `cache-from`/`cache-to` hoặc chuẩn hóa timestamp để đạt tiêu chí Q6 (**chưa xác minh** cách nào hợp GHCR).

### Bước 9a (2026-11-17)

`platform` [PR #2](https://github.com/hoangduoc0603/commerce-hub-platform/pull/2), commit `22fa4dd` (workflow, smoke tạm `FROM alpine:3.10.0`) và `217c655` (trả `FROM scratch`); fast-forward `main` lên `217c655`.

| Kiểm | Kết quả |
|---|---|
| `actionlint` 1.7.12; grep ghim SHA của ci-cd.md | Sạch; 0 dòng |
| Run `43914392475` (PR, alpine 3.10.0) | `image / build` **failure** ở bước Trivy: `Total: 12 (HIGH: 9, CRITICAL: 3)`, exit 1 (ví dụ `apk-tools` CVE-2021-36159 CRITICAL, đã vá ở 2.10.7-r0). `publish` skipped. SARIF vẫn đẩy: Code scanning có analysis `trivy-image-commerce-hub-platform-smoke` trên `refs/pull/2/merge`, 30 kết quả |
| Run PR với `FROM scratch` | `image / build` success; Trivy chỉ cảnh báo "Supported files for scanner(s) not found" |
| Run `43914858831` (push `main`) | `image / publish` success. Digest `sha256:1b33a28c…4311`. Config digest bản đã quét (Image ID) và `config.digest` trên GHCR đều `sha256:10756463…e4dd`; bước "Kiểm bản push trùng bản đã quét": `Layer trùng nhau (1 layer)` |
| Nhãn trên GHCR | `source`, `revision` = `version` = `217c655…`, `created` `2026-11-16T17:06:51Z` |

### Bước 9b (2026-11-17)

`platform` commit `b8c6fde` (`java-service.yml`, gọi lồng `container-image.yml@217c655…`). `hello` [PR #2](https://github.com/hoangduoc0603/commerce-hub-hello/pull/2): `ci.yml` (push `main`, PR, `schedule` thứ Hai 03:17 UTC, `workflow_dispatch`; ghim `java-service.yml@b8c6fde…` lúc thử), Dockerfile bỏ 3 `ARG` và 3 nhãn động (Q8).

| Kiểm | Kết quả |
|---|---|
| `actionlint` cả hai repo; grep ghim SHA của `platform` | Sạch; 0 dòng |
| Run `43915365966` (PR của `hello`) | `ci / check` success (58 s, `BUILD SUCCESSFUL in 40s`); `ci / image / build` success (74 s); `dependency-graph`, `image / publish` skipped |
| "Set up job", nhóm GITHUB_TOKEN Permissions | `check`: `Contents: read`. `image / build`: `Contents: read`, `SecurityEvents: write`; không có `Packages` dù `ci.yml` cấp `packages: write` |
| Trivy trên PR | Report Summary: Ubuntu 24.04 và 41 jar đều `0` |
| Build ở máy sau khi bỏ `ARG` | Được; image ở máy có `version=24.04` thừa hưởng từ base Ubuntu (ghi chú trong Dockerfile) |

### Bước 9c (2026-11-17)

`platform`: README (`4714554`), [release `v0.2.0`](https://github.com/hoangduoc0603/commerce-hub-platform/releases/tag/v0.2.0) tại `4714554242fedd3f829228dc9ee1913eacdaaf7f` (`immutable: true`), README ghim SHA (commit sau). `hello`: `ci.yml` ghim `java-service.yml@4714554…` (`64a0f14`), fast-forward `main`.

| Kiểm | Kết quả |
|---|---|
| Run `43916091267` (push `main`) | `check`, `dependency-graph`, `image / publish` success; `image / build` skipped. `publish` có `Packages: write` |
| Digest trong output job | `sha256:61df6f4c2b1411f65c4b11e1a8a0abfc4d087f2962548c47ba29a9877e250c7d` |
| `docker buildx imagetools inspect ghcr.io/hoangduoc0603/commerce-hub-hello:64a0f14…` (Mac đã `docker logout ghcr.io`) | Cùng digest; `application/vnd.oci.image.manifest.v1+json`, `amd64`. Package tự public |
| Bản push trùng bản đã quét | 12 layer trùng; Image ID và `config.digest` đều `sha256:1cb99f9b…ebf7` |
| `docker run --rm --platform linux/amd64 --entrypoint id …@sha256:61df6f4c…` | `uid=10001(app) gid=10001(app) groups=10001(app)` |
| Nhãn OCI | Đủ 7: `source`, `revision` và `version` (`64a0f14…`), `created` `2026-11-16T17:14:41Z`, `title`, `base.name`, `base.digest`; `User` `10001:10001` |
| Trivy | Cổng exit 0; Code scanning `trivy-image-commerce-hub-hello` trên `main`: 43 alert mở (39 MEDIUM, 4 LOW), 0 HIGH/CRITICAL |
| Dependency graph | `dependency-graph/sbom` của repo có 197 gói |

### Bước 10 (2026-11-17)

Số đo amd64 ở [2026-11-container-image-hello.md](../../../experiments/2026-11-container-image-hello.md), mục "amd64 trên CI". Build ấm: commit `29c0d5c` thêm một hằng số vào `HelloApplication`, `99e22ef` revert.

| Số đo | Kết quả |
|---|---|
| Layer đổi so với bản trước (manifest trên GHCR) | Cả hai lần: chỉ layer 11 (`application`) và 12 (`app.aot`); `dependencies`, loader, snapshot, layer user, `WORKDIR`, base giữ digest. Tiêu chí Q6 đạt |
| Kích thước amd64 | 138,1 MB nén (base 104,3 MB, `hello` 33,7 MB); 542 MB giải nén |
| Job `publish` lạnh / ấm / ấm | 99 s / 118 s / 105 s; push 5,8 s / 3,7 s / 2,6 s; training AOT 6,5 s / 4,8 s / 6,7 s |
| Job `check` lạnh / ấm | 65 s / 35 s (cache Gradle) |

Ở cỡ `hello`, cache gha không rút thời gian build bao nhiêu (builder, training, Trivy, ghi cache chiếm phần lớn); tác dụng chính là giữ digest của layer không đổi, nên chỉ phải đẩy khoảng 14 MB mỗi bản.

Sửa chuẩn: [container-image.md](../../../standards/container-image.md) (tick 21 mục, câu "build lại định kỳ" theo Q10, nhãn động Q8, quét trước push Q9), [ci-cd.md](../../../standards/ci-cd.md) (tick 12 mục, `java-service.yml` và gọi lồng, danh sách action Node).

Chuyển cho ticket sau:

- G0-24: ghi digest `image` của `java-service.yml` vào `gitops` (job `update-gitops`, GitHub App). AOT cache train trên CPU runner GitHub; kiểm `-Xlog:aot` trên node của lab (**chưa xác minh**).
- Mỗi push vào `main` ghi khoảng 55 MB cache gha (`buildkit-blob-*`) cho `hello`; hạn mức 10 GB của repo, entry 7 ngày không dùng bị xóa.

### Review (2026-11-17)

Skill `code-review` trên `platform` `c4b5d70..main` và `hello` `0bb4b87..main`: 8 điểm. Sửa 2 điểm, điểm thứ 3 đo xong thì không sửa; 5 điểm nhẹ để lại.

| # | Điểm | Xử lý |
|---|---|---|
| 1 | `ci.yml` và `ghcr-smoke.yml` để push vào `main` và lịch tuần chung nhóm `concurrency` theo ref. Một nhóm chỉ giữ một lần chạy đang chờ, lần mới hủy lần chờ (kể cả khi `cancel-in-progress: false`, [workflow syntax – concurrency](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#concurrency)), nên một commit có thể không bao giờ có image | **Sửa**: ngoài PR, nhóm theo `github.run_id` (mỗi lần chạy một nhóm). Loại `queue: max` (chạy tuần tự, chậm hơn, không cần) |
| 2 | Kiểm "bản push trùng bản đã quét" chạy sau khi đã push có tag: lệch thì tag SHA trỏ vào bản chưa quét, và bước "Kiểm tag chưa tồn tại" chặn mọi re-run | **Sửa** (`platform` `v0.2.1`): push theo digest (`push-by-digest=true`, không tag), kiểm, rồi mới gắn tag bằng `skopeo copy --preserve-digests` và kiểm tag trỏ đúng digest. Loại `docker buildx imagetools create`: thử trên `registry:2`, với một manifest nguồn nó tạo image index mới (digest `f7b7…` so với `9a35…`); `skopeo` giữ nguyên digest (`f7b4…` = `f7b4…`) và có sẵn trên runner (Skopeo 1.13.3) |
| 3 | DB Trivy tải lại mỗi lần chạy, không cache | **Không sửa** sau khi đo: DB tải từ `mirror.gcr.io` (không phải `ghcr.io`, Trivy tự lùi sang `ghcr.io` khi mirror lỗi), vuln DB 134 MiB khoảng 6 s, Java DB 954 MiB khoảng 18 s. Nén lại vẫn khoảng 1,1 GB mỗi bộ; cache theo ngày giữ tới 7 entry, khoảng 5 GB trong hạn mức 10 GB của repo, đẩy cache BuildKit (Q6) và Gradle ra. Đổi khoảng 20 s mỗi lần chạy lấy rủi ro đó không đáng |
| 4–8 | Hai job lặp bước; quét Trivy hai lần (dùng được `trivy convert`); cache `mode=max` ghi layer stage extract không dùng lại; `java-service.yml` ghim `container-image.yml` theo commit thay vì release; artifact jar giữ 1 ngày | Để lại, nhẹ |

Kiểm sau sửa:

- `platform` [PR #3](https://github.com/hoangduoc0603/commerce-hub-platform/pull/3) xanh. Run `ghcr-smoke` trên `main` (`92e2f4c`): `pushing manifest` không kèm tag, `Layer trùng nhau (1 layer)`, `skopeo` "Writing manifest to image destination", tag `92e2f4c…` trỏ `sha256:1d18f033…2880`, đúng digest của bước push.
- [Release `v0.2.1`](https://github.com/hoangduoc0603/commerce-hub-platform/releases/tag/v0.2.1) tại `152b52fc524f56f2a2898658728730da2b26b506` (`immutable: true`); `java-service.yml` gọi `container-image.yml@92e2f4c…`. `hello` ghim `v0.2.1` (`16efc28`): run `43920520833` xanh, `Layer trùng nhau (12 layer)`, tag `16efc28…` trỏ `sha256:5f13c9cc…e739`.
- Chưa thử được nhánh lỗi (layer lệch) trên CI: không có cách gây lệch thật mà không sửa workflow.
- Nhánh đã merge chưa xóa: `g0-23-review` của `platform` (local và remote), `g0-23-ci` của `hello` (local và remote).

### Dependabot alert đầu tiên (2026-11-17)

Job `dependency-graph` gửi graph lần đầu thì GitHub mở [alert #1](https://github.com/hoangduoc0603/commerce-hub-hello/security/dependabot/1): `org.apache.commons:commons-lang3` 3.16.0, CVE-2025-48924 (GHSA-j288-q9x7-2f5v, medium, vá ở 3.18.0). `./gradlew buildEnvironment` cho thấy gói chỉ ở classpath plugin (`spring-boot-gradle-plugin` 4.1.2 → `spring-boot-buildpack-platform` → `commons-compress` 1.27.1); `dependencyInsight` không thấy ở `runtimeClasspath`, `testRuntimeClasspath`; Trivy không thấy trong image. Chủ repo chọn dismiss với lý do `not_used`, kèm comment. Loại: ép 3.18.0 qua `buildscript` (lệch mặc định Initializr, phải nhớ gỡ).

## Bài học

- Review bắt được hai lỗi mà chạy xanh không lộ ra: kiểm sau khi đã gắn tag thì bản lỗi vẫn có tag và chặn re-run (sửa: push theo digest, kiểm, rồi mới tag); nhóm `concurrency` theo ref cho phép lần chạy sau hủy lần push đang chờ. Và `imagetools create` không gắn tag được mà giữ digest; thử trên `registry:2` mất hai phút, đỡ một lần đoán sai.
- Cổng chặn phải đứng **trước** push: build `load`, quét, rồi build lại với `push: true` cùng input. Lần thứ hai không chạy lại gì mà xuất lại đúng kết quả từ cache của builder; workflow tự chứng minh bằng cách so `diff_ids` (và config digest) của bản trên GHCR với bản đã quét.
- Chỗ vấp: tiêu chí "build ấm chỉ đẩy `application` và `app.aot`" không tự đạt trên CI. Runner mới mỗi lần, và `extract`, `groupadd` ghi mtime mới, nên không có cache BuildKit thì mọi layer đổi digest. Cache `type=gha` giải quyết, và nó giữ digest chứ gần như không giữ thời gian. Ngược lại, revert về đúng code cũ vẫn ra digest khác, nên tag = SHA cần lớp chặn ghi đè.
- Thử cổng chặn bằng một base cũ thật (alpine 3.10.0: 9 HIGH, 3 CRITICAL) trên PR là bằng chứng rẻ mà thuyết phục hơn đọc YAML.
- Câu chuyện kể được: "Image của service build đúng một lần trên runner amd64, quét Trivy trước khi push và chặn HIGH/CRITICAL đã có bản vá. Image được push theo digest, workflow kiểm nó trùng từng layer với bản đã quét rồi mới gắn tag SHA, nên bản lệch không bao giờ có tag. Tag là SHA, deploy theo digest, push bằng token ngắn hạn của job. Nhờ cache BuildKit trong GitHub Actions, sửa code chỉ đẩy lại 2 trong 12 layer, khoảng 14 MB."

