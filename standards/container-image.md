# Chuẩn: Container image

Từ 2026-11-15 hạ tầng chỉ cần mức tối thiểu (CLAUDE.md, mục Chuẩn production); các mục đánh dấu Hoãn tới G7 giữ làm tham khảo. G0 giữ: build một lần, tag SHA, digest, Trivy chặn HIGH/CRITICAL.

- Ngày tra: 2026-11-12; sửa 2026-11-15 theo [ADR-0017](../adr/0017-images-and-charts-on-ghcr.md) (image lên GHCR) và quyết định hoãn hạ tầng sâu sang G7
- Phiên bản áp dụng: Java 25 (Eclipse Temurin 25.0.5+8), Spring Boot 4.1.2, Docker Buildx/BuildKit (bản đi kèm Docker Desktop lúc build), Trivy v0.76.2, OCI Image Spec (nhánh `main`), Kubernetes 1.37 (kiến trúc node `linux/amd64`), Next.js (docs cập nhật 2026-09-18)
- Phạm vi: `Dockerfile` và `.dockerignore` của mọi repo trong `services/`, `simulators/`, `frontend/`; bước build image trong reusable workflow ở `platform/.github/workflows/` (chi tiết pipeline xem [`ci-cd.md`](ci-cd.md))

## Checklist

