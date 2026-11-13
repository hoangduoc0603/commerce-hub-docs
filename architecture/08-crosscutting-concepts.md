# 8. Khái niệm xuyên suốt

Mỗi mục tóm tắt quy tắc mà mọi service phải theo, rồi trỏ về nơi quyết định. Chi tiết, phương án đã loại và nguồn nằm ở ADR hoặc ticket được trỏ tới.

## 8.1 Ngôn ngữ chung và domain model

- Thuật ngữ theo [GLOSSARY](../GLOSSARY.md), dùng nguyên trong code, contract và giao diện. Không dùng "tenant" trong định danh; Workspace là `workspace_id` trong DB, `workspaceId` trong event, `app.workspace_id` trong tham số phiên PostgreSQL.
- Thực thể, aggregate và ranh giới nhất quán theo [domain model](../requirements/domain-model.md). Ranh giới nguyên tử của inventory: mọi StockItem mà một Order chạm tới, cùng trạng thái giữ tồn của các Order liên quan ([ADR-0007](../adr/0007-stock-balance-plus-ledger-in-one-transaction.md)).
- Định danh Role trong code: `OWNER`, `MANAGER`, `OPERATOR`, `WAREHOUSE_KEEPER`, `ACCOUNTANT`.

## 8.2 Cô lập Workspace

Quyết định: [ADR-0010](../adr/0010-workspace-isolation-shared-schema-with-mandatory-rls.md). Checklist migration và policy: [db-migration.md](../standards/db-migration.md).

- **Shared schema.** Mọi bảng chứa dữ liệu của Workspace có cột `workspace_id uuid`. Code luôn ghi rõ điều kiện `workspace_id`; RLS là thứ bảo đảm khi code quên.
- **RLS bắt buộc.** Mọi bảng có `workspace_id` bật `ENABLE` và `FORCE ROW LEVEL SECURITY`, policy `FOR ALL` cho mọi role với cùng biểu thức ở `USING` và `WITH CHECK`: `workspace_id = nullif(current_setting('app.workspace_id', true), '')::uuid`. Không role đăng nhập được nào có `BYPASSRLS`.
- **Workspace vào transaction từ ba nguồn**, giữ trong một `ScopedValue` của `workspace-access`:

  | Nguồn | Lấy Workspace từ |
  |---|---|
  | Request HTTP | `MemberContext` (header `X-Workspace-Id` đã kiểm Member), hoặc service account trong danh sách cho phép (F3.3c) |
  | Consumer Kafka | Trường `workspaceId` của envelope. Thiếu thì là lỗi không retry được |
  | Job nền | Vòng lặp qua danh sách Workspace (lấy bằng hàm `_lookup`), mỗi Workspace một transaction |

  Hook ở đầu transaction chạy `set_config('app.workspace_id', ?, true)`, nên đi qua PgBouncer `transaction` vẫn an toàn. Thiếu context thì ném exception. Một transaction chỉ thuộc một Workspace. Truy cập DB ngoài transaction thì fail closed. Workspace cũng được đưa vào MDC và span.
- **Bốn role mỗi database**: `<svc>_owner` (sở hữu object), `_migrator` (chạy Flyway), `_app` (runtime), `_lookup` (`NOLOGIN`, `BYPASSRLS`, chỉ sở hữu hàm `SECURITY DEFINER` trả ID hoặc số đếm cho tra cứu chéo Workspace).
- **FK ghép** `(workspace_id, x_id)`, bảng cha có `UNIQUE (workspace_id, id)`, vì kiểm FK bỏ qua RLS. PK vẫn là `id` UUID toàn cục.
- **Cache trong ứng dụng** phải có Workspace trong key.
- **Ngoại lệ có chủ đích**: bảng `account` của `workspace` (toàn cục), bảng phiên của `seller-web` (thuộc Account, [ADR-0011](../adr/0011-nextjs-bff-with-server-side-session.md)), `marketplace-sim` và Keycloak (ngoài N11).
- **Test N11 ba tầng**, đặt tên `N11_`/`BR04_`: test catalog sau Flyway (đủ RLS, policy đúng mẫu, FK ghép, quyền của role); test hành vi qua container PgBouncer `transaction`; test API ở từng service (ID của Workspace khác trả 404, event sai Workspace không đổi dữ liệu).

