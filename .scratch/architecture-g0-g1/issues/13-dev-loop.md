# 13 Vòng phát triển local

Type: grilling
Status: resolved
Blocked by: 04
Map: [Kiến trúc G0–G1](../map.md)

## Question

Khi code một service trên MacBook (arm64), hạ tầng (Kafka, PostgreSQL, Keycloak) lấy từ đâu: cụm home lab qua Tailscale, `platform/compose`, hay `kind`? Có dùng Tilt/Skaffold/Telepresence không. Test tích hợp chạy bằng Testcontainers trên Mac hay trong CI.

## Answer

Người dùng chốt ngày 2026-11-13, sau hai vòng grilling (Q1–Q8). Không viết ADR, vì mọi quyết định ở đây đổi lại được mà không tốn nhiều công.

**Máy dev (kiểm ngày 2026-11-13):** MacBook M1 Pro, 16 GB RAM, 10 core. VM của Docker Desktop có 8 GB và 6 CPU. Máy đã cài `kind`. Mọi image hạ tầng bên dưới đều có bản `arm64` (kiểm bằng `docker manifest inspect`): `apache/kafka` 4.1, `apicurio/apicurio-registry` 3, `postgres:18`, `quay.io/keycloak/keycloak`, `ghcr.io/cloudnative-pg/pgbouncer`, `adorsys/keycloak-config-cli`, `grafana/otel-lgtm`. Image của service mình chỉ có `linux/amd64` ([container-image.md](../../../standards/container-image.md)), nên **không** chạy chúng trong compose trên Mac.

### Hạ tầng khi code (Q1)

- **`platform/compose` trên Mac**, một stack dùng chung cho mọi service:
  - Kafka KRaft 1 broker;
  - Apicurio 3;
  - PostgreSQL 18, mỗi service một database kèm bốn role `_owner`/`_migrator`/`_app`/`_lookup` như [ADR-0010](../../../adr/0010-workspace-isolation-shared-schema-with-mandatory-rls.md); `seller_web` không có `_lookup`;
  - PgBouncer ở chế độ `transaction`;
  - Keycloak.

  Tổng khoảng 3 GB [SL, chưa đo]. Kafka 1 broker chỉ dùng ở đây, đúng như ticket 04 đã để ngỏ.
- Service chạy trên host (`./gradlew bootRun` hoặc từ IDE) với profile `local`.
- **Mac không bao giờ ghi vào hạ tầng của lab.** Lab chỉ nhận bản deploy từ CI. Từ Mac chỉ dùng `kubectl` để xem và gỡ lỗi.
- Đã loại:
  - Hạ tầng lab qua Tailscale: dữ liệu dev trộn vào môi trường duy nhất, Kafka phải mở listener ra ngoài cụm, và ADR-0004 không còn chỗ cho bản sao.
  - `kind` kèm đủ operator: riêng operator và CR đã gần kín VM 8 GB, và mỗi lần dựng lại mất vài phút.

### Config của compose lấy từ `gitops` (Q5)

- Hai container init đọc từ bản checkout `../gitops` nằm cạnh:
  - keycloak-config-cli áp chính YAML realm `commerce-hub`;
  - `yq` đọc CR `KafkaTopic` rồi gọi `kafka-topics.sh`, nên partition, retention và compaction giống lab.
- Biến riêng cho dev (redirect URI `http://localhost:<port>`, secret dev) nằm ở `platform/compose/.env.example`.
- **Lệch chuẩn có chủ đích, chỉ ở dev:** compose phụ thuộc lúc chạy vào một bản checkout cạnh nó, trong khi [ADR-0001](../../../adr/0001-polyrepo.md) nói các repo chỉ nối nhau qua contract, artifact và runtime. Ghi lý do ở README của compose. Đã loại cách chép realm và danh sách topic vào `platform`, vì bản chép sẽ trôi lệch khỏi `gitops`.
- **Sửa comment của ticket 07:** Keycloak chạy trên Mac gọi được backchannel logout về `host.docker.internal`, nên client dev của `seller-web` **có** khai backchannel và AC F1.1b kiểm được khi dev. BFF trên Mac gọi thẳng gateway trên host, không cần port-forward. Bảng phiên nằm ở database `seller_web` của compose.

### Schema Avro (Q6)

- Apicurio local được nạp bằng **đúng lệnh đăng ký schema của `contracts`** (cùng task CI dùng), trỏ vào `localhost`.
- Không profile nào bật `auto.register.schemas=true` ([kafka.md](../../../standards/kafka.md)). Lý do: auto-register bỏ qua bước kiểm tương thích, nên lỗi chỉ lộ ra khi lên lab. Tên lệnh cụ thể do spec G0 chốt, khi chọn plugin sinh code cho `contracts` (ticket 11).

### Test tích hợp (Q2)

