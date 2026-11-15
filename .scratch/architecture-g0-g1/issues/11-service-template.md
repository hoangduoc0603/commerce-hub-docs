# 11 Template service Spring Boot

Type: grilling
Status: resolved
Blocked by: 01, 02
Map: [Kiến trúc G0–G1](../map.md)
Ghi chú 2026-11-15: phần `libs/service-kit` (convention plugin, ArchUnit, module dùng chung, GitHub Packages) bị thay bởi [ADR-0018](../../../adr/0018-self-contained-services-no-shared-library-yet.md): service là project Spring Initializr bình thường, chưa có thư viện dùng chung, layout hexagonal là quy ước. Phần còn lại của ticket (Gradle, virtual thread, JdbcClient/JPA, hexagonal, profile) giữ nguyên. Nội dung dưới đây là bản ghi lúc chốt.

## Question

Một service mới bắt đầu từ đâu?
- Build tool: Gradle (đề xuất trong [container-image.md](../../../standards/container-image.md), [ci-cd.md](../../../standards/ci-cd.md)) hay Maven.
- Layout module hexagonal (domain / application / adapter), quy tắc phụ thuộc kiểm bằng gì (ArchUnit?).
- Cái gì vào `libs/` dùng chung (Workspace context, observability, error model) và cái gì không; version và publish thế nào.
- Template là repo mẫu, generator, hay copy tay; chart dùng chung tên `spring-service` (platform README) hay `application` (helm-chart.md).

## Answer

Chốt ngày 2026-11-13 (người dùng), sau hai vòng grilling (Q1–Q20). Quyết định khó đảo ngược: [ADR-0012](../../../adr/0012-two-persistence-stacks-one-rls-hook.md), hai công nghệ persistence với một hook RLS chung. [ADR-0005](../../../adr/0005-kafka-from-g1-with-deliberate-dual-write.md) có thêm mục sửa đổi về inbox. Tra cứu nơi publish artifact: [2026-11-maven-artifact-registry.md](../../../research/2026-11-maven-artifact-registry.md).

### Build và stack

- **Gradle 9.x, Groovy DSL** (Q1). Mỗi repo có wrapper riêng và version catalog `gradle/libs.versions.toml`.
- **Spring MVC chạy virtual thread** (`spring.threads.virtual.enabled=true`) cho mọi service G1 (Q2). Lý do: `ScopedValue` của ticket 06 cần luồng đồng bộ. Gateway vẫn nằm trong fog.
- **Persistence theo loại service** (Q3, Q10, ADR-0012):
  - `JdbcClient` với SQL tay: inventory, order, channel-connector.
  - JPA: workspace, catalog, marketplace-sim. Riêng upsert có version guard của catalog viết bằng native query.
  - Hook RLS dùng chung: `TransactionExecutionListener.afterBegin` chạy `set_config('app.workspace_id', ?, true)`.
  - Service JPA bắt buộc `open-in-view=false`, không bật second-level cache, `ddl-auto=validate`.

### Layout

- **Mọi service, kể cả `marketplace-sim`, dùng chung một layout hexagonal trong một module** (Q4): `domain`, `application` (use case + port), `adapter.in.{web,kafka}`, `adapter.out.{persistence,kafka}`.
- Luật ArchUnit, nằm trong `service-kit` module `test-support`: `domain` không import Spring hay adapter; `application` không import adapter. Service JPA được dùng `jakarta.persistence.*` trong `domain` (Q11).

### Template

- **Template là repo `services/hello`**, cũng chính là service "hello" của G0: luôn build được, CI xanh, có trace. Bật "template repository" trên GitHub (Q5).
- Template chỉ giữ phần mỏng: skeleton package, `application.yaml`, Dockerfile, `settings.gradle` (có `pluginManagement`), workflow gọi reusable workflow của `platform`.
- Thứ cần đồng bộ về sau đi qua artifact có version: convention plugin, `service-kit`, chart `app`, reusable workflow. Như vậy repo đã sinh ra không bị lệch khỏi chuẩn.

### Chart dùng chung `app`

