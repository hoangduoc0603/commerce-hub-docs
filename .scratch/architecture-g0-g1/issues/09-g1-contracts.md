# 09 Contract và canonical model của G1

Type: grilling
Status: resolved
Blocked by: 08
Map: [Kiến trúc G0–G1](../map.md)

## Question

Ở G1 tồn tại những event và API nào (tên, service sở hữu, key, version)? Canonical model của Order, Listing, Master SKU, StockItem đủ cho G1 gồm những trường nào, và trường nào là của riêng sàn phải ở lại channel-connector (N13)? Đầu ra là danh sách contract để `/to-spec` viết thành `.avsc`/OpenAPI, không viết file contract ở đây.

## Answer

Chốt ngày 2026-11-13 (người dùng), sau bốn vòng grilling (Q1–Q24). Quyết định khó đảo ngược: [ADR-0009](../../../adr/0009-deterministic-ids-for-marketplace-entities.md), ID tất định. Đầu ra là danh mục dưới đây để `/to-spec` viết thành `.avsc`, AsyncAPI và OpenAPI. Map không viết file contract.

### Nguyên tắc chung

1. **Mọi event G1 mang trạng thái đầy đủ của một aggregate kèm version** (Q1). Consumer bỏ qua bản có version cũ hơn bản đang lưu. Event của connector lấy `channelUpdateTime` làm version và áp khi **≥** (BR-31). Event đặt tên ở thì quá khứ. Với G1, bảng B2 được thay bằng danh mục ở mục "Event".
2. **ID** (Q2, Q23, ADR-0009): thực thể có gốc ở sàn dùng UUIDv5 tất định do connector tính: `listingId`, `orderId`, `orderLineId = v5(orderId, listingId)`. Warehouse mặc định có `warehouseId = v5(workspaceId, "default-warehouse")`. Thực thể tạo bên trong hệ thống dùng UUIDv7.
3. **Ranh giới N13** (Q3):
   - Được đi qua contract: `marketplace` dạng **chuỗi** mở, không dùng enum, để thêm sàn không phải sửa schema của order hay inventory; các chuỗi opaque `channelOrderId`, `channelStatus`, `channelProductId`, `channelVariantId`. Các chuỗi opaque chỉ dùng để hiển thị và tìm kiếm. Ngoài connector, không code nào được phân tích hay rẽ nhánh theo chúng.
   - Ở lại connector: token, `shop_cipher`, `partner_id`, chữ ký, payload gốc, cấu trúc `item_id`/`model_id` (kể cả `model_id = 0`), `pending_terms`, duyệt COD, quy tắc 1 giờ ON_HOLD (AS-02), đơn vị của `update_time`, bảng ánh xạ trạng thái (SRS mục 4.1), cách gộp dòng gốc.
   - BR-33: gặp trạng thái lạ thì connector gửi `status = null` kèm `channelStatus`, và order giữ nguyên trạng thái chuẩn hóa cũ. Cảnh báo cho Platform Admin là metric `channel_status_unmapped_total{marketplace,status}` ở connector cộng một alert Grafana.
   - CI của `contracts` có một check: không tên field nào chứa tên sàn hay khái niệm riêng của sàn (`shopee`, `tiktok`, `ordersn`, `model`…).
4. **Envelope** (Q4):
   - Key là chuỗi (`StringSerializer`).
   - Mỗi record có `eventId` (UUIDv7), `occurredAt`, `workspaceId`, cộng field version riêng của aggregate.
   - `traceparent` đi trong header do OTel gắn.
   - Không có `eventType` hay `schemaVersion`: `TopicRecordNameStrategy` và schema ID đã thay chúng.
   - Dùng `workspaceId`, không dùng `tenantId` (Q24).
5. **Tiền và thời gian** (Q5):
   - Tiền: `…Minor: long` cộng `currency` ISO 4217, theo số mũ ISO (VND mũ 0). Áp chung cho Avro, OpenAPI và DB `bigint`.
   - Thời gian: luôn là UTC. Avro dùng `timestamp-millis`, OpenAPI dùng RFC 3339 có `Z`, DB dùng `timestamptz`.