### Cách build và base image
- [x] Service Spring Boot dùng Dockerfile multi-stage: stage 1 tách jar bằng `java -Djarmode=tools -jar application.jar extract --layers --destination extracted`, stage 2 chỉ chép 4 layer `dependencies`, `spring-boot-loader`, `snapshot-dependencies`, `application` theo đúng thứ tự đó. Thư viện ít đổi nằm layer dưới nên đẩy bản mới chỉ tải lại layer `application`. [Spring Boot – Dockerfiles](https://docs.spring.io/spring-boot/reference/packaging/container-images/dockerfiles.html), [Efficient container images](https://docs.spring.io/spring-boot/reference/packaging/container-images/efficient-images.html)
- [x] Jar được Gradle build ở bước trước (cache Gradle của CI), Dockerfile chỉ `COPY` jar vào. Tách biên dịch khỏi `docker build` để không phải biên dịch dưới giả lập khi build amd64 trên Mac. [Docker – Multi-platform builds](https://docs.docker.com/build/building/multi-platform/)
- [x] Runtime stage dùng `eclipse-temurin:25-jre-noble` (JRE, Ubuntu 24.04 LTS, Docker Official Image), không dùng tag `-jdk`. JRE đủ để chạy và nhỏ hơn JDK; Temurin có bản amd64 và arm64. [Docker Hub – eclipse-temurin](https://hub.docker.com/_/eclipse-temurin), [danh sách tag](https://github.com/docker-library/docs/blob/master/eclipse-temurin/README.md)
- [x] `FROM` ghim theo digest, dạng `eclipse-temurin:25-jre-noble@sha256:<digest>`; Renovate/Dependabot mở PR khi digest đổi. Digest bảo đảm build lặp lại được, nhưng nếu không tự động cập nhật thì mất bản vá bảo mật. [Docker – Build best practices: Pin base image versions](https://docs.docker.com/build/building/best-practices/#pin-base-image-versions)
- [x] Không cài thêm gói vào runtime stage, trừ khi có lý do ghi ngay tại dòng `RUN`. Ít gói thì ít CVE và image nhỏ. [Docker – Don't install unnecessary packages](https://docs.docker.com/build/building/best-practices/#dont-install-unnecessary-packages)
- [x] CI build với `--pull` để luôn lấy base image mới nhất của digest đang ghim, và build lại định kỳ (hằng tuần) kể cả khi code không đổi. Image là snapshot, chỉ build lại mới nhận bản vá. (Sửa 2026-11-17, [G0-23](../.scratch/g0-platform/issues/23-hello-image.md) Q10) Base ghim digest nên build lại với cùng digest không nhận bản vá nào; bản vá đến qua PR Dependabot đổi digest, merge thì ra SHA và image mới. Lần chạy hằng tuần vì vậy là **quét lại** bằng DB Trivy mới (`schedule` chỉ chạy job build, không push), để bắt CVE mới công bố trên image đang chạy. [Docker – Rebuild your images often](https://docs.docker.com/build/building/best-practices/#rebuild-your-images-often)

### AOT cache (Java 25) thay cho CDS
- [x] Runtime stage chạy một training run lúc build: `java -XX:AOTCacheOutput=app.aot -Dspring.context.exit=onRefresh -jar application.jar`, và `ENTRYPOINT ["java", "-XX:AOTCache=app.aot", "-jar", "application.jar"]`. Với Java 25, Spring Boot khuyên dùng AOT cache thay CDS để giảm thời gian khởi động và bộ nhớ. [Spring Boot – AOT Cache and CDS](https://docs.spring.io/spring-boot/reference/packaging/aot-cache.html), [JEP 514](https://openjdk.org/jeps/514)
- [x] Training run nằm trong **runtime stage** (cùng base image, cùng kiến trúc với lúc chạy). AOT cache gắn với một ứng dụng (classpath/`-jar`), một bản JDK, một OS và kiến trúc CPU; đổi bất kỳ thứ nào phải tạo lại. [JDK 25 – java: Ahead-of-Time Cache](https://docs.oracle.com/en/java/javase/25/docs/specs/man/java.html)
- [x] Training run không được kết nối DB, Kafka hay dịch vụ ngoài (tắt bằng property truyền qua `-D` chỉ cho lệnh training). Một số tương tác từ xa có thể xảy ra trước khi context refresh xong. [Spring Boot – How-to: AOT Cache](https://docs.spring.io/spring-boot/how-to/aot-cache.html)
- [x] Kiểm cache có được dùng thật: chạy container với `-Xlog:aot` một lần và xem log; mặc định `-XX:AOTMode=auto` sẽ lặng lẽ chạy tiếp không cache nếu cache hỏng. [JDK 25 – java: -XX:AOTMode](https://docs.oracle.com/en/java/javase/25/docs/specs/man/java.html)

### Chạy non-root
- [x] Runtime stage tạo user riêng với UID/GID số cố định (ví dụ `10001:10001`) và đặt `USER 10001:10001` trước `ENTRYPOINT`. Dịch vụ không cần đặc quyền thì không chạy root; dùng UID số để kubelet kiểm được `runAsNonRoot`. [Docker – Best practices: USER](https://docs.docker.com/build/building/best-practices/#user), [Kubernetes – Pod Security Standards (Restricted)](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted)
- [ ] File ứng dụng thuộc root và chỉ đọc với user chạy (`COPY` mặc định là root); ứng dụng chỉ ghi vào `/tmp` (mount `emptyDir` khi chạy `readOnlyRootFilesystem`). Trang image Temurin ghi rằng container non-root hoặc read-only cần `/tmp` ghi được; Tomcat nhúng cũng dùng thư mục tạm (**chưa xác minh**: chưa tìm được nguồn chính thức cho ý này). [Docker Hub – eclipse-temurin](https://hub.docker.com/_/eclipse-temurin)
- [x] `ENTRYPOINT` dạng exec (mảng JSON), không bọc qua `sh -c`. Java phải là PID 1 để nhận SIGTERM và chạy graceful shutdown (xem [`zero-downtime.md`](zero-downtime.md)). [Docker – Best practices: ENTRYPOINT](https://docs.docker.com/build/building/best-practices/#entrypoint)

### JVM trong container
- [ ] Không tắt `UseContainerSupport` (mặc định bật); JVM tự đọc giới hạn bộ nhớ và CPU của cgroup. [JDK 25 – java: -XX:-UseContainerSupport](https://docs.oracle.com/en/java/javase/25/docs/specs/man/java.html)
- [ ] Đặt heap theo phần trăm, không dùng `-Xmx` cố định: `-XX:MaxRAMPercentage=75` (mặc định chỉ 25%, quá ít cho container một tiến trình). Phần còn lại cho metaspace, code cache, thread stack, direct buffer; con số 75 phải được xác nhận bằng số đo RSS. [JDK 25 – java: -XX:MaxRAMPercentage](https://docs.oracle.com/en/java/javase/25/docs/specs/man/java.html)
- [ ] Tùy chọn JVM truyền qua biến môi trường `JAVA_TOOL_OPTIONS` từ Helm values, không hard-code vào `ENTRYPOINT` (trừ `-XX:AOTCache`). Đổi heap không cần build lại image. [JDK 25 – java (JAVA_TOOL_OPTIONS)](https://docs.oracle.com/en/java/javase/25/docs/specs/man/java.html)
- [ ] Biết GC nào được chọn: JVM chọn Serial GC nếu thấy dưới 2 CPU hoặc dưới 1792 MB, G1 nếu ngược lại. Pod nhỏ (limit < 1792 Mi) sẽ chạy Serial GC; nếu muốn G1 phải đặt `-XX:+UseG1GC` rõ ràng, và dùng cùng cờ GC ở training run. [JDK 25 – GC Ergonomics](https://docs.oracle.com/en/java/javase/25/gctuning/ergonomics.html)
- [ ] Bật `-XX:+ExitOnOutOfMemoryError` để OOM thì tiến trình thoát và Kubernetes khởi động lại, thay vì chạy tiếp ở trạng thái hỏng. **Chưa xác minh**: cờ này không có trong man page `java` của JDK 25; kiểm bằng `java -XX:+PrintFlagsFinal -version | grep ExitOnOutOfMemoryError`. [JDK 25 – java](https://docs.oracle.com/en/java/javase/25/docs/specs/man/java.html)

### Đa kiến trúc
- [x] Image chạy trên cụm được build cho `linux/amd64` (`docker buildx build --platform linux/amd64`); thiếu bước này pod báo `exec format error`. [Docker – Multi-platform builds](https://docs.docker.com/build/building/multi-platform/), [homelab mục 9](../../platform/docs/homelab-hyperv.md)
- [x] Image chính thức do CI build trên runner amd64, không đẩy từ Mac. Trên Mac M1, runtime stage (có training run AOT) chạy dưới giả lập, chậm hơn nhiều so với build native. [Docker – Multi-platform builds: emulation](https://docs.docker.com/build/building/multi-platform/#qemu)
- [x] Stage chỉ tách jar dùng `FROM --platform=$BUILDPLATFORM` (việc tách jar không phụ thuộc kiến trúc); training run AOT thì không được, vì cache phải khớp kiến trúc lúc chạy. [Docker – Cross-compilation](https://docs.docker.com/build/building/multi-platform/#cross-compilation)

### Build context
- [x] Repo có `.dockerignore` loại `.git`, `.gradle`, `build/` (trừ jar cần dùng, mở lại bằng `!build/libs/*.jar`), `node_modules`, `.env*`, `*.pem`, `*.key`, file IDE. Context nhỏ thì build nhanh và không lọt bí mật vào builder. [Docker – .dockerignore files](https://docs.docker.com/build/concepts/context/#dockerignore-files)

### Tag, digest, metadata
- [x] Mỗi image có tag bất biến bằng git SHA đầy đủ (ví dụ `ghcr.io/<user>/commerce-hub-order:<sha>`; sửa 2026-11-15, ADR-0017, trước là `10.20.0.5:5000/order:<sha>`); không bao giờ dùng hoặc ghi đè `latest`. Tag có thể bị trỏ sang image khác, digest thì không. [Kubernetes – Images](https://kubernetes.io/docs/concepts/containers/images/)
- [ ] CI ghi **digest** (`@sha256:...`) vào `gitops/envs/<env>/<service>/values.yaml`; tag chỉ để người đọc. Kubernetes chạy đúng một bản code mỗi lần khởi động container khi chỉ định digest. [Kubernetes – Images: image names](https://kubernetes.io/docs/concepts/containers/images/#image-names)
- [x] Image có các nhãn OCI: `org.opencontainers.image.source`, `.revision` (git SHA), `.version`, `.created` (RFC 3339), `.title`, `.base.name`, `.base.digest`. Truy được image về commit và base image khi có CVE. (Thêm 2026-11-17, G0-23 Q8) `revision`, `version`, `created` do reusable workflow đặt qua `labels:` của `build-push-action` (chỉ CI biết giá trị); Dockerfile giữ nhãn tĩnh. Nhãn gắn lúc xuất image nên `created` đổi mỗi lần không làm mất cache. [OCI Image Spec – Annotations](https://github.com/opencontainers/image-spec/blob/main/annotations.md)

### SBOM, quét lỗ hổng, ký
- [ ] **Hoãn tới G7** (2026-11-15), cùng attestation trong [`ci-cd.md`](ci-cd.md). Build với `--sbom=true` (SPDX, do BuildKit Syft scanner tạo) và giữ provenance mặc định `mode=min`. Cần driver `docker-container` hoặc containerd image store; driver `docker` với image store cổ điển báo lỗi. [Docker – SBOM attestations](https://docs.docker.com/build/metadata/attestations/sbom/), [Build attestations](https://docs.docker.com/build/metadata/attestations/)
- [x] CI chặn merge khi Trivy thấy lỗ hổng HIGH/CRITICAL đã có bản vá: `trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 <image>`. Lỗ hổng chưa có bản vá chỉ báo cáo, không chặn. (Thêm 2026-11-17, G0-23 Q9) Quét **trước khi push**: build `load` vào Docker của runner, `docker save` rồi quét file tar bằng image `aquasec/trivy` ghim digest (không dùng `trivy-action`, xem ci-cd.md), rồi build lại với `push: true` cùng input để BuildKit xuất lại đúng kết quả từ cache ([Docker – Test before push](https://docs.docker.com/build/ci/github-actions/test-before-push/)). Workflow so `rootfs.diff_ids` của bản trên GHCR với bản đã quét, khác thì đỏ. [Trivy – trivy image](https://trivy.dev/latest/docs/references/configuration/cli/trivy_image/)
- [x] Mọi ngoại lệ ghi trong `.trivyignore` kèm mã CVE, lý do và ngày hết hạn trong comment. Bỏ qua lỗ hổng phải là quyết định có ghi lại. [Trivy – trivy image (--ignorefile)](https://trivy.dev/latest/docs/references/configuration/cli/trivy_image/)
- [x] Xuất báo cáo Trivy dạng `sarif` lên GitHub Code Scanning. Lịch sử CVE xem được theo commit. [Trivy – trivy image (--format)](https://trivy.dev/latest/docs/references/configuration/cli/trivy_image/)
- [ ] Ký image: **chưa bắt buộc ở home lab** (xem mục lệch chuẩn). Khi bật, ký theo digest bằng cosign key-pair. [Sigstore – Signing containers](https://docs.sigstore.dev/cosign/signing/signing_with_containers/)

### Next.js (frontend)
- [ ] `next.config.js` đặt `output: 'standalone'`; runtime stage chỉ chép `.next/standalone`, cộng `public` và `.next/static` (standalone không tự chép hai thư mục này), chạy `node server.js` với `HOSTNAME=0.0.0.0`. Không cần cài `node_modules` ở runtime. [Next.js – output](https://nextjs.org/docs/app/api-reference/config/next-config-js/output)
- [ ] Base image Node bản LTS hiện hành, ghim digest, chạy non-root; các mục tag/SBOM/Trivy/nhãn OCI ở trên áp dụng như service Java. **Chưa xác minh**: bản Node LTS cụ thể và user mặc định của image `node` chưa tra trong đợt này.

## Lựa chọn và phương án đã loại

| Quyết định | Chọn | Loại | Lý do | Nguồn |
|---|---|---|---|---|
| Cách build image Spring Boot | Dockerfile multi-stage + layered jar | Buildpacks (`bootBuildImage`); Jib | Dockerfile minh bạch từng bước, hợp mục tiêu học, chạy được training run AOT. Buildpacks cũng hỗ trợ AOT cache (`BP_JVM_AOTCACHE_ENABLED`) nhưng che phần lớn chi tiết và builder mặc định không có shell. Jib build không cần Docker daemon nhưng không chạy JVM lúc build nên không tạo được AOT cache | [Dockerfiles](https://docs.spring.io/spring-boot/reference/packaging/container-images/dockerfiles.html), [bootBuildImage](https://docs.spring.io/spring-boot/gradle-plugin/packaging-oci-image.html), [Paketo spring-boot](https://github.com/paketo-buildpacks/spring-boot), [Jib](https://github.com/GoogleContainerTools/jib) |
| Base image | `eclipse-temurin:25-jre-noble` | `bellsoft/liberica-openjre-debian:25-cds` (ví dụ trong docs Spring); bản `-alpine`; `-resolute`; tự `jlink` | Temurin là Docker Official Image, có amd64/arm64. Alpine dùng musl, khác glibc của môi trường dev. Resolute (26.04) mới, ít được dùng hơn. `jlink` cho image nhỏ nhất nhưng phải tự duy trì danh sách module; để dành khi đã đo được kích thước là vấn đề | [eclipse-temurin](https://hub.docker.com/_/eclipse-temurin) |
| Tăng tốc khởi động | AOT cache (JEP 514/515) | CDS (`-XX:SharedArchiveFile`); Spring AOT/GraalVM native | Spring Boot 4.1 khuyên AOT cache cho Java 25. Native image đổi thời gian build và khả năng tương thích lấy tốc độ, không cần ở quy mô này | [AOT Cache and CDS](https://docs.spring.io/spring-boot/reference/packaging/aot-cache.html) |
| Quét lỗ hổng | Trivy | Grype | Cả hai đều quét image và SBOM. Trivy có sẵn `--ignore-unfixed`, `--exit-code`, xuất SARIF trong một công cụ | [Trivy](https://trivy.dev/latest/docs/references/configuration/cli/trivy_image/), [Grype](https://github.com/anchore/grype) |
| Định danh image khi deploy | Digest | Chỉ tag | Tag ghi đè được; digest bất biến | [Kubernetes – Images](https://kubernetes.io/docs/concepts/containers/images/) |

## Lệch chuẩn có chủ đích ở home lab

- ~~**Registry không TLS, không auth** (`10.20.0.5:5000`, docker-registry 2.8 trên `gw`).~~ Không còn (sửa 2026-11-15, [ADR-0017](../adr/0017-images-and-charts-on-ghcr.md)): image lên GHCR `ghcr.io/<user>/<repo>`, có TLS, CI ghi bằng `GITHUB_TOKEN`. Không cần `insecure-registries` hay cấu hình BuildKit cho registry HTTP; Trivy quét thẳng image trên GHCR hoặc file tar trước khi đẩy. Câu hỏi chưa xác minh về `--insecure` của Trivy không còn.
- **Chưa ký image** (hoãn G7, 2026-11-15, cùng SBOM và attestation). Cụm chưa có admission controller kiểm chữ ký nên chữ ký chưa chặn được gì. Câu hỏi cũ về registry 2.8 lưu chữ ký không còn; GHCR có lưu được chữ ký cosign và attestation không: **chưa xác minh**, kiểm khi làm ở G7.
- **Image không đa kiến trúc.** Chỉ build `linux/amd64` vì cụm chỉ có amd64; build thêm arm64 tốn gấp đôi thời gian mà không dùng.

## Bằng chứng cần có

Ghi vào `docs/experiments/YYYY-MM-container-image-<service>.md`, đo cho service đầu tiên rồi lặp lại khi đổi base image:

| Số đo | Lệnh | Tiêu chí |
|---|---|---|
| Kích thước image (nén và giải nén) | `docker buildx imagetools inspect <img>@<digest>`; `docker image inspect <img> --format '{{.Size}}'` | Ghi số; so với lần đo trước, tăng > 10% phải giải thích |
| Thời gian build lạnh và ấm (chỉ đổi code) | `time docker buildx build --platform linux/amd64 --no-cache ...` rồi build lại sau khi sửa 1 class | Build ấm chỉ tải lên lại layer `application` và layer `app.aot` (kiểm trong log push). `app.aot` phụ thuộc toàn bộ classpath nên sinh lại mỗi khi code đổi (sửa 2026-11-16, [ticket G0-23](../.scratch/g0-platform/issues/23-hello-image.md) Q6) |
| Thời gian khởi động có và không AOT cache | So dòng log "Started ... in N seconds" của Spring Boot trong 2 lần chạy | AOT cache phải nhanh hơn; ghi tỉ lệ |
| Lỗ hổng | `trivy image --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 <img>` | 0 HIGH/CRITICAL đã có bản vá |
| Non-root | `docker run --rm --entrypoint id <img>` | `uid=10001`, không phải 0 |
| Kiến trúc | `docker buildx imagetools inspect <img>` | Có `linux/amd64` |
| SBOM và nhãn | `docker buildx imagetools inspect <img> --format '{{ json .SBOM.SPDX }}'` (SBOM **Hoãn tới G7**); `docker image inspect <img> --format '{{json .Config.Labels}}'` | SBOM có gói Java và gói OS; đủ nhãn OCI ở checklist |
| RSS so với limit | `kubectl top pod`, `jcmd 1 VM.native_memory summary` (khi bật `-XX:NativeMemoryTracking=summary`) | RSS đỉnh dưới 90% memory limit khi chạy tải |

## Nguồn

- Spring Boot 4.1.2: [Dockerfiles](https://docs.spring.io/spring-boot/reference/packaging/container-images/dockerfiles.html), [Efficient container images](https://docs.spring.io/spring-boot/reference/packaging/container-images/efficient-images.html), [AOT Cache and CDS](https://docs.spring.io/spring-boot/reference/packaging/aot-cache.html), [How-to: AOT Cache](https://docs.spring.io/spring-boot/how-to/aot-cache.html), [Gradle plugin: Packaging OCI images](https://docs.spring.io/spring-boot/gradle-plugin/packaging-oci-image.html), [Cloud Native Buildpacks](https://docs.spring.io/spring-boot/reference/packaging/container-images/cloud-native-buildpacks.html)
- JDK 25: [java command](https://docs.oracle.com/en/java/javase/25/docs/specs/man/java.html), [GC Ergonomics](https://docs.oracle.com/en/java/javase/25/gctuning/ergonomics.html), [JEP 514](https://openjdk.org/jeps/514), [JEP 515](https://openjdk.org/jeps/515)
- Base image: [eclipse-temurin trên Docker Hub](https://hub.docker.com/_/eclipse-temurin), [README tag](https://github.com/docker-library/docs/blob/master/eclipse-temurin/README.md)
- Docker: [Build best practices](https://docs.docker.com/build/building/best-practices/), [Multi-platform builds](https://docs.docker.com/build/building/multi-platform/), [Build context và .dockerignore](https://docs.docker.com/build/concepts/context/), [SBOM attestations](https://docs.docker.com/build/metadata/attestations/sbom/), [Build attestations](https://docs.docker.com/build/metadata/attestations/)
- [OCI Image Spec – Annotations](https://github.com/opencontainers/image-spec/blob/main/annotations.md)
- [Kubernetes – Images](https://kubernetes.io/docs/concepts/containers/images/), [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [Trivy CLI `trivy image`](https://trivy.dev/latest/docs/references/configuration/cli/trivy_image/), [Trivy releases](https://github.com/aquasecurity/trivy/releases), [Grype](https://github.com/anchore/grype), [Sigstore cosign](https://docs.sigstore.dev/cosign/signing/signing_with_containers/)
- Buildpacks/Jib: [Paketo spring-boot buildpack](https://github.com/paketo-buildpacks/spring-boot), [Jib](https://github.com/GoogleContainerTools/jib)
- [Next.js – output: standalone](https://nextjs.org/docs/app/api-reference/config/next-config-js/output)