## 8.3 Danh tính và phân quyền

Quyết định: [ADR-0008](../adr/0008-keycloak-authn-only-members-replicated-via-kafka.md). Chi tiết Keycloak: [keycloak.md](../standards/keycloak.md).

| Việc | Ở đâu |
|---|---|
| Mật khẩu, xác minh email, phiên, khóa đăng nhập (F1.1a–b, BR-02) | Keycloak, một realm `commerce-hub`. Token chỉ mang `sub`, email, `email_verified` |
| Account trong hệ thống | `workspace`, tạo JIT ở lần gọi `GET /me` đầu tiên |
| Workspace, Member, Role, Scope | `workspace`, phát trạng thái đầy đủ lên `workspace.members` (compact, gỡ Member là tombstone) |
| Workspace đang làm việc | Header `X-Workspace-Id` mỗi request. Chuyển Workspace không đổi token |
| Kiểm JWT | gateway và mọi service |
| Kiểm Member, Role, Scope | Mỗi service, bằng bản sao Member trong bộ nhớ. Mỗi service tự giữ bảng quyền F1.2a cho tài nguyên của mình |

- **Không phải Member, hoặc đối tượng ngoài Scope, thì trả 404**, không trả 403 (BR-04).
- **Scope (F1.2b)**: truy vấn danh sách lọc theo `shop_id ∈ Scope` (Warehouse với Role Kho). Member giữ nhiều Role thì được hợp quyền.
- **Không fail-open**: Kafka không tới được thì pod không ready. Thư viện không gọi `workspace` khi không thấy Member.
- **Gọi giữa service** (chỉ F3.3c ở G1): token client credentials của bên gọi kèm `X-Workspace-Id`. Bên nhận chấp nhận Workspace từ service account trong danh sách cho phép, không kiểm Member, không chuyển tiếp token người dùng. Bút toán ghi người thực hiện là service account, kèm `onBehalfOf` là Member đã chạy job.
- **Tạo Workspace cần claim `email_verified`**. Verify email của realm tắt để không chặn đăng nhập; BFF dùng `kc_action=VERIFY_EMAIL` ([ADR-0011](../adr/0011-nextjs-bff-with-server-side-session.md)).
- **Đặt lại mật khẩu đăng xuất mọi phiên khác** nhờ backchannel logout tới BFF (AC của F1.1b).

## 8.4 Phiên trình duyệt (BFF)

Quyết định: [ADR-0011](../adr/0011-nextjs-bff-with-server-side-session.md). Sự thật về thư viện: [tra cứu 11/2026](../research/2026-11-nextjs-bff-oidc.md).