- **Testcontainers chạy cả trên Mac lẫn CI**, cùng một lệnh `./gradlew check`. Test hành vi RLS qua PgBouncer (ticket 06) làm đỏ được ngay trên Mac.
- `testcontainers.reuse.enable=true` chỉ bật trong `~/.testcontainers.properties` của Mac. CI luôn dựng container sạch.
- Cấu hình Testcontainers nằm ở module `test-support` của `libs/service-kit` (ticket 11). Tag image ở đó và ở compose ghim cùng major.minor với production. Spec G0 chốt nguồn tag dùng chung để hai chỗ không lệch nhau.

### Cụm thử cho chart (Q3)

- `ct install` của chart `app` ([helm-chart.md](../../../standards/helm-chart.md)) chạy trên **kind trong job CI** (GitHub-hosted runner), dựng rồi bỏ mỗi lần chạy. Dùng kind trần, không operator; Job `PreSync` và Sealed Secret tắt trong `ci/*-values.yaml`.
- `platform/kind/` giữ cấu hình kind cho CI. Trên Mac chỉ dùng kind khi gỡ lỗi chart, không phải một bước của vòng code.
- Đã loại namespace tạm trên lab, vì nó ăn vào khoảng 1 GiB còn dư của ADR-0004.

### Công cụ inner loop (Q4)

- **Không dùng Tilt, Skaffold hay Telepresence ở G0–G1.** Vòng code không chạy trong cụm, và Telepresence phải cài traffic-manager vào lab. Hot reload dùng Spring Boot DevTools trên host.

### Chạy nhiều service và dữ liệu khởi đầu (Q7)

- Vòng code trên Mac nhắm vào **một service cộng các service lân cận trực tiếp của nó**. Luồng đầy đủ (sim → connector → catalog/inventory/order → seller-web) kiểm trên lab sau khi deploy. Theo ước tính, 8 JVM cộng compose cộng IDE là sát 16 GB.
- Chạy nhiều service bằng run config compound của IDE, không thêm công cụ. JVM trên Mac đặt `-Xmx256m`.
- **Profile `local` của `workspace` tạo dữ liệu khởi đầu**, theo cách idempotent: một Account dev trong realm, một Workspace và một Member có Role Owner. Topic `workspace.members` là compact và volume compose được giữ, nên chỉ cần chạy `workspace` một lần; sau đó service khác qua được bước kiểm Member mà không cần nó.
- Reset bằng `docker compose down -v`.
- Đã nhận từ ticket 11: PAT `read:packages` trong `~/.gradle/gradle.properties`; composite build `--include-build ../../libs/service-kit` khi sửa lib cùng service.

### Quan sát (Q8)

- Compose có profile tùy chọn `obs` chạy `grafana/otel-lgtm`. Service gửi OTLP tới `localhost:4318`. Không bật profile thì exporter là `none` và service vẫn chạy được.
- Spec G0 dùng profile này để kiểm "service hello có trace" trên Mac trước khi lên lab.

### Chuyển cho spec G0

- Viết `platform/compose`: stack, hai init đọc `../gitops`, `.env.example`, profile `obs`, README ghi lệch chuẩn ADR-0001.
- Viết `platform/kind/` và job `ct install` trong reusable workflow của `platform`.
- Viết profile `local` (template `services/hello`), seed của `workspace`, client Keycloak dev cho `seller-web` có backchannel.
- Đo RAM thật của compose và một vòng 3–4 service trên Mac.

## Comments
- 2026-11-12: Từ ticket [04 Ngân sách tài nguyên home lab](04-resource-budget.md#answer): cụm lab chỉ còn dư khoảng 1 GiB sau G1 ([ADR-0004](../../../adr/0004-single-instance-by-default-on-homelab.md)), không chạy thêm được bản sao môi trường (preview, namespace riêng cho dev). Nếu dev loop cần Kafka hay PostgreSQL riêng thì chạy trên Mac (Kafka 1 broker chỉ được dùng ở đó).
- 2026-11-13: Từ ticket [07 Frontend truy cập API](07-frontend-access.md#answer): chạy `seller-web` trên Mac cần một client Keycloak riêng cho dev có redirect URI `http://localhost:<port>/auth/callback`. Keycloak trong cụm không gọi được backchannel logout về Mac, nên client dev không khai backchannel (chấp nhận thiếu AC F1.1b khi dev). Cookie `__Host-` cần `Secure`; `localhost` được trình duyệt coi là secure context. BFF cần tới được gateway (port-forward) và một PostgreSQL cho bảng phiên.
- 2026-11-13: Từ ticket [11 Template service Spring Boot](11-service-template.md#answer): artifact dùng chung (`libs/service-kit`, `contracts`) publish lên GitHub Packages, và đọc cũng cần token. Mac dùng classic PAT `read:packages` trong `~/.gradle/gradle.properties`; npm cần `.npmrc` trỏ scope về GitHub Packages. Sửa lib và service cùng lúc thì dùng composite build `./gradlew build --include-build ../../libs/service-kit`, không dùng SNAPSHOT.
