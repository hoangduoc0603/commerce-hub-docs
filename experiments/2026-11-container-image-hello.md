# Bản ghi: container image của `hello` (arm64, trên máy)

Ticket [G0-23](../.scratch/g0-platform/issues/23-hello-image.md), bước 8. Bằng chứng theo mục "Bằng chứng cần có" của [container-image.md](../standards/container-image.md). Đo ngày **2026-11-16** khoảng 15:20–15:40 UTC.

Số ở đây là **arm64 native** trên Mac (quyết định Q1 của ticket): dưới giả lập amd64, training run và thời gian khởi động chủ yếu đo chi phí giả lập. Image chính thức là `linux/amd64` do CI build. Số amd64 (kích thước, build lạnh và ấm, log push) bổ sung ở bước 10, sau ticket 17. Kết quả Trivy nằm ở mục Kết quả bước 7 của ticket.

## Giả thuyết

1. Layered jar của Spring Boot làm build ấm (sửa code, không đổi thư viện) chỉ đổi layer `application`. Từ khi có AOT cache, đổi thêm layer `app.aot`, vì cache phụ thuộc toàn bộ classpath ([Q6](../.scratch/g0-platform/issues/23-hello-image.md)).
2. AOT cache của Java 25 ([JEP 514](https://openjdk.org/jeps/514), [JEP 515](https://openjdk.org/jeps/515)) làm `hello` khởi động nhanh hơn rõ so với không có cache, trên cùng image.
3. Phần `hello` thêm vào base image nhỏ so với base.

## Cách đo

Môi trường:

- Mac M1 Pro (10 nhân, 16 GiB), macOS 27.2. Docker Desktop, Docker Engine 29.8.0 arm64, buildx v0.37.1, containerd image store; VM của Docker có 6 CPU, 7,7 GiB.
- Image `hello:dev` build từ commit `0bb4b87` của `commerce-hub-hello`. Base `eclipse-temurin:25-jre-noble@sha256:e3b6f788…968c`, JRE Temurin 25.0.5+8. Spring Boot 4.1.2, Gradle 9.8.2 (daemon đã chạy sẵn).
- Dockerfile 2 stage: tách jar thành 4 layer, training run AOT trong runtime stage, `ARG` và `LABEL` đặt sau mọi `RUN`.

Lệnh (chạy trong `services/hello`):

```bash
# Kích thước
docker image ls hello:dev                                   # DISK USAGE (giải nén) và CONTENT SIZE (blob nén)
docker history hello:dev --format '{{.Size}}\t{{.CreatedBy}}'
# Kích thước nén từng layer: đọc manifest arm64 trong file `docker save` (OCI layout)

# Build lạnh: 3 lần, Gradle và Docker đo riêng
./gradlew clean bootJar -q
docker build -q --no-cache -t hello:dev --build-arg REVISION=… --build-arg VERSION=… --build-arg CREATED=… .

# Build ấm: 3 lần. Mỗi lần thêm một hằng số mang giá trị chưa từng build vào HelloApplication,
# đo Gradle + Docker, so danh sách layer (RootFS.Layers) với bản trước, rồi git checkout -- src/
diff <(docker image inspect hello:before --format '{{range .RootFS.Layers}}{{println .}}{{end}}') \
     <(docker image inspect hello:after  --format '{{range .RootFS.Layers}}{{println .}}{{end}}')

# Build không đổi code: 3 lần
./gradlew bootJar -q && docker build -q -t hello:dev --build-arg … .

# Khởi động: 5 lần mỗi kiểu, xen kẽ, cùng image; đọc dòng "Started HelloApplication in X seconds (process running for Y)"
docker run -d --entrypoint java hello:dev -XX:AOTCache=app.aot -jar application.jar   # có AOT
docker run -d --entrypoint java hello:dev -XX:AOTMode=off      -jar application.jar   # không AOT
```

Thời gian build lấy `real` của `/usr/bin/time -p`. Build lạnh dùng `--no-cache` nên mọi bước chạy lại, nhưng base image đã có sẵn trên máy: không tính thời gian tải base.

## Số đo

### Kích thước

| | Giải nén | Nén |
|---|---|---|
| Image `hello:dev` | 563 MB | 136,1 MB |
| Riêng base Temurin (5 layer đầu) | | 102,4 MB |
| Phần `hello` thêm vào | | 33,8 MB |

Từng layer của `hello` (7 layer sau base):

| # | Layer | Giải nén | Nén |
|---|---|---|---|
| 6 | `RUN groupadd … useradd` (user 10001) | 41 kB | 1,1 kB |
| 7 | `WORKDIR /application` | 8 kB | 0,1 kB |
| 8 | `dependencies` (41 jar) | 21,9 MB | 19,6 MB |
| 9 | `spring-boot-loader` | 4,1 kB | 32 B |
| 10 | `snapshot-dependencies` | 4,1 kB | 32 B |
| 11 | `application` | 12,3 kB | 1,8 kB |
| 12 | `app.aot` | 56,8 MB | 14,1 MB |

Thư viện gần như không nén được (jar vốn đã là zip). `app.aot` nén từ 56,8 MB xuống 14,1 MB. Không có AOT cache, image sẽ khoảng 506 MB giải nén, 122 MB nén.

### Thời gian build

| Kiểu | Lần 1 | Lần 2 | Lần 3 | Trung vị |
|---|---|---|---|---|
| `./gradlew clean bootJar` | 1,36 s | 0,81 s | 0,80 s | 0,81 s |
| `docker build --no-cache` (lạnh) | 7,78 s | 7,00 s | 6,71 s | 7,00 s |
| Build ấm (Gradle + Docker, sửa 1 class) | 8,25 s | 8,91 s | 7,70 s | 8,25 s |
| Build không đổi code (Gradle + Docker) | 1,56 s | 1,31 s | 1,01 s | 1,31 s |

Training run AOT chiếm khoảng 5 s trong cả build lạnh lẫn build ấm. Nó là phần lớn thời gian build ấm.

### Layer đổi khi build ấm

| Lần | `diff` của `RootFS.Layers` (12 layer) |
|---|---|
| 1, 2, 3 | `11,12c11,12`: chỉ `application` và `app.aot` |

Mỗi bản code mới chỉ phải đẩy lên khoảng 1,8 kB (`application`) và 14,1 MB (`app.aot`) dạng nén. `dependencies` (19,6 MB) và các layer khác dùng lại.

### Khởi động

| | Lần 1 | 2 | 3 | 4 | 5 | Trung vị |
|---|---|---|---|---|---|---|
| Có AOT: `Started … in` | 0,649 | 0,592 | 0,701 | 0,595 | 0,572 | **0,595 s** |
| Có AOT: `process running for` | 0,814 | 0,729 | 0,835 | 0,721 | 0,687 | **0,729 s** |
| Không AOT: `Started … in` | 1,318 | 1,309 | 1,326 | 1,307 | 1,555 | **1,318 s** |
| Không AOT: `process running for` | 1,569 | 1,532 | 1,545 | 1,536 | 1,769 | **1,545 s** |

Tỉ lệ trung vị: `process running for` nhanh hơn **2,1 lần** (1,545 / 0,729), `Started … in` nhanh hơn 2,2 lần. Kiểm cache được dùng thật: `-XX:AOTMode=on` thoát 0, `-Xlog:aot` có `Opened AOT cache app.aot.` (bước 6 của ticket).

## Phát hiện phụ

- **Build ấm đầu tiên bị nhiễu bởi cache.** Lần đo đầu dùng hằng số `"warm-1"`, trùng giá trị đã build trên một bản chép ở bước chuẩn bị. Gradle đóng jar tái lập được (cùng nguồn thì ra cùng byte), nên BuildKit lấy lại layer `application` và `app.aot` của lần đó, và build "ấm" chỉ mất 2,05 s. Số trong bảng trên dùng một giá trị mới mỗi lần đo.
- **Hai lần `--no-cache` từ cùng một jar ra layer khác nhau** (`6,8c6,8` và `11,12c11,12`). Lệnh `extract` ghi file với mtime là lúc tách, và `groupadd` cùng `WORKDIR` cũng ghi mtime mới, nên nội dung layer đổi dù file y hệt. Hệ quả cho bước 9: runner CI không có build cache thì mỗi lần build đẩy lại cả `dependencies` (19,6 MB). Muốn giữ tiêu chí Q6 trên CI phải có BuildKit cache giữa các lần chạy (`cache-from`/`cache-to`), hoặc chuẩn hóa timestamp (`SOURCE_DATE_EPOCH` cùng `rewrite-timestamp`). Cách nào hợp với GHCR và `GITHUB_TOKEN`: **chưa xác minh**, quyết ở bước 9.

## Kết luận

- Giả thuyết 1 **đúng**: build ấm chỉ đổi `application` và `app.aot`, trên máy có build cache. Trên CI, điều này còn phụ thuộc cache hoặc timestamp, xem phát hiện phụ.
- Giả thuyết 2 **đúng**: AOT cache rút thời gian tới khi sẵn sàng từ 1,55 s xuống 0,73 s (nhanh hơn 2,1 lần). Cái giá: thêm 14,1 MB nén mỗi bản deploy và khoảng 5 s mỗi lần build. Giữ AOT cache (Q6).
- Giả thuyết 3 **đúng một phần**: `hello` thêm 33,8 MB nén vào base 102,4 MB. Trong đó 14,1 MB là `app.aot`, 19,6 MB là thư viện; code của `hello` chỉ 1,8 kB. Base JRE Ubuntu là phần lớn nhất, đổi base (`jlink`, distroless) chỉ đáng xét khi kích thước thành vấn đề ([container-image.md](../standards/container-image.md), bảng phương án).
- Số arm64 không thay được số amd64 của image chính thức. Bước 10 đo lại kích thước, build lạnh và ấm trên runner amd64, kèm log push.
