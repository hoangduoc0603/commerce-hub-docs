# Chuẩn: Build của một service Spring Boot

Artifact **mức đầy đủ** (CLAUDE.md, mục Chuẩn production): code service. File này chỉ nói phần **tạo project và build Gradle**. Phần chạy app nằm ở các chuẩn khác: Actuator, probe, shutdown ở [`zero-downtime.md`](zero-downtime.md); image ở [`container-image.md`](container-image.md); migration ở [`db-migration.md`](db-migration.md); quan sát ở [`observability.md`](observability.md).

- Ngày tra: 2026-11-15 (viết theo [ADR-0018](../adr/0018-self-contained-services-no-shared-library-yet.md), thay mục "Phía consumer" của [`java-library.md`](java-library.md))
- Phiên bản áp dụng: Spring Initializr (start.spring.io, metadata tra ngày 2026-11-15: bản mặc định Spring Boot 4.1.2), Spring Boot 4.1.2, plugin `io.spring.dependency-management` 1.1.7, Java 25 (Temurin), Gradle 9.8.2 (wrapper do Initializr sinh; docs Gradle hiện hành là 9.9.1), IntelliJ IDEA 2025.3.
- Phạm vi: `build.gradle`, `settings.gradle`, `gradle/wrapper/`, `.gitattributes`, `.gitignore`, `.github/dependabot.yml` của mọi service Spring Boot trong `services/` và `simulators/`, kể cả template `services/hello`.

## Checklist