- **Token chỉ ở server.** Bảng phiên trong database `seller_web`. Access token và refresh token mã hóa AES-GCM, khóa lấy từ Sealed Secret, mỗi dòng ghi `key_id` để xoay khóa. Trình duyệt chỉ có cookie `__Host-session` chứa ID phiên ngẫu nhiên 256 bit.
- **CSRF**: mọi `/api/*` phải có `Sec-Fetch-Site: same-origin`; thiếu header đó thì `Origin` phải trùng origin của app. Sai thì 403. Cookie dùng `Lax` thay vì `Strict` để link trong email không làm mất phiên.
- **Proxy**: chuyển 1:1 `/api/<path>` sang gateway, gắn `Authorization: Bearer`. Header chuyển tiếp theo một danh sách cho phép duy nhất: `Accept`, `Content-Type`, `If-Match`, `If-None-Match`, `X-Workspace-Id`, `Idempotency-Key`. Cookie không bao giờ xuống gateway. Problem Details chuyển nguyên về client.
- **Workspace nằm trong URL** `/w/{workspaceId}/…`. BFF không kiểm Member; service trả 404. Query key của TanStack Query chứa `workspaceId`.
- **Refresh**: chủ động khi access token còn dưới 60 giây; tuần tự hóa bằng `SELECT … FOR UPDATE` trên dòng phiên. `invalid_grant` thì xóa phiên và trả 401 `session_expired`. Keycloak không tới được thì trả 503 và giữ phiên.
- **Đăng xuất**: revoke refresh token, xóa phiên, redirect tới `end_session_endpoint`. Backchannel logout từ Keycloak (trong cụm) xóa phiên theo `sid`.
- **SSE ở G2** đi qua BFF; BFF đóng stream khi access token hết hạn, `EventSource` nối lại kèm `Last-Event-ID`. G1 chỉ chốt hướng.

## 8.5 Event và Kafka

