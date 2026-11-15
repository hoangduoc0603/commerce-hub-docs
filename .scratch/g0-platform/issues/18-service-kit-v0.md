# 18: `service-kit` v0.1: convention plugin, ArchUnit, publish từ tag

Status: resolved
Blocked by: 01
Repos: libs/service-kit, platform, docs
Spec: [G0](../spec.md)

## Mô tả

Repo `libs/service-kit` nhiều module, một version, với hai module đầu: `gradle-plugin` (convention `commercehub.spring-service`: ghim Java 25, minor Spring Boot 4.1, repository, bật ArchUnit) và `test-support` (luật ArchUnit cho layout hexagonal, cấu hình Testcontainers, bảng tag image). Reusable workflow `java-library` trong `platform` build, test và publish lên GitHub Packages chỉ từ tag `vX.Y.Z`. Theo ticket 11 của map và [ci-cd.md](../../../standards/ci-cd.md).

## Mục tiêu học

- Convention plugin của Gradle (precompiled script plugin) để gom cấu hình build.
- Publish artifact bất biến theo SemVer.

## Tiêu chí nghiệm thu

- [x] Tag `v0.1.0` tạo package trên GitHub Packages; push lại cùng tag bị từ chối.
- [x] Một project Gradle thử áp plugin, tải được artifact bằng PAT `read:packages` trên Mac.
- [x] Luật ArchUnit tự kiểm: một package cố ý vi phạm (`domain` import Spring) làm test đỏ.
- [x] Composite build `--include-build` từ project thử chạy được, không dùng SNAPSHOT.
- [x] Workflow ghim SHA, có `timeout-minutes`, cache Gradle chỉ ghi trên nhánh mặc định; Dependabot có ecosystem `gradle`.

## Quyết định khi lập lộ trình (2026-11-15)

- Q1. Project thử ở `services/kit-try/`, không `git init`, xóa khi xong ticket. Đường `--include-build ../../libs/service-kit` giống hệt đường `hello` sẽ dùng.
- Q2. Version lấy từ tag: CI truyền `-PreleaseVersion=${GITHUB_REF_NAME#v}`, build local mặc định `0.0.0-local`, task publish từ chối version đó. Tag là nguồn sự thật duy nhất. (Bước 7 đổi tên tham số thành `-Pversion`, xem mục dưới.)
- Q3. Chuẩn ghi ở file mới `docs/standards/java-library.md` (artifact mức đầy đủ); ticket 20 dùng lại.
- Q4. Plugin thêm `test-support` vào `testImplementation`; service có một class test `@AnalyzeClasses` + `@ArchTest ArchTests.in(...)`, theo cách ArchUnit hướng dẫn cho JUnit 5.
- Q5. Bất biến ở hai lớp: ruleset tag `v*` cấm cập nhật và xóa; GitHub Packages từ chối publish lại version đã có (đã xác minh ở bước 10: `409 Conflict`).

## Quyết định trong lúc làm (2026-11-15)