6. **Dòng đơn canonical** (Q6): một dòng cho mỗi (Order, Listing). connector gộp các dòng gốc, cộng `quantity`, `cancelledQuantity` và `lineAmountMinor`. Chưa xác minh, để spec G2 kiểm khi viết dialect TikTok: TikTok tách `line_items` theo từng đơn vị hàng, còn Shopee có thể có hai dòng cùng `model_id` khi có khuyến mãi kèm. Quyết định đứng vững dù kết quả kiểm thế nào.
7. **Tiến hóa schema** (Q16):
   - Namespace Avro theo context, không mang version.
   - Đổi tương thích theo `BACKWARD_TRANSITIVE`, field mới luôn có default.
   - Đổi phá vỡ thì làm topic mới hậu tố `.v2`, phát song song hai topic cho tới khi consumer chuyển xong.
   - Bố cục repo `contracts`: `avro/<service>/<Record>.avsc`, `asyncapi/<service>.yaml` (mỗi service phát event một file), `openapi/<service>.yaml`.
   - `contracts/README.md` đang ghi `BACKWARD`, phải sửa thành `BACKWARD_TRANSITIVE` (theo `kafka.md`). Việc này làm ở spec.

### Event

Mỗi topic G1 chứa đúng một loại record, nhưng vẫn dùng `TopicRecordNameStrategy`. Số partition mặc định là 6 (`kafka.md`).

| Record | Topic | Luồng | Key | Retention | Version |
|---|---|---|---|---|---|
| `ChannelOrderSynced` | `channel.orders` | connector → order | `orderId` | delete 7 ngày | `channelUpdateTime` |
| `ChannelListingSynced` | `channel.listings` | connector → catalog | `listingId` | delete 7 ngày | `channelUpdateTime` |
| `ListingMappingChanged` | `catalog.listing-mappings` | catalog → order | `listingId` | compact, không có tombstone | `mappingVersion` |
| `OrderStockDemandChanged` | `order.stock-demands` | order → inventory | `orderId` | delete 7 ngày | `orderVersion` |
| `ShortOrderChanged` | `inventory.short-orders` | inventory → order | `orderId` | delete 7 ngày | `stateVersion` |
| `MemberChanged` | `workspace.members` | workspace → mọi service | `workspaceId:accountId` | compact, gỡ Member là tombstone | `memberVersion` |

Field, ngoài envelope:

- **`ChannelOrderSynced`** (canonical Order, Q12, Q7):
  - `orderId`, `shopId`, `marketplace`, `channelOrderId`, `channelStatus`;
  - `status`: enum chuẩn hóa (SRS mục 4.1), có thể null theo BR-33;
  - `cancellationRequested`, `channelCreatedAt`, `channelUpdateTime`;
  - `syncSource`: enum `Poll`, `Backfill`, có default; G2 thêm `Webhook`;
  - `cod`, `totalAmountMinor`, `currency`;
  - `recipient?` gồm `name`, `phone`, `addressText`. order che theo Role ở API (N11). Dữ liệu cá nhân nằm trên topic 7 ngày và trên DLT 14 ngày, đều ngắn hơn 30 ngày của BR-05. Địa chỉ có cấu trúc để G4 thêm;
  - `lines[]`, mỗi dòng gồm `orderLineId`, `listingId`, `channelProductId`, `channelVariantId`, `sellerSku?`, `itemName` (tên lúc đặt, đã gồm biến thể), `quantity`, `cancelledQuantity`, `lineAmountMinor`.

  Chưa có Package (G4), chưa có `paidTime`.
- **`ChannelListingSynced`** (canonical Listing, Q13):
  - `listingId`, `shopId`, `marketplace`, `channelProductId`, `channelVariantId`, `sellerSku?`, `name`, `imageUrl?`, `priceMinor`, `currency`;
  - `status`: enum `Active`, `Inactive` (ẩn, bị khóa, đang duyệt), `Removed` (đã gỡ khỏi sàn, F3.2a);
  - `channelStatus`, `channelStock` (tồn trên sàn lần cuối, dùng cho F3.3c), `channelUpdateTime`.

  catalog áp bản mới khi `channelUpdateTime` ≥ bản đang lưu, vì sàn có thể đổi tồn mà không tăng `update_time`.