- **Một chart cho mọi workload, đổi tên `spring-service` thành `app`** (Q6, Q19). Chart phục vụ cả service Spring, `marketplace-sim` và `seller-web` (Node, ticket 07). "Chart `application`" ở [helm-chart.md](../../../standards/helm-chart.md) là *kiểu* chart, không phải tên. Spec G0 đổi tên theo trong `helm-chart.md`, `gitops-argocd.md`, `db-migration.md`, `zero-downtime.md` và `platform/README.md`.
- Phần riêng của JVM nằm dưới `jvm.enabled` (mặc định `true`): `JAVA_TOOL_OPTIONS` với `MaxRAMPercentage=75`. Values lab ghi đè xuống 60 cho pod 512Mi; spec G0 đo RSS để chốt.
- **Trust bundle** ([ADR-0014](../../../adr/0014-lab-pki-and-dns.md)): chart mount truststore PKCS12 do trust-manager sinh. App JVM thêm `-Djavax.net.ssl.trustStore` vào `JAVA_TOOL_OPTIONS`; app Node (`seller-web`) đặt `NODE_EXTRA_CA_CERTS`. Mọi HTTP client và `JwtDecoder` tin CA của lab mà không sửa code.
- Các khả năng bật bằng values:
  - port thứ hai (admin API của sim, ticket 12);
  - `HTTPRoute` (values `httpRoute.*`) gắn vào Gateway `edge`, nhiều hostname trỏ về một Service, chỉ port chính ([ADR-0013](../../../adr/0013-gateway-api-envoy-gateway-shared-edge.md));
  - Job migrate là hook `PreSync`, tắt được cho app không có DB, kèm `migration.image`/`migration.args`. Service Spring dùng chính image của nó với profile `migrate`. `seller-web` dùng một image migrate riêng build từ repo của nó (`FROM flyway/flyway` + `COPY sql/`), vì image Node không chạy được Flyway;
  - Sealed Secret.
- **NetworkPolicy theo app** (Q20). Ingress theo danh sách cho phép ở mọi app (`ingress.from` theo label app/namespace); app có `HTTPRoute` thì chart tự mở thêm nguồn từ pod Envoy của `edge`. Egress mặc định mở, chỉ siết khi app khai báo `egress.to` (seller-web, gateway). Lý do: siết egress cho mọi service thì phải liệt kê Kafka, PG, Keycloak, OTel ở mọi nơi.

### Kafka trong template

- **Retry chặn rồi vào DLT** (Q7): `DefaultErrorHandler` + `ExponentialBackOff` từ 1 s tới 60 s, tổng khoảng 5 phút, sau đó `DeadLetterPublishingRecoverer` ghi vào `<topic>.<group>-dlt`.
- Lỗi vĩnh viễn vào DLT ngay ở lần đầu: deserialize, validate, thiếu `workspaceId`.
- Có alert khi DLT có message mới. Replay ở G1 dùng CLI Kafka theo runbook.
- DLT an toàn với thứ tự vì event mang trạng thái đầy đủ kèm version: bản mới cùng key thay bản trong DLT, và replay bản cũ sẽ bị bỏ qua.
- **Không có inbox ở G1** (Q8). Consumer idempotent bằng mẫu version guard (`WHERE stored_version < :v`). Đây là tài liệu kèm test mẫu, không phải thư viện.

### `libs/service-kit`

- **Một repo, nhiều module, chung một version** (Q12):
  - `workspace-access`: `ScopedValue`, filter HTTP, interceptor Kafka, bản sao Member, hook RLS, cùng `test-fixtures` (test catalog RLS, test PgBouncer).
  - `ids`: UUIDv7.
  - `events`: port publish, bản G1 `AFTER_COMMIT`, cấu hình producer, error handler retry/DLT.
  - `web`: Problem Details, cursor, `Idempotency-Key`, `ETag`/`If-Match`.
  - `test-support`: luật ArchUnit, cấu hình Testcontainers.
  - `gradle-plugin`: convention plugin `commercehub.spring-service` (Groovy precompiled script plugin). Plugin ghim Java 25 và minor Spring Boot, khai báo repository, bật ArchUnit.