- Bước 3: luật onion dùng một adapter chung `..adapter..`, thêm luật slices cấm adapter gọi nhau; class ngoài ba lớp không được gọi vào lớp nào; mọi luật cho phép rỗng. Chi tiết ở [java-library.md](../../../standards/java-library.md), mục "Luật kiến trúc".
- Bước 5, **lệch mô tả ticket**: convention plugin không ghim repository. Gradle Best Practices đặt repository trong `settings.gradle` với `FAIL_ON_PROJECT_REPOS`, và plugin khai repository thì service không áp được plugin (đã thử). Repository nằm trong `settings.gradle` của service, có `exclusiveContent` cho GitHub Packages. TestKit ở source set `test`; bytecode plugin Java 25.
- Bước 6: plugin biết version của mình qua `commercehub-kit.properties` do `WriteProperties` ghi vào jar; `gradle.properties` có `version=0.0.0-local`; `test-support` có publication cơ bản (kéo một phần bước 7 lên) để TestKit tải từ `build/testkit-repo` qua `exclusiveContent`.
- Bước 7, **đổi Q2**: CI truyền `-Pversion=X.Y.Z` (đè `version=0.0.0-local` trong `gradle.properties`) thay cho `-PreleaseVersion`, không cần code đọc property; ý của Q2 giữ nguyên. Cấu hình publish chung ở included build `build-logic` (plugin `commercehub.kit-publishing`). Kiểm bằng repository thư mục `build/testkit-repo` thay cho `publishToMavenLocal`.
- Bước 8: `--include-build` thay được cả plugin lẫn `test-support`, không cần phương án `kitPath`. Composite build vẫn đòi credentials `githubPackages` (Gradle kiểm trước khi resolve); chủ repo chọn tạo PAT classic `read:packages` ngay và đặt ở `~/.gradle/gradle.properties`. Lần kiểm đầu dùng giá trị giả `-P...` vì PAT chưa có.
- Bước 9: `java-library.yml` có ba job (`check`, `dependency-graph` chỉ push `main`, `publish` chỉ tag `v*`). `ci.yml` ghim `platform` theo SHA commit trên `main` (`ef85dac`) vì `platform` chưa có release (ticket 17). `setup-java` v6.2.0 thay vì v6.3.0 (mới ra 1 ngày, chưa qua cooldown). Lần chạy đầu hai job tranh nhau ghi cùng key cache Gradle (`check` bị từ chối "Unable to reserve cache"); sửa: `dependency-graph` `needs: check` và `cache-read-only: true`.
- Bước 10: ruleset khóa tag tạo bằng cờ mới `--release-tags` của `repo-bootstrap.sh`/`repo-audit.sh` (platform `8127401`), để `contracts` (ticket 20) dùng lại. Tag `v0.1.0` có chú thích, trỏ `6e7d399`. GitHub Packages nhận cả marker plugin (artifactId có dấu chấm); ba package public, gắn repo `commerce-hub-service-kit`. Thử dời và xóa tag trên GitHub bị hệ thống quyền của Claude chặn (`git push --force` lên tag); chủ repo tự chạy, cả hai bị ruleset từ chối.

## Lộ trình

