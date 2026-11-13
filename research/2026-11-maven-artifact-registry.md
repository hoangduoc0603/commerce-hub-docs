# Nơi publish artifact JVM (Maven) và npm cho polyrepo

Tra cứu ngày 13/11/2026. Mọi nguồn dưới đây được đọc vào ngày này, trừ khi ghi khác.

Bối cảnh: dự án học, một người làm, polyrepo, mọi repo **public** trên một tài khoản GitHub cá nhân (gói Free). CI chạy trên GitHub-hosted runner, vào home lab qua Tailscale (`tailscale/github-action`, ephemeral node). Lab đã có docker-registry 2.8 HTTP thường ở `10.20.0.5:5000` trên host `gw`, cùng host chạy RustFS (S3-compatible). Build bằng Gradle 9.x, Java 25. Cần publish:

- artifact JVM có version: thư viện dùng chung (`libs/*`), code sinh từ Avro/OpenAPI (repo `contracts`), có thể thêm Gradle convention plugin và BOM/version catalog;
- package npm sinh từ `contracts`, cho frontend Next.js dùng.

Bên tiêu thụ: CI của repo khác (GitHub-hosted runner), Dockerfile build (jar đã build bằng Gradle trước đó nên bản thân `docker build` không cần resolve dependency), MacBook của developer.

Ghi chép này chỉ gom dữ kiện, **không đề xuất**. Quyết định để một phiên khác.

Nhãn: **[CT]** tài liệu hoặc mã nguồn chính thức · **[CXM]** chưa xác minh · **[SL]** suy luận của người viết, chưa có nguồn nói thẳng.

## Tóm tắt

- **GitHub Packages** (Maven và npm) **luôn cần token để tải, kể cả package public**. Chỉ Container registry cho tải ẩn danh. Token phải là PAT (classic) hoặc `GITHUB_TOKEN`; fine-grained PAT không được hỗ trợ.
- Maven ở GitHub Packages chỉ có quyền theo repo (repository-scoped): package luôn gắn với repo và thừa hưởng quyền của repo. npm có quyền chi tiết (granular): muốn `GITHUB_TOKEN` của repo B đọc package npm do repo A publish thì vào trang package, mục "Manage Actions access", **Add repository** B.
- **Maven Central** (Central Portal): tài khoản đăng nhập bằng GitHub được cấp sẵn namespace `io.github.<username>`. Bắt buộc ký PGP từng file, có `-sources.jar` và `-javadoc.jar`, POM đủ metadata. Bản release **không xóa, không sửa được**. Có SNAPSHOT (bật theo namespace, tự dọn sau 90 ngày). Sonatype không có plugin Gradle chính thức. Từ 2026 có hạn mức publish mỗi tháng theo tổ chức.
- **Reposilite** 3.6.7 (09/11/2026): chỉ Maven, **không có npm** (issue "Support NPM" vẫn mở). Heap khuyến nghị 32 MB cho "personal projects + CI + Proxy". Có mirror (proxy) và backend S3.
- **Nexus Repository CE**: có Maven và npm, nhưng tài liệu ghi host tối thiểu **8 GB RAM**, heap tối thiểu 2703 MB. Vượt xa khoảng 1 GiB RAM còn trống ở lab.
- Mọi phương án đặt trong lab đều bắt mọi consumer (CI, MacBook) phải vào tailnet mới resolve được dependency. Gradle còn bắt opt-in `allowInsecureProtocol` nếu repo dùng HTTP thường.

---

## 1. GitHub Packages

### 1.1 Tải ẩn danh package public