- **`ListingMappingChanged`** (Q14): `listingId`, `shopId`, `masterSkuId?` (null nghĩa là chưa ghép hoặc đã bỏ ghép), `mappingVersion` (catalog tăng mỗi lần ghép hoặc bỏ ghép). Không có tombstone, vì Listing bị gỡ khỏi sàn vẫn giữ Mapping.
- **`OrderStockDemandChanged`** (Q11, Q14, ticket 10): `orderId`, `orderVersion`, `lines[]` gồm `orderLineId`, `masterSkuId?`, `quantity`. `quantity` bằng số đặt trừ số đã hủy, và order đặt về 0 khi Order `Cancelled`. Theo BR-18, order là bên quyết định trạng thái nào giữ tồn, nên inventory không cần hiểu trạng thái đơn. Không có `warehouseId`: inventory dùng Warehouse mặc định (Q10). P1 thêm field có default null.
- **`ShortOrderChanged`** (ticket 10): `orderId`, `short`, `stateVersion`.
- **`MemberChanged`** (Q21, Q22, ADR-0008):
  - `accountId` (`sub` của Keycloak), `memberVersion`;
  - `roles[]`: enum `OWNER`, `MANAGER`, `OPERATOR`, `WAREHOUSE_KEEPER`, `ACCOUNTANT`;
  - `shopScope` (chỉ có nghĩa với `OPERATOR`) và `warehouseScope` (chỉ có nghĩa với `WAREHOUSE_KEEPER`), mỗi scope dạng `{ all: boolean, ids: [uuid] }`.

  Không mang email hay tên, để PII không nằm vĩnh viễn trên topic compact.

**Không có ở G1**: `MasterSkuChanged`, `AvailabilityChanged`, `ShopConnected`, `WorkspaceCreated`. Lý do:
- Nhãn Master SKU được lấy theo lô qua REST (Q8).
- Warehouse mặc định có ID tất định (Q23).
- Danh sách Shop đọc qua REST của connector (ticket 08).

**Vá event mất do dual-write** (Q15): topic compact vá được bằng lệnh phát lại. G1 có hai lệnh như vậy: phát lại Mapping của một Workspace ở catalog (chỉ Platform Admin gọi được), và phát lại Member ở `workspace` (ADR-0008). Topic delete thì không vá ở G1 (ADR-0005).

**Rủi ro ghi lại, không cần quyết thêm**: dual-write sau commit có thể gửi hai lần sửa liền nhau của cùng một key theo thứ tự đảo ngược. Field version chặn được việc này ở consumer đang chạy. Nhưng compaction giữ bản ghi sau cùng, có thể là bản cũ hơn, nên consumer đọc lại từ đầu (bản sao Member khi pod khởi động, bản sao Mapping của order) có thể thấy trạng thái cũ. Ở G1, lệnh phát lại là cách vá. G2 dùng outbox với Debezium gửi theo thứ tự commit, nên hết lỗi này.

### API REST

Đây là mức tài nguyên (Q17). Endpoint cụ thể để `/to-spec` viết. FE gọi thẳng qua gateway hay đi qua BFF thì ticket 07 quyết.

| Service | Tài nguyên G1 |
|---|---|
| `workspace` | Account (`GET /me`, tạo JIT), Workspace, Member, Role, Scope (F1.1a–c, F1.2a–b), theo ticket 05; phát lại Member |
| channel-connector | Shop (danh sách, lấy theo lô); bắt đầu kết nối (trả URL ủy quyền); OAuth callback (F2.1a); tiến độ job kéo dữ liệu (F2.4a) |
| catalog | Master SKU (tạo, sửa, archive, tìm kiếm, lấy theo lô; F3.1a); Listing (lọc theo Shop hoặc chưa ghép, số đếm chưa ghép); `PUT`/`DELETE /listings/{id}/mapping` (F3.3b); job F3.3c (tạo, tiến độ, chạy lại phần lỗi); phát lại Mapping |
| inventory | StockItem (danh sách, lọc Available < 0, lấy theo lô theo `masterSkuIds`); "Đặt số tồn" (CAS trên `expectedOnHand`, lệch thì `409`); "Điều chỉnh"; lịch sử bút toán của một SKU, lọc theo thời gian và loại (F4.3a) |
| order | Danh sách đơn (cursor, bộ lọc F5.1a, số đếm theo trạng thái); chi tiết đơn (che người nhận theo N11) |
| marketplace-sim | Admin API (ticket 12) |

- **Không có API nội bộ riêng** (Q9). F3.3c gọi đúng endpoint "Đặt số tồn" với:
  - `expectedOnHand = 0` (StockItem chưa tồn tại thì On hand là 0);
  - `Idempotency-Key = f33c:<jobId>:<masterSkuId>`;
  - lý do `Lấy từ sàn`, chỉ hệ thống dùng (Q20, SRS F4.1b);
  - token client credentials (ADR-0008). Bút toán ghi người thực hiện là service account, kèm `onBehalfOf` là Member đã chạy job, truyền qua header.