Quyết định: [ADR-0005](../adr/0005-kafka-from-g1-with-deliberate-dual-write.md), ticket [09](../.scratch/architecture-g0-g1/issues/09-g1-contracts.md#answer), ticket [11](../.scratch/architecture-g0-g1/issues/11-service-template.md#answer). Checklist: [kafka.md](../standards/kafka.md).

**Topic G1.** Mỗi topic chứa đúng một loại record. Số partition mặc định 6.

| Topic | Record | Phát → nhận | Key | Retention | Version |
|---|---|---|---|---|---|
| `channel.orders` | `ChannelOrderSynced` | connector → order | `orderId` | delete 7 ngày | `channelUpdateTime` |
| `channel.listings` | `ChannelListingSynced` | connector → catalog | `listingId` | delete 7 ngày | `channelUpdateTime` |
| `catalog.listing-mappings` | `ListingMappingChanged` | catalog → order | `listingId` | compact, không tombstone | `mappingVersion` |
| `order.stock-demands` | `OrderStockDemandChanged` | order → inventory | `orderId` | delete 7 ngày | `orderVersion` |
| `inventory.short-orders` | `ShortOrderChanged` | inventory → order | `orderId` | delete 7 ngày | `stateVersion` |
| `workspace.members` | `MemberChanged` | workspace → mọi service | `workspaceId:accountId` | compact, gỡ Member là tombstone | `memberVersion` |

**Quy tắc chung**

- **Trạng thái đầy đủ kèm version.** Mọi event G1 mang trạng thái đầy đủ của một aggregate. Consumer bỏ bản có version cũ hơn bản đang lưu (version guard `WHERE stored_version < :v`). Riêng event của connector lấy `channelUpdateTime` làm version và áp khi **≥** (BR-31), vì sàn có thể đổi dữ liệu mà không tăng `update_time`. Event đặt tên ở thì quá khứ.
- **Envelope**: key là chuỗi. Mỗi record có `eventId` (UUIDv7), `occurredAt`, `workspaceId` (bắt buộc) và field version của aggregate. `traceparent` đi trong header. Không có `eventType` hay `schemaVersion`, vì `TopicRecordNameStrategy` và schema ID đã thay chúng.
- **Schema**: Avro, đăng ký ở Apicurio bằng lệnh của repo `contracts`, không bao giờ `auto.register.schemas`. Tương thích `BACKWARD_TRANSITIVE`, field mới luôn có default. Đổi phá vỡ thì làm topic mới hậu tố `.v2` và phát song song tới khi consumer chuyển xong.
- **Phía phát**:
  - `channel-connector`: gửi, chờ ack (`acks=all`), rồi mới dời checkpoint. Không bao giờ cần outbox, vì sàn là nguồn sự thật và đọc lại được.
  - `order`, `catalog`, `inventory`, `workspace`: domain gọi `publish(event)` bên trong `@Transactional`. Bản G1 gửi ở `AFTER_COMMIT` (cố ý dual-write: hỏng thì mất event, không sinh event ma). Bản G2 ghi dòng outbox trong cùng transaction.
- **Phía nhận**: retry chặn bằng `DefaultErrorHandler` với backoff mũ từ 1 s tới 60 s (tổng khoảng 5 phút), rồi ghi vào `<topic>.<group>-dlt`. Lỗi vĩnh viễn (deserialize, validate, thiếu `workspaceId`) vào DLT ngay. Có alert khi DLT có message mới; replay ở G1 bằng CLI Kafka theo runbook. DLT an toàn với thứ tự vì bản mới cùng key thay bản cũ, và replay bản cũ bị version guard bỏ qua.
- **Không có inbox ở G1.** Inbox quay lại khi có event không mang trạng thái (lệnh, thông báo, từ G2).
- **Offset commit sau commit DB.** Mọi thay đổi do một event gây ra nằm trong một transaction (N16).

**Vá event mất do dual-write.** Topic compact vá được bằng lệnh phát lại: Mapping của một Workspace (catalog, chỉ Platform Admin) và Member của một Workspace (workspace). Topic delete không vá ở G1. Rủi ro đã ghi: dual-write sau commit có thể gửi hai bản cùng key theo thứ tự đảo, và compaction có thể giữ bản cũ hơn; consumer đọc lại từ đầu sẽ thấy trạng thái cũ cho tới khi phát lại. G2 dùng outbox với Debezium gửi theo thứ tự commit nên hết lỗi này.

## 8.6 Canonical model, ID, tiền và thời gian

Quyết định: ticket [09](../.scratch/architecture-g0-g1/issues/09-g1-contracts.md#answer), [ADR-0009](../adr/0009-deterministic-ids-for-marketplace-entities.md).

- **Ranh giới N13.** Contract được mang `marketplace` dạng chuỗi mở (không enum) và các mã sàn dạng chuỗi opaque: `channelOrderId`, `channelStatus`, `channelProductId`, `channelVariantId`. Ngoài connector, không code nào phân tích hay rẽ nhánh theo chúng; chúng chỉ để hiển thị và tìm kiếm. CI của `contracts` chặn field có tên sàn hay khái niệm riêng của sàn (`shopee`, `tiktok`, `ordersn`, `model`…).
- **Trạng thái lạ (BR-33)**: connector gửi `status = null` kèm `channelStatus`; order giữ trạng thái chuẩn hóa cũ. Connector xuất metric `channel_status_unmapped_total{marketplace,status}` có alert.
- **Dòng đơn canonical**: một dòng cho mỗi (Order, Listing). Connector gộp các dòng gốc, cộng `quantity`, `cancelledQuantity`, `lineAmountMinor`.
- **ID tất định (UUIDv5)** cho thực thể có gốc ở sàn, do connector tính: `listingId`, `orderId`, `orderLineId = v5(orderId, listingId)`. Warehouse mặc định: `v5(workspaceId, "default-warehouse")`. Nhờ vậy hai context cùng biết một ID mà không gọi nhau. Thực thể tạo bên trong hệ thống dùng **UUIDv7**.
- **Tiền**: `…Minor: long` cộng `currency` ISO 4217, theo số mũ ISO (VND mũ 0). Áp chung cho Avro, OpenAPI và DB (`bigint`).
- **Thời gian**: luôn UTC. Avro `timestamp-millis`, OpenAPI RFC 3339 có `Z`, DB `timestamptz`. Giao diện hiển thị theo Asia/Ho_Chi_Minh.
- **PII trên event**: `ChannelOrderSynced` mang người nhận (tên, điện thoại, địa chỉ). Topic giữ 7 ngày và DLT 14 ngày, đều ngắn hơn 30 ngày của BR-05. `MemberChanged` không mang email hay tên, vì topic compact giữ vĩnh viễn.

## 8.7 Quy ước REST

Quyết định: ticket [09](../.scratch/architecture-g0-g1/issues/09-g1-contracts.md#answer), [11](../.scratch/architecture-g0-g1/issues/11-service-template.md#answer). Cài đặt trong `service-kit` module `web`.

- **Contract-first**: mỗi service một `openapi/<service>.yaml` trong `contracts`. Không có API nội bộ riêng; F3.3c gọi đúng endpoint công khai "Đặt số tồn".
- **Lỗi**: Problem Details (RFC 9457) bằng `ProblemDetail` của Spring. Lỗi HTTP chung có `type: about:blank`; lỗi nghiệp vụ có `type: urn:commerce-hub:problem:<code>` kèm extension `code`. Mọi lỗi có `traceId`; lỗi validate có `errors[]`. Danh mục `code` nằm trong `contracts/openapi`.
- **Phân trang**: keyset, `?cursor=&limit=`, trả `nextCursor` opaque (base64url của JSON `{v:1, k:[…, id]}`, không ký). `limit` mặc định 50, tối đa 200.
- **`Idempotency-Key`** cho `POST` tạo mới: lưu ở bảng `idempotency_key` của từng service (có RLS), cùng transaction với thao tác, giữ 24 giờ. Cùng key khác body trả 422, đang xử lý trả 409.
- **Optimistic locking**: `ETag` mạnh `"<version>"`; `PUT`/`PATCH`/`DELETE` bắt buộc `If-Match`, thiếu trả 428, lệch trả 412.
- **Gom dữ liệu hai service** (không có REST đọc giữa service): phân trang ở service chính, rồi lấy nhãn theo lô ở service kia (Shop của connector, Master SKU của catalog, StockItem theo `masterSkuIds`). Trình duyệt làm việc này, không phải BFF.

## 8.8 Persistence và migration

Quyết định: [ADR-0003](../adr/0003-shared-postgres-cluster.md), [ADR-0012](../adr/0012-two-persistence-stacks-one-rls-hook.md), [ADR-0007](../adr/0007-stock-balance-plus-ledger-in-one-transaction.md). Checklist: [db-migration.md](../standards/db-migration.md).

- **Một cluster, nhiều database.** `pg-main` (CloudNativePG, PostgreSQL 18) phục vụ mọi service, Keycloak, `seller_web` và `marketplace_sim`. Database per service giữ ở mức logic: mỗi service một database, `REVOKE CONNECT ... FROM PUBLIC`, `pg_hba` theo database × role. Không service nào vào database của service khác.
- **Kết nối**: runtime đi qua Pooler PgBouncer chế độ `transaction`. Job Flyway và Keycloak nối thẳng `pg-main-rw`.
- **Hai công nghệ persistence**: `JdbcClient` với SQL tay cho inventory, order, channel-connector; JPA cho workspace, catalog, marketplace-sim. Service JPA bắt buộc `open-in-view=false`, `ddl-auto=validate`, không second-level cache. Cả hai đặt Workspace ở cùng một `TransactionExecutionListener.afterBegin`.
- **Migration**: Flyway chạy trong Job hook `PreSync` của Argo CD, trước khi rollout. Service Spring dùng chính image của nó với profile `migrate`; `seller-web` dùng image Flyway riêng. Đổi schema theo expand/contract.
- **Ghi đồng thời ở inventory**: READ COMMITTED, `SELECT ... FOR UPDATE`, không dùng `@Version` (retry dồn dập khi flash sale). Thứ tự khóa cho mọi luồng: các `stock_item` theo `(master_sku_id, warehouse_id)`, rồi các `order_inventory_state` theo `order_id`.
- **Bất biến BR-29**: job định kỳ (mặc định 5 phút) chạy `REPEATABLE READ READ ONLY`, so số dư với tổng sổ cái và Reservation `Open`, xuất `inventory_invariant_violations`. Không tự sửa.
- **Race nhập đơn và ghép Listing** ở order: bản sao Mapping có một dòng cho mỗi Listing, kể cả Listing chưa ghép. Nhập đơn lấy `FOR SHARE`, xử lý ghép lấy `FOR UPDATE` trên dòng đó (ticket [08](../.scratch/architecture-g0-g1/issues/08-g1-communication.md#answer)).
- **Backup**: plugin Barman Cloud lên RustFS trên `gw`, `archive_timeout: 1min` (RPO của N10), `ScheduledBackup` hằng ngày giữ 14 ngày. Diễn tập PITR ra cluster mới để đo RTO.

## 8.9 Bảo mật dữ liệu và mạng

- **Secret**: Sealed Secrets trong repo `gitops` ([gitops-argocd.md](../standards/gitops-argocd.md)). Kubeconfig, auth key Tailscale và `.env` không bao giờ vào repo (repo public, [ADR-0006](../adr/0006-public-repos-on-personal-account.md)).
- **NetworkPolicy theo app**, sinh từ chart `app`: ingress theo danh sách cho phép ở mọi app. Egress mặc định mở, chỉ siết ở app khai báo `egress.to` (`seller-web`, `gateway`). Gateway chỉ nhận từ `seller-web`; Keycloak được gọi vào `seller-web` cho backchannel logout. Admin API của simulator chạy port riêng để chặn được bằng NetworkPolicy.
- **Thông tin người mua (N11)**: không có trong log, trace, thông báo lỗi; order che người nhận theo Role ở API. Workspace đi trong baggage, PII thì không ([observability.md](../standards/observability.md)).
- **Token sàn được mã hóa khi lưu (N11)** ở `channel-connector`. Cách mã hóa (khóa, xoay khóa) **chưa chốt**, nằm trong fog của map cùng chi tiết polling của connector.

## 8.10 Observability

Checklist: [observability.md](../standards/observability.md). Ngân sách và cỡ từng thành phần: ticket [04](../.scratch/architecture-g0-g1/issues/04-resource-budget.md#answer).

- **Instrument**: Micrometer Tracing cộng bridge OTel và OTLP exporter (`spring-boot-starter-opentelemetry`), metric qua `micrometer-registry-prometheus`. Không dùng OTel Java agent. `seller-web` dùng OTel Node SDK trong `instrumentation.ts`.
- **Trace (N12)**: propagation W3C. `traceparent` đi qua HTTP (BFF mở server span và gửi xuống gateway; `traceparent` từ trình duyệt bị bỏ) và qua header Kafka (bật observation ở template và listener). Sampling 100% ở lab.
- **Log**: JSON (ECS) ra stdout, có `traceId`, `spanId`, `workspace_id`. Collector đọc và gửi Loki. Nhãn index của Loki chỉ gồm giá trị tĩnh.
- **Business metric tính từ DB**, không đếm trong bộ nhớ: Oversell (số bút toán `caused_oversell`), `inventory_invariant_violations`, `channel_status_unmapped_total`.
- **Stack ở lab**: OTel Collector (DaemonSet), Prometheus, Alertmanager, Loki monolithic, Tempo, Grafana. Trên Mac: profile `obs` của compose chạy `grafana/otel-lgtm`.

Hướng instrument trên là đề xuất của [ticket 01](../.scratch/architecture-g0-g1/issues/01-infra-standards.md#answer) trong `observability.md`, được các ticket sau dùng làm đầu vào (ngân sách ở ticket 04, profile `obs` ở ticket 13). Không có ADR riêng, vì đổi sang OTel agent chỉ là đổi dependency và cấu hình.

## 8.11 Build, artifact và triển khai

Quyết định: ticket [11](../.scratch/architecture-g0-g1/issues/11-service-template.md#answer), [ADR-0001](../adr/0001-polyrepo.md), [ADR-0006](../adr/0006-public-repos-on-personal-account.md). Checklist: [ci-cd.md](../standards/ci-cd.md), [helm-chart.md](../standards/helm-chart.md), [gitops-argocd.md](../standards/gitops-argocd.md), [container-image.md](../standards/container-image.md), [zero-downtime.md](../standards/zero-downtime.md).

- **Build**: Gradle 9 (Groovy DSL), wrapper và version catalog trong từng repo. Convention plugin `commercehub.spring-service` từ `service-kit`.
- **Template**: repo `services/hello`, cũng là service "hello" của G0. Chỉ giữ phần mỏng (skeleton package, `application.yaml`, Dockerfile, `settings.gradle`, workflow gọi reusable workflow). Thứ cần đồng bộ về sau đi qua artifact có version: convention plugin, `service-kit`, chart `app`, reusable workflow.
- **Artifact**: `service-kit` và `contracts` (Maven và npm) publish lên GitHub Packages từ tag `vX.Y.Z`, SemVer. Không repo nào dùng SNAPSHOT của repo khác. Dependabot bump version. Sửa lib cùng service thì dùng composite build.
- **CI**: GitHub Actions trên GitHub-hosted runner; mỗi repo gọi reusable workflow trong `platform`. Push image lên registry ở `gw` qua `tailscale/github-action`. Workflow cho PR từ fork không nhận secret.
- **Chart `app`**: một chart cho mọi workload (service Spring, `marketplace-sim`, `seller-web`). Phần JVM dưới `jvm.enabled` (`MaxRAMPercentage`, lab ghi đè 60 cho pod 512 Mi, đo ở G0). Bật bằng values: port thứ hai, nhiều hostname, Job migrate `PreSync`, Sealed Secret, NetworkPolicy. Mặc định `replicaCount: 2`; values lab đặt 1 ([ADR-0004](../adr/0004-single-instance-by-default-on-homelab.md)).
- **GitOps**: repo service chỉ tạo image; `gitops` quyết định chạy ở đâu và cấu hình gì. Argo CD kéo chart từ registry và values từ `gitops` (multiple sources). CI cập nhật image tag trong `gitops`.

## 8.12 Vòng phát triển và test

Quyết định: ticket [13](../.scratch/architecture-g0-g1/issues/13-dev-loop.md#answer).

- **Hạ tầng dev** là `platform/compose` trên Mac: Kafka KRaft 1 broker, Apicurio 3, PostgreSQL 18 (mỗi service một database kèm bốn role như ở lab), PgBouncer `transaction`, Keycloak. Service chạy trên host với profile `local`. Mac không bao giờ ghi vào hạ tầng lab.
- **Config lấy từ `gitops`**: hai container init đọc bản checkout `../gitops` để áp realm `commerce-hub` và tạo topic giống lab. Đây là lệch [ADR-0001](../adr/0001-polyrepo.md) có chủ đích, chỉ ở dev, ghi lý do ở README của compose.
- **Dữ liệu khởi đầu**: profile `local` của `workspace` tạo idempotent một Account dev, một Workspace, một Member Owner.
- **Phạm vi trên Mac**: một service cộng các service lân cận trực tiếp. Luồng đầy đủ (simulator → connector → catalog/inventory/order → seller-web) kiểm trên lab sau khi deploy.
- **Test tích hợp**: Testcontainers chạy cả trên Mac lẫn CI bằng cùng `./gradlew check`; cấu hình nằm ở `service-kit` module `test-support`. Tag image ghim cùng major.minor với production.
- **Test chart**: `ct install` chạy trên kind trong job CI, dựng rồi bỏ mỗi lần.
- **Đã chốt về test**: test N11 ba tầng (8.2); luật ArchUnit (5.2); test chặn route trùng giữa hai dialect của simulator; bộ test tuân thủ của simulator dựng từ ví dụ trong tài liệu Shopee. Chiến lược test G1 còn lại (Pact, nơi chạy e2e, property-based test cho BR-29) nằm trong fog của map.