- Maven, Gradle và npm đều ghi giống nhau: "You need an access token to publish, install, and delete private, internal, and public packages." [CT] ([Maven](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-apache-maven-registry), [Gradle](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-gradle-registry), [npm](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-npm-registry))
- Trang quyền nói rõ: ở hầu hết registry, muốn pull phải xác thực bằng PAT hoặc `GITHUB_TOKEN` "regardless of whether the package is public or private". Ngoại lệ duy nhất là Container registry, nơi package public tải ẩn danh được [CT] ([About permissions for GitHub Packages](https://docs.github.com/en/packages/learn-github-packages/about-permissions-for-github-packages)).
- Loại token: "GitHub Packages only supports authentication using a personal access token (classic)." Muốn tải thì cần scope `read:packages` [CT] (cùng nguồn).
- Hệ quả [SL]: MacBook cần một PAT classic `read:packages` đặt trong `~/.gradle/gradle.properties` và `~/.npmrc`. Ai clone repo public về build cũng phải tự tạo PAT.

### 1.2 `GITHUB_TOKEN` đọc package của repo khác cùng tài khoản

**Maven/Gradle (repository-scoped):**

- Maven và Gradle nằm trong danh sách registry "**only** support repository-scoped permissions". Package "inherits the permissions and visibility of the repository in which the package is published" [CT] ([About permissions](https://docs.github.com/en/packages/learn-github-packages/about-permissions-for-github-packages#permissions-for-repository-scoped-packages)).
- Trang Gradle: dùng `GITHUB_TOKEN` để publish package của repo đang chạy workflow. Còn để cài package "associated with other private repositories" thì dùng PAT classic `read:packages`, "(`GITHUB_TOKEN` can be used if the repository is granted read access to the package ...)" [CT] ([Gradle registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-gradle-registry)).
- Trang quyền: dùng PAT classic để "install packages associated with other private repositories that `GITHUB_TOKEN` can't access" [CT] ([About permissions](https://docs.github.com/en/packages/learn-github-packages/about-permissions-for-github-packages)).
- Trang hướng dẫn Actions nói với registry repository-scoped: "The token's permissions are limited to the repository that contains your workflow." [CT] ([Publishing and installing a package with GitHub Actions](https://docs.github.com/en/packages/managing-github-packages-using-github-actions-workflows/publishing-and-installing-a-package-with-github-actions)).
- **[CXM]** `GITHUB_TOKEN` của repo B có tải được package Maven của repo A (public) hay không: tài liệu không nói thẳng. Câu "other *private* repositories" gợi ý repo public thì đọc được, nhưng câu "limited to the repository that contains your workflow" lại gợi ý ngược lại. Ở registry repository-scoped không có nút "Manage Actions access" để cấp quyền thêm, vì quyền đi theo repo. Phải thử bằng một workflow thật mới chắc được.
- URL: mỗi repo một URL `https://maven.pkg.github.com/OWNER/REPOSITORY`. Trang Maven còn ghi có thể dùng `https://maven.pkg.github.com/OWNER/*` để cài package "from any repository for a specified repository owner". Owner phải viết chữ thường [CT] ([Maven registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-apache-maven-registry), [Gradle registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-gradle-registry)). Trang Gradle chỉ có ví dụ URL theo từng repo. **[CXM]** URL `OWNER/*` dùng với Gradle có chạy không.
- Workflow publish cần `permissions: contents: read, packages: write` [CT] ([Publishing and installing ...](https://docs.github.com/en/packages/managing-github-packages-using-github-actions-workflows/publishing-and-installing-a-package-with-github-actions)). Workflow chỉ đọc thì cần `packages: read` [SL].

**npm (granular):**

- npm "supports granular permissions". Package npm phải có scope (`@NAMESPACE/PACKAGE-NAME`), với `.npmrc` dạng `@NAMESPACE:registry=https://npm.pkg.github.com` [CT] ([npm registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-npm-registry)).
- Package gắn với repo trước khi publish thì tự thừa hưởng quyền truy cập của repo, và workflow trong repo đó tự có quyền. Với workflow ở repo khác: "you must give explicit access to the repository where the workflow is stored". Với package thuộc tài khoản cá nhân, vào package settings, mục "Manage Actions access", **Add repository** [CT] ([Configuring a package's access control and visibility](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility#ensuring-workflow-access-to-your-package)).
- Đặt package thành public thì không đổi về private được nữa [CT] (cùng nguồn).

### 1.3 Gradle convention plugin (plugin marker)

- Theo Gradle, khối `plugins {}` tìm Plugin Marker Artifact có toạ độ `plugin.id:plugin.id.gradle.plugin:plugin.version`. Marker này phụ thuộc vào artifact chứa plugin. `java-gradle-plugin` tự sinh publication cho marker khi đi kèm `maven-publish`. Repo Maven tự dựng (custom) "must contain plugin marker artifacts and the artifacts that implement the plugin". Consumer khai báo repo trong `pluginManagement { repositories { ... } }` [CT] ([Gradle 9.9.1, Using Plugins: Plugin Marker Artifacts](https://docs.gradle.org/current/userguide/plugins_intermediate.html#sec:plugin_markers), [Gradle Plugin Development Plugin](https://docs.gradle.org/current/userguide/java_gradle_plugin.html)).
- Tài liệu GitHub Packages không nói gì về Gradle plugin hay plugin marker [CT, vắng mặt] ([Gradle registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-gradle-registry)).
- [SL] Về lý thuyết thì publish được, vì marker chỉ là một artifact Maven bình thường (packaging `pom`). Mỗi marker sẽ hiện thành một package riêng trong repo. **[CXM]** chưa có tài liệu GitHub xác nhận, cần thử.
- Gradle Plugin Portal là chỗ khác để publish plugin: plugin mới phải qua duyệt tay. Ví dụ plugin ID hợp lệ là `io.github.johndoe.myplugin`, còn `com.github` không được chấp nhận nữa. Portal từ chối bản SNAPSHOT [CT] ([Gradle Plugin Portal: How do I add my plugin](https://plugins.gradle.org/docs/publish-plugin)).

### 1.4 Chi phí và xóa

- "GitHub Packages usage is free for public packages." Dữ liệu tải từ GitHub Actions dùng `GITHUB_TOKEN` không tính vào hạn mức của repo [CT] ([GitHub Packages billing](https://docs.github.com/en/billing/concepts/product-billing/github-packages)).
- Không xóa được package public nếu có version nào vượt 5.000 lượt tải. Khi đó phải liên hệ GitHub Support [CT] ([Deleting and restoring a package](https://docs.github.com/en/packages/learn-github-packages/deleting-and-restoring-a-package)).

---

## 2. Maven Central (Central Publisher Portal)

### 2.1 Namespace

- Đăng ký bằng GitHub thì "you will automatically receive a verified namespace in the form `io.github.<github username>`". Chỉ áp dụng cho chính username dùng để đăng ký, không áp dụng cho organization [CT] ([Register a Namespace](https://central.sonatype.org/register/namespace/)).
- Namespace theo domain (ví dụ `com.example`) xác minh bằng bản ghi DNS TXT chứa Verification Key. Thường mất vài phút; quá vài giờ thì email Central Support [CT] (cùng nguồn).

### 2.2 Yêu cầu khi publish

Theo [Requirements](https://central.sonatype.org/publish/requirements/) [CT]:

- Có `groupId`, `artifactId`, `version`, và version không được kết thúc bằng `-SNAPSHOT` (đó là luồng riêng, xem 2.4).
- Mỗi jar chính phải kèm `-sources.jar` và `-javadoc.jar`. Packaging `pom` (BOM, plugin marker) được miễn. Không có nội dung thật thì nộp jar giữ chỗ cũng được.
- Mỗi file phải có checksum `.md5` và `.sha1`; `.sha256`/`.sha512` tùy chọn.
- Mỗi file phải có chữ ký `.asc` (GPG/PGP).
- POM phải có `name`, `description`, `url`, `license`, `developer`, `scm` (`connection`, `developerConnection`, `url`).

Ký số [CT] ([GPG](https://central.sonatype.org/publish/requirements/gpg/)): public key phải nằm trên một keyserver mà Central đọc: `keyserver.ubuntu.com`, `keys.openpgp.org` hoặc `pgp.mit.edu`. Key tạo bằng `gpg --gen-key` mặc định hết hạn sau 2 năm; gia hạn được, sau đó đẩy lại public key lên keyserver. Phía Gradle, plugin `signing` có `useInMemoryPgpKeys(signingKey, signingPassword)` đọc key dạng ascii-armored từ `ORG_GRADLE_PROJECT_signingKey`/`ORG_GRADLE_PROJECT_signingPassword`, hợp với secret của CI [CT] ([Gradle 9.9.1 Signing Plugin](https://docs.gradle.org/current/userguide/signing_plugin.html)).

Gradle: "Currently, there is no official Gradle plugin for publishing to Maven Central via the Central Publishing Portal." Trang này liệt kê plugin cộng đồng (JReleaser, `GradleUp/nmcp`, `vanniktech/gradle-maven-publish-plugin`...), Sonatype không hỗ trợ các plugin đó. Ai đang dùng plugin cũ từ thời OSSRH thì dùng Portal OSSRH Staging API [CT] ([Publishing By Using Gradle](https://central.sonatype.org/publish/publish-portal-gradle/)).

### 2.3 Bao lâu thì dùng được

- Upload xong, Portal kiểm tra bản deployment, "should not take more than a few minutes". Sau đó bấm **Publish** (hoặc để tự publish) để đồng bộ lên Maven Central. Trạng thái: `VALIDATED`, `PUBLISHING`, `PUBLISHED`, `FAILED`. Trước khi publish có thể **Drop** bản deployment [CT] ([Publisher Portal Guide](https://central.sonatype.org/publish/publish-portal-guide/)).
- Tài liệu không ghi thời gian cố định từ lúc publish tới lúc tải được từ `repo1.maven.org`. Trang Support bảo mở ticket nếu bản release vẫn chưa có trên central.sonatype.com "after 4 hours of being released" [CT] ([Support](https://central.sonatype.org/pages/support/)). **[CXM]** con số thực tế (cộng đồng hay nói khoảng 10–30 phút, chưa có nguồn chính thức).

### 2.4 SNAPSHOT

- Có. Bật theo từng namespace ("Enable SNAPSHOTs" trên trang Namespaces). URL `https://central.sonatype.com/repository/maven-snapshots/`. Không kiểm tra hợp lệ, được ghi đè, "cleaned up after a period of time (currently 90 days)" [CT] ([Publish Portal Snapshots](https://central.sonatype.org/publish/publish-portal-snapshots/)).
- Ví dụ cấu hình consumer trong tài liệu không có credentials. **[CXM]** đọc ẩn danh repo snapshot.

### 2.5 Xóa hay sửa bản đã publish

- "Once a component has been released and published to the Central Repository, it cannot be altered." Lỗi thì phải ra version mới [CT] ([Can I change, modify, delete, remove, or update a component on Central?](https://central.sonatype.org/faq/can-i-change-a-component/)). Portal Guide: "Once released/published, you will not be able to remove/update/modify your components." [CT]

### 2.6 Hạn mức publish (mới)

- Theo [Maven Central Publishing Limits](https://central.sonatype.org/publish/maven-central-publishing-limits/) [CT]: tính ba chỉ số mỗi tháng theo tổ chức (file count, release size, release count). Ngưỡng đặt ở khoảng nhóm 10% publisher lớn nhất. Con số tham chiếu (phân vị 90, 90 ngày gần nhất): 1.167 file, 78 MB, **7 release**. Vượt ngưỡng thì có 30 ngày ân hạn, hết ân hạn thì bị chặn release mới. Ngưỡng hiện hành xem ở Usage Center.
- **[CXM]** "release" được đếm thế nào (theo deployment, theo version hay theo component), và SNAPSHOT có bị tính không. Trang không định nghĩa. [SL] Một polyrepo publish nhiều version mỗi tuần có thể chạm mốc 7 release/tháng.
- Artifact "commercial nature" cần Publisher Pro từ 01/10/2026 [CT] (cùng nguồn). [SL] Dự án học không thuộc diện này.

### 2.7 npm

Maven Central không nhận npm. Package npm public thì nơi tương ứng là npmjs.com: scoped package mặc định private, cần `npm publish --access public` [CT] ([Creating and publishing scoped public packages](https://docs.npmjs.com/creating-and-publishing-scoped-public-packages)). Unpublish được trong 72 giờ đầu nếu không ai phụ thuộc; sau 72 giờ cần đủ ba điều kiện (không ai phụ thuộc, dưới 300 lượt tải tuần trước, một owner). Số version đã dùng thì không dùng lại được [CT] ([npm Unpublish Policy](https://docs.npmjs.com/policies/unpublish)). **[CXM]** tải package public từ npmjs.com có cần đăng nhập không. Theo hiểu biết chung thì không cần, nhưng trang đã đọc không nói.

---

## 3. Tự host trong lab

Ràng buộc chung [SL]: lab chỉ có IP tailnet/LAN, nên mọi consumer (GitHub-hosted runner, MacBook) phải vào tailnet mới resolve được. Mỗi job CI cần một bước `tailscale/github-action` trước khi Gradle hay npm chạy, kể cả job chỉ build thư viện không cần lab. Lab tắt hoặc tailnet lỗi thì mọi build hỏng. Nếu dùng HTTP thường như registry `10.20.0.5:5000`, Gradle bắt bật `allowInsecureProtocol` cho từng repo: "For security purposes this intentionally requires a user to opt-in to using insecure protocols on case by case basis." [CT] ([UrlArtifactRepository](https://docs.gradle.org/current/dsl/org.gradle.api.artifacts.repositories.UrlArtifactRepository.html)).

### 3.1 Reposilite

| Mục | Dữ kiện | Nguồn |
|---|---|---|
| Phiên bản | **3.6.7** (09/11/2026); 3.6.6 (02/11), 3.6.5 (27/10). Repo không archived, Apache-2.0 | GitHub Releases API `dzikoysk/reposilite` [CT] |
| Phạm vi | "repository manager for Maven-based artifacts in the JVM ecosystem" | [README](https://github.com/dzikoysk/reposilite/blob/main/.github/README.md) [CT] |
| npm | **Không có.** Issue [#1346 "Support NPM"](https://github.com/dzikoysk/reposilite/issues/1346) vẫn mở. Danh sách extension mặc định khi proxy chỉ có `.jar .war .aar .xml .pom .module .asc .md5 .sha1 .sha256 .sha512` | GitHub Issues [CT]; [Mirrors](https://github.com/dzikoysk/reposilite/blob/main/reposilite-site/data/guides/features/mirrors.md) [CT] |
| Bộ nhớ | README: "assign around 20MB of RAM". Trang JAR: 20 MB tối thiểu; **32 MB** "Repository for personal projects + CI + Proxy"; 64 MB cho repo public dùng chung; 128 MB+ cho repo lớn. Khuyến nghị an toàn 32–64 MB, đặt bằng `-Xmx` (Docker: `JAVA_OPTS`) | [README](https://github.com/dzikoysk/reposilite/blob/main/.github/README.md), [JAR](https://github.com/dzikoysk/reposilite/blob/main/reposilite-site/data/guides/installation/jar.md), [Docker](https://github.com/dzikoysk/reposilite/blob/main/reposilite-site/data/guides/installation/docker.md) [CT] |
| RSS thực của container | Các con số trên là heap. Metaspace, thread stack và code cache cộng thêm. **[CXM]** RSS thực, phải đo sau khi chạy | [SL] |
| JVM trong image | `eclipse-temurin:21.0.13_9-jre-noble` (Dockerfile ở tag 3.6.7). Trang JAR vẫn ghi "JVM: 11-18", có vẻ chưa cập nhật | [Dockerfile@3.6.7](https://github.com/dzikoysk/reposilite/blob/3.6.7/Dockerfile) [CT] |
| Repo mặc định | `releases`, `snapshots`, `private`. Visibility `PUBLIC` / `HIDDEN` / `PRIVATE`; `PRIVATE` mới bắt token khi tải. Mặc định chặn deploy đè (409 Conflict), có thể bật | [Repositories](https://github.com/dzikoysk/reposilite/blob/main/reposilite-site/data/guides/features/repositories.md) [CT] |
| Proxy (mirror) | Mỗi repo có danh sách mirror theo URL hoặc theo ID repo nội bộ, tùy chọn lưu cache (Store), lọc allowed/blocked groups (chống dependency confusion), có hướng dẫn riêng cho proxy Maven Central (lỗi 429) | [Mirrors](https://github.com/dzikoysk/reposilite/blob/main/reposilite-site/data/guides/features/mirrors.md) [CT] |
| Proxy Gradle Plugin Portal | Tài liệu không nhắc. [SL] Mirror nhận URL bất kỳ, nên trỏ được tới `https://plugins.gradle.org/m2/`. **[CXM]** chưa thử | — |
| Backend S3 | Hỗ trợ S3-compatible làm storage cho từng repo, có `prefix` và `sharedBucket` để dùng chung bucket. Ví dụ có MinIO kèm `-Dreposilite.s3.pathStyleAccessEnabled=true`. **[CXM]** chạy với RustFS (không có trong bảng tương thích) | [S3](https://github.com/dzikoysk/reposilite/blob/main/reposilite-site/data/guides/features/s3.md) [CT] |

### 3.2 Sonatype Nexus Repository Community Edition

| Mục | Dữ kiện | Nguồn |
|---|---|---|
| Phiên bản | `release-3.98.1-01` (05/11/2026) trên `sonatype/nexus-public` | GitHub Releases API [CT] |
| Định dạng | Maven và npm đều có hosted, proxy, group, "in all distributions" | [Formats](https://help.sonatype.com/en/formats.html) [CT] |
| Hạn mức CE | Tối đa 40.000 component và 100.000 request/ngày; vượt thì ngừng nhận component mới tới khi xuống dưới ngưỡng | [CE onboarding](https://help.sonatype.com/en/ce-onboarding.html) [CT] |
| Bộ nhớ | Host tối thiểu: "Min allowable is 8G". Heap tối thiểu 2703M, `-Xms` bằng `-Xmx`. Cấu hình mẫu nhỏ nhất (host 8 GB): `-Xms4G -Xmx4G -XX:MaxDirectMemorySize=2g` | [Memory Overview](https://help.sonatype.com/en/nexus-repository-memory-overview.html) [CT] |
| Khác | Cần Java 21 (từ 3.78.0 bundle có sẵn JVM). H2 nhúng chịu tối đa 200.000 request/ngày hoặc 100.000 component; tài liệu khuyên dùng PostgreSQL ngoài. Cấu hình tham chiếu nhỏ nhất (Extra-Small) là 4 vCPU, 16 GiB | [System Requirements](https://help.sonatype.com/en/sonatype-nexus-repository-system-requirements.html) [CT] |

[SL] Ngay cả mức tối thiểu 8 GB cũng gấp khoảng 8 lần 1 GiB còn trống ở lab.

---

## 4. Phương án khác (mỗi dòng một phương án)

- **JitPack**: build theo yêu cầu từ tag hoặc commit GitHub, toạ độ `com.github.User:Repo:Tag` (multi-module: `com.github.User.Repo:Module:Tag`), mặc định JDK 8, đổi qua `jitpack.yml` (ví dụ `jdk: openjdk17`, hoặc SDKMAN `21-open`) [CT] ([Docs](https://docs.jitpack.io/), [Building](https://docs.jitpack.io/building/)). **[CXM]** có Java 25 không, có miễn phí cho repo public không (trang đã đọc không nói), và có phục vụ plugin marker không.
- **GitHub Releases + Gradle composite build (`includeBuild`)**: composite build thay dependency ngoài bằng mã nguồn local, không cần publish [CT] ([Gradle 9.9.1 Composite Builds](https://docs.gradle.org/current/userguide/composite_builds.html)). [SL] Hợp cho MacBook (các repo được clone cạnh nhau). CI thì phải `actions/checkout` thêm repo phụ thuộc theo đúng tag, nên không còn là artifact có version, trái tinh thần [ADR-0001](../adr/0001-polyrepo.md). Đính jar vào GitHub Releases rồi trỏ một repo `ivy` có pattern URL tới đó: **[CXM]** chưa tra.
- **Repo Maven `s3://` trên RustFS**: Gradle hỗ trợ sẵn repo `s3://bucket/path` với `AwsCredentials`, và system property `org.gradle.s3.endpoint` để trỏ tới dịch vụ S3-compatible [CT] ([Gradle 9.9.1 Supported Protocols](https://docs.gradle.org/current/userguide/supported_repository_protocols.html)). Không tốn thêm RAM ở lab [SL]. Vẫn cần tailnet; không có npm; **[CXM]** path-style addressing với RustFS và việc đọc không credentials.
- **npmjs.com** (cho phần npm): public, scoped package phải `--access public`, unpublish có điều kiện (mục 2.7) [CT]. **[CXM]** đọc ẩn danh.
- **Gradle Plugin Portal** (chỉ cho convention plugin): duyệt tay lần đầu, ID dạng `io.github.<user>.<plugin>`, không nhận SNAPSHOT [CT] ([Plugin Portal docs](https://plugins.gradle.org/docs/publish-plugin)).

---

## 5. Bảng so sánh

| Phương án | Đọc ẩn danh? | Cần tailnet? | RAM ở lab | Độ khó khi publish |
|---|---|---|---|---|
| GitHub Packages (Maven) | **Không**, cần PAT classic `read:packages` hoặc `GITHUB_TOKEN` [CT] | Không | 0 | Thấp: `GITHUB_TOKEN` + `packages: write`. Consumer ở repo khác: **[CXM]** `GITHUB_TOKEN` có đủ không |
| GitHub Packages (npm) | **Không** [CT] | Không | 0 | Thấp; phải "Add repository" cho từng package × repo consumer |
| Maven Central | Có (release) [SL, theo hiểu biết chung] | Không | 0 | Cao: PGP, sources/javadoc, POM đủ, plugin cộng đồng, không xóa được, hạn mức tháng |
| npmjs.com | **[CXM]** (thường là có) | Không | 0 | Thấp: `npm publish --access public`, unpublish có điều kiện |
| Reposilite (lab) | Có nếu repo `PUBLIC` [CT] | **Có** | Heap 32–64 MB khuyến nghị [CT]; RSS **[CXM]** | Thấp: token Reposilite; chỉ Maven, không npm |
| Nexus CE (lab) | Có thể cấu hình (cho phép anonymous) **[CXM]** | **Có** | Host tối thiểu 8 GB [CT] | Trung bình; có cả Maven và npm |
| S3 trên RustFS (`s3://`) | **[CXM]** | **Có** | 0 thêm (RustFS đã chạy) | Thấp ở phía Gradle; không có npm, không có UI hay index |
| JitPack | **[CXM]** | Không | 0 | Thấp (chỉ cần tag), nhưng **[CXM]** Java 25 |
| Composite build (`includeBuild`) | Không áp dụng (đọc mã nguồn) | Không | 0 | Không cần publish; mất version hóa artifact |