- [x] 1. (Claude viết) `docs/standards/java-library.md` và thêm `java-library.yml` vào `ci-cd.md`. Kiểm: chủ repo duyệt.
- [x] 2. Khung repo `libs/service-kit`: `git init`, `repo-bootstrap.sh service-kit --ecosystems gradle`, wrapper 9.9.1, `settings.gradle` hai module, `gradle/libs.versions.toml`. Kiểm: `./gradlew projects` có `:gradle-plugin`, `:test-support`; `repo-audit.sh` PASS.
- [x] 3. `test-support`: luật ArchUnit hexagonal, test trước, fixture một package đúng, một package rỗng và bốn package vi phạm. Kiểm: `./gradlew :test-support:test` xanh (10 test); gõ sai mẫu package trong luật thì đỏ.
- [x] 4. `test-support`: bảng tag image và cấu hình Testcontainers `@ServiceConnection`. Kiểm: test PostgreSQL trả `server_version` khớp tag trong bảng (18.7).
- [x] 5. `gradle-plugin`: precompiled script plugin ghim Java 25, Spring Boot 4.1.x, BOM, JUnit Platform (repository để ở `settings.gradle` của service); test bằng TestKit. Kiểm: `./gradlew :gradle-plugin:test` xanh (3 test); thêm repository vào plugin thì đỏ.
- [x] 6. Plugin bật ArchUnit: thêm `test-support` cùng version plugin. Kiểm: TestKit, project vi phạm làm `check` đỏ (6 test plugin xanh; `test-support` publish vào `build/testkit-repo` cho TestKit).
- [x] 7. Publish: `maven-publish`, version từ tag, sources/javadoc, POM đủ metadata. Kiểm: `./gradlew publishAllPublicationsToTestKitRepository` có marker và đủ artifact của hai module (11 file); `publish` với version local bị chặn.
- [x] 8. Project thử `services/kit-try/` với composite build. Kiểm: `./gradlew check --include-build ../../libs/service-kit` xanh, thêm vi phạm thì đỏ (`DOMAIN_INDEPENDENT_OF_SPRING FAILED`), `test-support` thay bằng project, 0 SNAPSHOT. Chạy lại không có `-P...` sau khi PAT classic `read:packages` đã ở `~/.gradle/gradle.properties` (quyền 600): xanh.
- [x] 9. Reusable `java-library.yml` trong `platform` và `ci.yml` mỏng trong `service-kit`. Kiểm: CI xanh trên main; grep ghim SHA 0 dòng. Kết quả: run 43727443461 (lạnh) và 43727733986 (ấm) xanh, `publish` skipped; job `check` 93 s lạnh, 76 s ấm (Gradle 1m18s → 1m5s); dependency graph có 123 package; grep ghim SHA 0 dòng ở cả `platform` và `service-kit`.
- [x] 10. Release `v0.1.0`: ruleset tag `v*`, push tag, chạy lại publish. Kiểm: package có trên GitHub; publish lại bị từ chối; dời tag bị chặn. Kết quả: `repo-audit.sh service-kit --release-tags` Tất cả PASS; run 43728359529 lần 1 xanh (publish 71 s), ba package `0.1.0`; lần 2 (chạy lại `publish`) đỏ với `409 Conflict`; chủ repo thử dời tag (`GH013 … Cannot update this protected ref`) và xóa tag (`GH013 … Cannot delete this tag`), cả hai bị từ chối, tag vẫn trỏ `6e7d399`.
- [x] 11. Project thử tải từ GitHub Packages bằng PAT `read:packages`; kết ticket. Kiểm: `./gradlew check --refresh-dependencies` tải được `0.1.0`. Kết quả: `kit-try` tải marker POM, pom/module/jar của `gradle-plugin` và `test-support` `0.1.0` từ `maven.pkg.github.com`, xanh 22 s; thêm import Spring vào `domain` thì `DOMAIN_INDEPENDENT_OF_SPRING FAILED`. `service-kit` `clean check --rerun-tasks` 17 test xanh. `kit-try` xóa sau khi đo (Q1).

## Kết quả