- **Không vào lib** (Q13): logic nghiệp vụ, bảng quyền F1.2a, code sinh từ Avro/OpenAPI, UUIDv5 tất định (thuộc `contracts`), version guard, business metric. `service-kit` không phụ thuộc `contracts`; module `events` làm việc với `SpecificRecord` kèm header.
- **Publish lên GitHub Packages** (Q14), cả `service-kit` và `contracts`, Maven lẫn npm:
  - Đọc package cũng cần token.
  - CI dùng `GITHUB_TOKEN`. **Chưa xác minh**: repo này đọc được package của repo kia hay không; nếu không thì dùng classic PAT `read:packages` cất ở secret.
  - MacBook dùng classic PAT trong `~/.gradle/gradle.properties`.
  - Package npm mở "Manage Actions access" cho repo `frontend`.
  - Không viết ADR, vì đổi registry chỉ là sửa URL ở plugin và `settings.gradle`.
  - Đã loại: Maven Central (không xóa được, khoảng 7 release mỗi tháng), Reposilite trong lab (không có npm, mọi build phải vào tailnet), Nexus (8 GB RAM).
- **Version** (Q15):
  - SemVer, publish chỉ từ tag `vX.Y.Z`, không repo nào dùng SNAPSHOT của repo khác.
  - Dependabot bump version lib.
  - Sửa lib và service cùng lúc thì dùng composite build `--include-build ../../libs/service-kit`.
  - Mỗi bản `service-kit` gắn với một minor Spring Boot.
- **Tọa độ** (Q16): groupId `io.github.<user>.commercehub`, package `io.github.<user>.commercehub.<service>`, lib là `….kit.<module>`.

### Quy ước REST (module `web`)

- **Problem Details (RFC 9457)** (Q17):
  - Dùng `ProblemDetail` của Spring.
  - Lỗi HTTP chung (401/404/405/412/428) có `type: about:blank`.
  - Lỗi nghiệp vụ có `type: urn:commerce-hub:problem:<code>` kèm extension `code`.
  - Mọi lỗi có `traceId`; lỗi validate có thêm `errors[]` (`pointer`, `detail`).
  - Danh mục `code` và schema `Problem` nằm trong `contracts/openapi`.
  - Không phải Member thì trả 404.
- **Cursor** (Q18): keyset, base64url của JSON `{v:1, k:[…, id]}`, không ký; cursor hỏng trả 400. `limit` mặc định 50, tối đa 200.
- **`Idempotency-Key`**: chỉ áp cho `POST` tạo mới.
  - Lưu ở bảng `idempotency_key(workspace_id, key, request_hash, status, response, created_at)` trong schema của từng service. Bảng có RLS, migration mẫu đi kèm lib, ghi cùng transaction với thao tác.
  - Giữ 24 giờ. Cùng key khác body trả 422, đang xử lý trả 409.
- **`ETag`**: strong `"<version>"`. `PUT`/`PATCH`/`DELETE` bắt buộc có `If-Match`: thiếu trả 428, lệch version trả 412.

### Secret

- Sealed Secrets theo [gitops-argocd.md](../../../standards/gitops-argocd.md), không viết ADR (Q9). Chi tiết để spec G0.

### Chuyển cho ticket và spec khác

- Ticket 13: composite build, PAT trên Mac (đã comment).
- Frontend (`seller-web`): package npm của `contracts` trên GitHub Packages cần token đọc ở CI và trên Mac; dùng chart `app`.
- Ticket 14: mục 8 arc42 (đã comment).
- Spec G0:
  - chọn plugin sinh code Avro/OpenAPI cho `contracts`;
  - đo RSS với `MaxRAMPercentage=60`;
  - thử đọc package chéo repo bằng `GITHUB_TOKEN`;
  - test N11 với cả một service JPA lẫn một service `JdbcClient`.