### Tạo project
- [ ] Tạo bằng Spring Initializr: generator **Spring Boot** của IntelliJ (gọi start.spring.io), hoặc tải từ start.spring.io rồi **File → Open**. Chọn: Gradle - Groovy, Java, Spring Boot 4.1.x bản phát hành (không chọn `SNAPSHOT` hay `RC`), packaging Jar, **Java 25**. Initializr mặc định chọn Java 17, nên phải chọn 25 tường minh. Group `io.github.hoangduoc0603.commercehub`, artifact là tên service. Kiểm ngày 2026-11-15: metadata có `4.1.2` (mặc định), `4.2.0-RC2`, `4.1.3-SNAPSHOT`; Java có 27, 25, 21, 17 (mặc định 17). [Spring Initializr](https://start.spring.io), [IntelliJ – Spring Boot](https://www.jetbrains.com/help/idea/spring-boot.html)
- [ ] Chỉ chọn dependency mà ticket hiện tại cần, thêm dần sau. Ví dụ ticket G0-23 chỉ chọn Spring Web và Spring Boot Actuator. Thư viện thêm sau được khai tay trong `build.gradle`: mỗi lần thêm là một lần học nó làm gì.
- [ ] Gradle trong IntelliJ chạy bằng JDK 25: **Settings → Build, Execution, Deployment → Build Tools → Gradle → Gradle JVM**. Toolchain chỉ quyết định JDK để biên dịch và chạy test; Gradle JVM là JDK chạy chính Gradle.

### `build.gradle` giữ mặc định của Initializr
- [ ] Giữ nguyên khung Initializr sinh ra. Với Spring Web và Actuator, ngày 2026-11-15 khung đó gồm:
  - plugin `java`, `org.springframework.boot` (có version) và `io.spring.dependency-management` (có version);
  - `group`, `version`;
  - `java { toolchain { languageVersion = JavaLanguageVersion.of(25) } }`;
  - `repositories { mavenCentral() }`;
  - starter không ghi version;
  - `testRuntimeOnly 'org.junit.platform:junit-platform-launcher'`;
  - `tasks.named('test') { useJUnitPlatform() }`.

  Đã tải thật bằng `https://start.spring.io/build.gradle?type=gradle-build&bootVersion=4.1.2&javaVersion=25&dependencies=web,actuator`. Cách viết này giống mọi tutorial và docs Spring, nên đọc docs nào cũng khớp. [Spring Boot Gradle plugin – Managing dependencies](https://docs.spring.io/spring-boot/gradle-plugin/managing-dependencies.html)
- [ ] Spring Boot 4 đổi tên starter: "Spring Web" là `spring-boot-starter-webmvc`. Mỗi starter có test starter riêng (`spring-boot-starter-webmvc-test`, `spring-boot-starter-actuator-test`), không còn một `spring-boot-starter-test` chung. Thêm thư viện sau này thì tìm đúng tên starter của Boot 4.1, không chép tên từ tutorial Boot 3. [Spring Boot 4.1 – Build systems / starters](https://docs.spring.io/spring-boot/reference/using/build-systems.html)
- [ ] Version của phụ thuộc do BOM của Boot quản lý (plugin `io.spring.dependency-management` tự import BOM của đúng bản Boot đang dùng): **không ghi version** cho thư viện có trong BOM. Thư viện không có trong BOM thì ghi version đầy đủ, kèm comment vì sao cần. Muốn đổi version một thư viện có trong BOM thì dùng property (`ext['<lib>.version']`) và ghi lý do; docs cảnh báo mỗi bản Boot chỉ được test với đúng bộ version của nó. [Managing dependencies](https://docs.spring.io/spring-boot/gradle-plugin/managing-dependencies.html)
- [ ] Toolchain Java 25 khai trong `java { toolchain {} }`, không dùng `sourceCompatibility`; docs Gradle ghi cách sau "không bảo đảm dùng đúng JDK". Initializr không thêm plugin tự tải JDK (foojay). Máy dev và CI phải có sẵn JDK 25 (Mac: Temurin hoặc Oracle JDK 25; CI: `actions/setup-java` 25). [Gradle – Toolchains](https://docs.gradle.org/current/userguide/toolchains.html)
- [ ] Mọi chỗ sửa khỏi file Initializr sinh ra có comment ngay tại dòng đó: sửa gì, vì sao. Ví dụ: tắt task `jar` để chỉ còn fat jar (G0-23). (Sửa 2026-11-24, [ADR-0019](../adr/0019-no-contracts-repo.md): ví dụ cũ về repository GitHub Packages cho artifact `contracts` không còn, vì không còn package nào để đọc.)
- [ ] Không có thư viện dùng chung hay convention plugin ([ADR-0018](../adr/0018-self-contained-services-no-shared-library-yet.md)). Code chung (Problem Details, UUIDv7) chép từ template `hello` khi tạo service.

### Layout package
- [ ] Layout hexagonal là **quy ước**, không có test tự động ([ADR-0018](../adr/0018-self-contained-services-no-shared-library-yet.md)). Các package `domain`, `application`, `adapter.in.<kênh>`, `adapter.out.<đích>` nằm dưới package gốc của service. Chiều phụ thuộc theo [arc42 mục 5.2](../architecture/05-building-block-view.md#52-mức-2-bên-trong-một-service): `domain` không import Spring hay adapter, `application` không import adapter. Package ra đời cùng class đầu tiên của nó, không tạo trước package rỗng. Không bắt `package-info.java` (bỏ ngày 2026-11-16, chọn của chủ repo): luật phụ thuộc đã nằm ở arc42 5.2, chép thêm vào từng package là thêm một bản phải giữ cho khớp. Thêm `package-info.java` khi cần annotation cho cả package (ví dụ `@NullMarked` của JSpecify).

### Wrapper Gradle
- [ ] Giữ version Gradle mà Initializr sinh (9.8.2 lúc tra). Thêm `distributionSha256Sum` bằng `./gradlew wrapper --gradle-version <version> --gradle-distribution-sha256-sum <sha>`, lấy sha từ file `https://services.gradle.org/distributions/gradle-<version>-bin.zip.sha256`. Initializr không ghi checksum. Thiếu dòng này thì không có gì kiểm bản Gradle tải về; khi có, sai checksum là build dừng (Gradle chỉ kiểm lúc tải bản phân phối lần đầu). [Gradle – Wrapper: verifying the download](https://docs.gradle.org/current/userguide/gradle_wrapper.html)
- [ ] Kiểm SHA-256 của `gradle/wrapper/gradle-wrapper.jar` với `https://services.gradle.org/distributions/gradle-<version>-wrapper.jar.sha256` trước commit đầu. Jar wrapper là file nhị phân sẽ chạy trên máy mọi người và trên CI. Từ v4, `gradle/actions/setup-gradle` cũng tự kiểm jar này trên CI. [Gradle – Wrapper](https://docs.gradle.org/current/userguide/gradle_wrapper.html)
- [ ] Giữ `.gitattributes` của Initializr (`gradlew` LF, `*.bat` CRLF, `*.jar` nhị phân).

### Repo và cập nhật phụ thuộc
- [ ] Repo tạo và cấu hình bằng `platform/scripts/github/repo-bootstrap.sh <tên> --local . --ecosystems gradle,docker`, kiểm bằng `repo-audit.sh` trước lần push đầu ([`ci-cd.md`](ci-cd.md), [`platform/scripts/github/README.md`](../../platform/scripts/github/README.md)).
- [ ] `.gitignore` bỏ cả thư mục `.idea/`. Template được chép sang mọi service, và IntelliJ dựng lại `.idea` từ Gradle.
- [ ] Dependabot ecosystem `gradle`. Dependabot đọc `build.gradle` và nâng version ghi thẳng trong khối `plugins {}` (`org.springframework.boot`, `io.spring.dependency-management`). Thư viện không ghi version thì không được nâng riêng; chúng đi theo BOM khi Boot plugin lên bản mới. Dependabot cũng cập nhật wrapper (`gradle-wrapper.properties`, `gradlew`, jar). [Supported ecosystems – Gradle](https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories#gradle). Phần `plugins {}` là đọc mã nguồn `dependabot-core` (`gradle/lib/dependabot/gradle/file_parser.rb`, nhánh `main`), docs GitHub không ghi.

## Lựa chọn và phương án đã loại

| Quyết định | Chọn | Loại | Lý do | Nguồn |
|---|---|---|---|---|
| Khung build của service | Project Spring Initializr, giữ mặc định | Convention plugin `commercehub.spring-service` của `service-kit` | Chủ repo học bằng cách tự cấu hình; một service chưa cần lớp trừu tượng dùng chung | [ADR-0018](../adr/0018-self-contained-services-no-shared-library-yet.md) |
| BOM của Boot | Plugin `io.spring.dependency-management` (mặc định Initializr) | `platform(SpringBootPlugin.BOM_COORDINATES)` | Docs Boot không khuyên bên nào; plugin cho đổi version bằng property, `platform()` có thể build nhanh hơn. Chọn mặc định để khớp docs và tutorial | [Managing dependencies](https://docs.spring.io/spring-boot/gradle-plugin/managing-dependencies.html) |
| Repository | `mavenCentral()` trong `build.gradle` (mặc định) | Khai ở `settings.gradle` với `FAIL_ON_PROJECT_REPOS` | Project một module, repository nằm cùng chỗ với phụ thuộc là dễ đọc nhất. Chặn repository lạ có giá trị khi có nhiều module hay plugin nội bộ | [Gradle – Centralizing repositories](https://docs.gradle.org/current/userguide/centralizing_repositories.html) |
| Kiểm layout hexagonal | Quy ước, review | ArchUnit trong `check` | Chọn của chủ repo, giữ ít thư viện; thêm lại khi review không đủ | [ADR-0018](../adr/0018-self-contained-services-no-shared-library-yet.md) |
| DSL | Groovy | Kotlin DSL | Spec G0 chốt Groovy | [spec G0](../.scratch/g0-platform/spec.md) |

## Bằng chứng cần có

Ghi ở mục `## Kết quả` của ticket tạo service (với `hello` là ticket G0-23):

| Số đo | Lệnh | Tiêu chí |
|---|---|---|
| Build và test của khung | `./gradlew build` | Xanh, có test `contextLoads` của Initializr |
| Checksum bản phân phối | `grep distributionSha256Sum gradle/wrapper/gradle-wrapper.properties` | Khớp file `.sha256` trên `services.gradle.org` |
| Checksum jar wrapper | `shasum -a 256 gradle/wrapper/gradle-wrapper.jar` | Khớp file `-wrapper.jar.sha256` |
| JDK biên dịch | `javap -v build/classes/java/main/<đường dẫn>/HelloApplication.class \| grep major` | `major version: 69` (Java 25) |
| Repo đạt chuẩn | `repo-audit.sh <tên> --local . --ecosystems gradle,docker` | Tất cả PASS |

## Nguồn

- [Spring Initializr](https://start.spring.io) (API `build.gradle` và `starter.zip`, metadata `application/vnd.initializr.v2.2+json`, tra 2026-11-15)
- Spring Boot 4.1.2: [Gradle plugin – Managing dependencies](https://docs.spring.io/spring-boot/gradle-plugin/managing-dependencies.html), [Build systems – starters](https://docs.spring.io/spring-boot/reference/using/build-systems.html)
- Gradle: [Wrapper](https://docs.gradle.org/current/userguide/gradle_wrapper.html), [Toolchains](https://docs.gradle.org/current/userguide/toolchains.html), [Centralizing repositories](https://docs.gradle.org/current/userguide/centralizing_repositories.html)
- GitHub: [Dependabot supported ecosystems – Gradle](https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories#gradle), [dependabot-core `file_parser.rb`](https://github.com/dependabot/dependabot-core/blob/main/gradle/lib/dependabot/gradle/file_parser.rb)
- JetBrains: [IntelliJ IDEA – Gradle](https://www.jetbrains.com/help/idea/gradle.html), [Spring Boot](https://www.jetbrains.com/help/idea/spring-boot.html)