- **Gom dữ liệu từ hai service** (Q8): phân trang ở service chính, rồi lấy nhãn theo lô ở service kia. Lọc Available < 0 thì phân trang ở inventory. Tìm theo mã hoặc tên Master SKU thì phân trang ở catalog.
- **Quy ước** (Q18):
  - Phân trang bằng `?cursor=&limit=`, trả về `nextCursor` opaque.
  - Lệnh ghi không tự nhiên idempotent thì nhận `Idempotency-Key`.
  - Sửa Master SKU dùng `ETag` cộng `If-Match`, lệch thì trả `412` (F3.1a).
  - Không phải Member, hoặc đối tượng ngoài Scope, thì trả `404` (ADR-0008).
  - Mô hình lỗi Problem Details (RFC 9457) do ticket 11 chốt.

### Đã sửa tài liệu nguồn

- SRS 1.3:
  - BR-17: "mỗi Workspace luôn có đúng một Warehouse mặc định", inventory tạo nó lúc lần đầu chạm tới Workspace (Q19);
  - F4.1b: thêm lý do hệ thống `Lấy từ sàn` (Q20).
- Domain model 1.2: mỗi (Order, Listing) có tối đa một OrderLine; trạng thái canonical của Listing; ID của Warehouse mặc định.
- GLOSSARY:
  - định danh trong code của Role (Q22);
  - _Avoid_ "tenant" cả trong định danh code (Q24).
- **Đổi tên service `tenant` thành `workspace`** (Q24) ở mọi tài liệu. Định danh `tenant_id`, `tenantId`, `app.tenant_id` đổi thành `workspace_id`, `workspaceId`, `app.workspace_id`. Chỉ giữ "tenant" trong các từ ghép kiến trúc: multi-tenant, multi-tenancy, schema-per-tenant.

### Để cho ticket khác

- Ticket 07: gom dữ liệu từ hai service và các endpoint lấy theo lô (đã ghi comment).
- Ticket 11: thư viện sinh UUIDv7 và UUIDv5, Problem Details, `Idempotency-Key`, định dạng cursor (đã ghi comment).
- Ticket 14: danh mục contract này là nguồn cho arc42 mục 8 (đã ghi comment).
- Pipeline publish contract: còn trong fog của map, chờ ticket 11.

## Comments
- 2026-11-12: Từ ticket [08 Giao tiếp giữa service ở G1](08-g1-communication.md#answer): bảng luồng G1 cần đặt tên event và key. Gồm: Order đã chuẩn hóa (connector → order), Listing đã kéo về (connector → catalog), ghép và bỏ ghép Listing (catalog → order), dòng đơn kèm Master SKU (order → inventory), Short order bật/tắt (inventory → order). Thêm một lệnh REST nội bộ: khai báo tồn ban đầu (catalog → inventory), idempotent theo (job, Master SKU). Avro và Schema Registry có ngay từ G1 ([ADR-0005](../../../adr/0005-kafka-from-g1-with-deliberate-dual-write.md)).
- 2026-11-12: Từ ticket [12 Kiến trúc shopee-sim](12-shopee-sim.md#answer): thêm OpenAPI của **admin API simulator** (tạo App, Shop, seed Listing, tạo và chuyển trạng thái đơn, "hết hạn ngay", ghi đè AS-xx) vào danh sách contract. **Không** viết OpenAPI cho API của Shopee: connector và simulator mỗi bên tự cài đặt từ tài liệu chính thức.
- 2026-11-13: Từ ticket [10 Mô hình ghi của inventory ở G1](10-inventory-write-model.md#answer): event order → inventory mang **trạng thái đích của cả Order** (mọi dòng `orderLineId`, `masterSkuId` hoặc null, `qty` = đặt − đã hủy), kèm `orderVersion`. `orderVersion` là version aggregate do order tự tăng, không phải `update_time` của sàn. Event không mang lệnh delta. Event Short order inventory → order mang trạng thái `(orderId, short, stateVersion)`, không mang lệnh bật/tắt.
- 2026-11-13: Từ ticket [05 Mô hình danh tính và Workspace trong token](05-identity-model.md#answer): thêm vào danh sách contract **event Member** do `tenant` (nay là `workspace`) phát lên một topic **compacted**. Key theo (Workspace, Account `sub`); value là trạng thái đầy đủ (các Role, mỗi Role kèm Scope); gỡ Member là tombstone. Gửi lại phải idempotent ([ADR-0008](../../../adr/0008-keycloak-authn-only-members-replicated-via-kafka.md)).
- 2026-11-13: Từ ticket [06 Cô lập Workspace ở tầng dữ liệu](06-workspace-isolation.md#answer): envelope chung của mọi event có trường **bắt buộc** `workspaceId` (không dùng `tenantId`). Consumer coi event thiếu trường này là lỗi không retry được ([ADR-0010](../../../adr/0010-workspace-isolation-shared-schema-with-mandatory-rls.md)).