## Comments
- 2026-11-12: Từ ticket [04 Ngân sách tài nguyên home lab](04-resource-budget.md#answer): values lab cho mỗi service là `replicaCount: 1`, memory 512Mi (request = limit). Chart vẫn mặc định 2 ([ADR-0004](../../../adr/0004-single-instance-by-default-on-homelab.md)). Với 512Mi, `MaxRAMPercentage=75` nhiều khả năng quá cao (non-heap chỉ còn ~128Mi), nên template cần cho đổi được và spec G0 phải đo RSS.
- 2026-11-12: Từ ticket [08 Giao tiếp giữa service ở G1](08-g1-communication.md#answer): template cần một port publish duy nhất, gọi bên trong `@Transactional`. Bản G1 gửi Kafka ở `AFTER_COMMIT` (cố ý dual-write), bản G2 ghi dòng outbox ([ADR-0005](../../../adr/0005-kafka-from-g1-with-deliberate-dual-write.md)). Consumer idempotent bằng bảng inbox có từ G1. Retry và DLT theo [kafka.md](../../../standards/kafka.md) cần chốt ở ticket này.
- 2026-11-12: Từ ticket [12 Kiến trúc shopee-sim](12-shopee-sim.md#answer): `marketplace-sim` dùng chung template và chart với service, nhưng cần hai thứ mà chart phải cho bật được: một port thứ hai cho admin API, và Ingress có nhiều hostname trỏ về cùng một Service.
- 2026-11-13: Từ ticket [05 Mô hình danh tính và Workspace trong token](05-identity-model.md#answer): `libs/workspace-access` là thư viện dùng chung. Nó đọc topic Member vào bộ nhớ: tự gán mọi partition, không consumer group, đọc từ đầu khi khởi động; readiness chỉ `UP` khi đã tới end offset (không fail-open). Từ `sub` + `X-Workspace-Id` dựng `MemberContext`; không phải Member thì 404. Thư viện chỉ giữ enum Role, kiểu Scope, `MemberContext`; bảng quyền F1.2a mỗi service tự giữ. Gọi giữa service dùng client credentials kèm `X-Workspace-Id` ([ADR-0008](../../../adr/0008-keycloak-authn-only-members-replicated-via-kafka.md)).
- 2026-11-13: Từ ticket [06 Cô lập Workspace ở tầng dữ liệu](06-workspace-isolation.md#answer): `libs/workspace-access` giữ Workspace hiện tại trong một `ScopedValue`, được gắn ở filter HTTP, interceptor consumer Kafka (từ `workspaceId` của envelope) và vòng lặp job. Template cần một hook ở đầu transaction chạy `set_config('app.workspace_id', ?, true)`: thiếu context thì ném exception, không cho đổi Workspace khi transaction đang mở. Điểm hook cụ thể tùy công nghệ persistence mà ticket này chọn. Lib phát hành thêm artifact test-fixtures gồm test catalog (RLS, policy, FK ghép, quyền) và test hành vi qua PgBouncer `transaction`. Lint migration theo [db-migration.md](../../../standards/db-migration.md). Mỗi service có bốn role `_owner`/`_migrator`/`_app`/`_lookup` ([ADR-0010](../../../adr/0010-workspace-isolation-shared-schema-with-mandatory-rls.md)).
- 2026-11-13: Từ ticket [09 Contract và canonical model của G1](09-g1-contracts.md#answer): `libs` cần (1) sinh UUIDv7 cho ID nội bộ và `eventId`; (2) UUIDv5 tất định chỉ dùng trong connector, nhưng namespace và cách nối chuỗi cố định trong `contracts`, kèm test giá trị mẫu ([ADR-0009](../../../adr/0009-deterministic-ids-for-marketplace-entities.md)); (3) envelope event `eventId`, `occurredAt`, `workspaceId`, `traceparent` trong header; (4) quy ước REST: `?cursor=&limit=` trả `nextCursor` opaque, header `Idempotency-Key`, `ETag`/`If-Match` → `412`, mô hình lỗi Problem Details (RFC 9457) chốt ở ticket này. Key Kafka là chuỗi (`StringSerializer`).
- 2026-11-13: Từ ticket [07 Frontend truy cập API](07-frontend-access.md#answer): `seller-web` là Node (Next.js 16, `output: 'standalone'`), không dùng template Spring Boot, nhưng chart cần ba thứ giống service: Job Flyway ở `PreSync` cho DB `seller_web` (role `_owner`/`_migrator`/`_app`, không `_lookup`), Sealed Secret chứa client secret và khóa AES-GCM của phiên (có `key_id` để xoay), và NetworkPolicy cho chiều Keycloak → seller-web (backchannel logout) và seller-web → gateway. Service nhận `traceparent` do BFF gửi ([ADR-0011](../../../adr/0011-nextjs-bff-with-server-side-session.md)).
- 2026-11-13: Sửa theo ticket [16](16-cluster-entry.md#answer): Ingress → HTTPRoute, trust bundle (ADR-0013, ADR-0014).
- 2026-11-13: Từ ticket [18 Gateway ở G1](18-gateway-g1.md#answer): gateway là Spring Cloud Gateway **Server MVC** chạy virtual thread, sinh từ template `hello` nhưng bỏ persistence, Kafka và hook RLS; vẫn dùng `service-kit` và chart `app`. Không rate limit ở G1. Timeout chung `spring.http.clients.*` (connect 2s, read 10s), quá timeout trả 504 Problem Details.