- Bằng chứng: [bản ghi G0, mục 8](../../../experiments/2026-11-g0.md#8-service-kit-010-convention-plugin-luật-kiến-trúc-publish-bất-biến-từ-tag).
- `libs/service-kit` (`commerce-hub-service-kit`) từ `06ee97e` tới `6e7d399`, tag `v0.1.0`: module `test-support` (luật hexagonal, Testcontainers PostgreSQL 18.7, bảng tag image), module `gradle-plugin` (convention plugin `commercehub.spring-service`), included build `build-logic` (plugin publish nội bộ), `ci.yml`.
- `platform` từ `5f9e1ce` tới `8127401`: reusable workflow `java-library.yml`, README mục "Reusable workflow", cờ `--release-tags` cho `repo-bootstrap.sh` và `repo-audit.sh`.
- GitHub Packages: `gradle-plugin`, `test-support` và marker `commercehub.spring-service` version `0.1.0`, public.
- `v0.1.1` (tag trên `77094ce`, run 43730338109): mang sửa 2–3 của review. Bước kiểm mới của job `publish` chạy thật lần đầu: `Commit 77094ce… nằm trên main (identical)`; `check` 79 s, `publish` 69 s; ba package có `0.1.1` và `0.1.0`. Template `hello` (ticket 23) bắt đầu từ `0.1.1`.
- Chuẩn: [java-library.md](../../../standards/java-library.md) hết điểm "chưa xác minh" của ticket này (marker, 409, `--include-build`, version qua resource, JUnit 6.1.3); còn một điểm thuộc ticket `hello` (Dependabot tự truy cập GitHub Packages).
- Ma trận truy vết: không có dòng cho ticket nền tảng G0 (bảng theo mã F và NFR), nên không sửa. Luật hexagonal là công cụ giữ N13 ("thêm sàn mới không sửa lõi") từ G1.

## Review

`code-review` (mức high) trên toàn bộ `service-kit` và phần thay đổi của `platform`, 7 phát hiện. Chủ repo chọn sửa 1–3 (đã sửa, xem dưới); 4–7 để lại:

1. **Đã sửa** (platform `f836c28`, `service-kit` ghim lại ở `77094ce`): `java-library.yml`: `publish` chạy với mọi tag `v*`, không kiểm commit của tag nằm trên `main`. Thêm bước gọi API compare, chỉ đi tiếp khi `identical` hoặc `behind`; đã thử `identical` (6e7d399), `behind` (06ee97e) và `diverged` (nhánh chưa merge của `actions/checkout`, thoát 1).
2. **Đã sửa** (`service-kit` `0e17254`): `commercehub.kit-publishing.gradle`: `pom.description` đọc `project.description` lúc tạo publication, phụ thuộc thứ tự dòng trong module. Đã tái hiện (POM mất `<description>`), sửa bằng `providers.provider`, configuration cache vẫn lưu và dùng lại.
3. **Đã sửa** (`service-kit` `0e17254`): `commercehub.spring-service.gradle`: không kiểm `null` khi đọc `commercehub-kit.properties`. Đã tái hiện (NPE), giờ ném `GradleException` nêu tên file và task. Hai sửa 2–3 có hiệu lực cho service từ bản phát hành sau `0.1.0`.
4. `HexagonalRules.ADAPTERS_INDEPENDENT`: cấm `adapter.in.kafka` và `adapter.out.kafka` dùng chung code (serde, cấu hình Avro).
5. `gradle-plugin/build.gradle`: test phụ thuộc publish đầy đủ (sources, javadoc) của `test-support`.
6. `ServiceProject`: chèn đường dẫn repo vào chuỗi Groovy không escape.
7. `ci.yml`: quyền ghi cấp cho cả lần chạy `pull_request`, an toàn dựa vào từng job tự hạ quyền.

## Bài học

- Convention plugin và repository là hai việc tách nhau: Gradle Best Practices đặt repository ở `settings.gradle` với `FAIL_ON_PROJECT_REPOS`, và một plugin khai repository làm chính service đó không áp được plugin. Test TestKit dựng service tạm có `FAIL_ON_PROJECT_REPOS` biến quyết định này thành test hồi quy.
- Luật kiến trúc cũng cần test của chính nó: ArchUnit mặc định đánh trượt luật rỗng, nhưng template rỗng buộc phải cho phép rỗng; khi đó chỉ có fixture vi phạm (kèm kiểm tên class trong thông báo) mới bắt được luật gõ sai package. Đọc mã nguồn `onionArchitecture()` mới thấy nó xét mọi phụ thuộc, kể cả class ngoài ba lớp.
- Hai chỗ "chưa xác minh" lớn nhất (marker có dấu chấm, publish lại) chỉ trả lời được bằng lần phát hành thật; chuẩn ghi sẵn phương án dự phòng nên không phải chặn ticket để chờ. Lần chạy CI đầu cũng lộ một lỗi không đọc docs nào thấy: hai job tranh nhau một key cache.
- Câu chuyện kể được: "Tôi làm thư viện nội bộ cho mọi service: một convention plugin và luật ArchUnit cho layout hexagonal, publish lên GitHub Packages chỉ từ tag. Version bất biến ở hai lớp: ruleset khóa tag (dời hay xóa đều bị GH013) và registry trả 409 khi publish lại. Service chỉ cần một dòng `plugins` và một class test; `domain` import Spring thì `./gradlew check` đỏ, và composite build cho sửa kit với service cùng lúc mà không dùng SNAPSHOT."

