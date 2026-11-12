# commerce-hub: yêu cầu, tính năng và kỹ thuật áp dụng

Tài liệu nền cho dự án commerce-hub, một hệ thống quản lý bán hàng đa kênh (multi-channel OMS). Hệ thống giúp nhà bán quản lý một kho sản phẩm và tồn kho chung, gom đơn hàng từ TikTok Shop, Shopee và kênh riêng về một nơi, đồng bộ trạng thái hai chiều.

> **Trạng thái (12/11/2026).** Yêu cầu của hệ thống (người dùng, tính năng, yêu cầu phi chức năng) nằm ở [SRS](requirements/srs.md), thuật ngữ ở [GLOSSARY](GLOSSARY.md). Tài liệu này giữ phần đặc điểm các sàn, thiết kế tổng quan và kỹ thuật, làm đầu vào cho phase thiết kế. Chỗ nào khác với SRS thì theo SRS. Ví dụ: tenant được gọi là Workspace, carrier-sim chuyển sang P1, tồn được giữ ngay cả với đơn chưa thanh toán ([ADR-0002](adr/0002-reserve-stock-on-first-sight.md)).

Tài liệu có ba phần:

- **Phần A: Bài toán.** Đặc điểm các sàn ảnh hưởng tới thiết kế (A2).
- **Phần B: Thiết kế.** Chia service, event, luồng chính.
- **Phần C: Kỹ thuật.** Từng nhóm kỹ thuật backend, microservice, event-driven, vận hành: dùng ở phần nào và vì sao. Cuối phần là ma trận kỹ thuật theo service, chiến lược giả lập, lộ trình.

> **Độ tin cậy nguồn.** Thông số về sàn (thời hạn token, webhook, trạng thái đơn, giới hạn API) được tra từ tài liệu chính thức của TikTok Shop Partner Center và Shopee Open Platform vào tháng 11/2026. Chỗ nào không xác nhận được thì ghi rõ **chưa xác minh**. Danh sách tính năng tổng hợp từ trang sản phẩm công khai của Sapo, BigSeller, Ginee, Nhanh.vn, Pancake, KiotViet, Haravan, Linnworks, ChannelEngine, Sellercloud, Zoho Inventory. Đó là tài liệu marketing, chưa có kiểm chứng độc lập. Tài liệu sàn thay đổi theo tháng, nên trước khi code adapter thật phải tra lại.

---

# Phần A: Bài toán

> Người dùng, kênh bán và thuật ngữ: xem [SRS mục 2.2](requirements/srs.md#22-người-dùng) và [GLOSSARY](GLOSSARY.md).

## A2. Đặc điểm các sàn ảnh hưởng tới thiết kế

Đây là phần quan trọng nhất của Phần A. Phần lớn độ khó kỹ thuật của hệ thống đến từ những đặc điểm dưới đây, và simulator phải tái hiện được chúng.

### Ủy quyền và token

| | TikTok Shop | Shopee |
|---|---|---|
| Mã ủy quyền | `auth_code` dùng 1 lần, hết hạn sau 30 phút | `code` dùng 1 lần, hết hạn sau 10 phút |
| Access token | Mặc định 7 ngày. `access_token_expire_in` là **Unix timestamp**, không phải số giây | **4 giờ** (`expire_in` tính bằng giây) |
| Refresh token | Hạn bằng thời gian nhà bán cấp quyền. Có xoay vòng hay không: **chưa xác minh** | 30 ngày, **xoay vòng**: mỗi lần refresh nhận refresh token mới; access token cũ còn hiệu lực thêm 5 phút |
| Thời hạn ủy quyền | Tối đa: chưa xác minh | Tối đa 365 ngày |
| Báo sắp hết hạn | Webhook `UPCOMING_AUTHORIZATION_EXPIRATION`: trước 30 ngày, rồi mỗi ngày lúc 00:00 | Push `open_api_authorization_expiry` (code 12), trước 7 ngày |
| Thu hồi | Webhook `SELLER_DEAUTHORIZATION` | Push `shop_authorization_canceled_push` (code 2) |
| Ký request | HMAC-SHA256(`app_secret`, `app_secret + path + các query param đã sort + body + app_secret`). Access token gửi qua header `x-tts-access-token`. `timestamp` không cũ hơn 5 phút, không sớm hơn 30 giây | HMAC-SHA256(`partner_key`, `partner_id + api_path + timestamp + access_token + shop_id`). Không ký body. `timestamp` trong vòng 5 phút |

**Hệ quả thiết kế:**

- **Refresh token xoay vòng là bẫy concurrency.** Hai pod cùng refresh token của một shop Shopee: pod nào đến sau sẽ dùng refresh token đã bị thay, và shop đó **mất kết nối**. Việc refresh phải là **single-flight** cho từng shop: distributed lock hoặc một owner duy nhất cho mỗi shop. Xem C5.3.
- Token Shopee 4 giờ hết hạn một lần. Với hàng nghìn shop, cần **scheduler refresh chủ động** trước khi hết hạn, không đợi gặp lỗi 401.
- Lệch đồng hồ quá 5 phút thì mọi request đều bị từ chối. Cần NTP trên node và metric clock skew.

### Webhook (push notification)

| | TikTok Shop | Shopee |
|---|---|---|
| Phải trả lời | HTTP 200, body rỗng, **trong 3 giây** | HTTP 2xx, body rỗng, **trong 3 giây** |
| Retry khi lỗi | Sau 2 phút → 30 phút → 3 giờ → 12 giờ, rồi dừng | Sau 300 s → 1800 s → 10800 s |
| Đảm bảo giao | **At-least-once.** Dedupe theo `tts_notification_id`. Không cam kết thứ tự. Tài liệu nói rõ webhook chỉ là "tín hiệu thay đổi", API mới là nguồn sự thật | **Không đảm bảo thứ tự** ("Sequence Guaranteed: No"), **có thể trùng** ("Can Repeated Same Message: Yes") |
| Chữ ký | Header `Authorization` = hex(HMAC-SHA256(`app_secret`, `app_key + raw_body`)) | Header `Authorization` = hex(HMAC-SHA256(`partner_key`, `callback_url + "\|" + raw_body`)) |
| Nội dung | `{type, tts_notification_id, shop_id, timestamp, data}`. Ví dụ đơn: `{order_id, order_status, update_time, is_on_hold_order}` | Chỉ báo có thay đổi, phải gọi API lấy chi tiết. Ví dụ `order_status_push`: `{ordersn, status, completed_scenario, update_time}` |
| Phạt khi endpoint yếu | Chưa xác minh | Nếu > 600 push trong 6 giờ mà tỷ lệ thành công < 70% thì gửi email cảnh báo; < 30% thì **tắt subscription**, push bị lỡ **không gửi lại** |

Các loại event chính:

- **TikTok:** `ORDER_STATUS_CHANGE`, `PACKAGE_UPDATE` (gộp/tách kiện), `RECIPIENT_ADDRESS_UPDATE`, `CANCELLATION_STATUS_CHANGE`, `RETURN_STATUS_CHANGE`, `REVERSE_STATUS_UPDATE`, `PRODUCT_STATUS_CHANGE`, `PRODUCT_AUDIT_STATUS_CHANGE`, `SELLER_DEAUTHORIZATION`, `UPCOMING_AUTHORIZATION_EXPIRATION`, tin nhắn chat.
- **Shopee:** `order_status_push` (3), `order_trackingno_push` (4), `shipping_document_status_push` (15), `reserved_stock_change_push` (8), `violation_item_push` (6), `item_promotion_push` (7), `promotion_update_push` (9), `webchat_push` (10), push về ủy quyền (1, 2, 12).

**Hệ quả thiết kế:**

- Endpoint nhận webhook phải **cực nhanh và cực sẵn sàng**. Chỉ xác thực chữ ký, ghi bền (Kafka) rồi trả 200, không xử lý nghiệp vụ trong request. Nếu endpoint yếu, Shopee tắt subscription và push bị lỡ mất hẳn.
- Phải **dedupe** và **chịu được sai thứ tự**: so `update_time` hoặc version, không tin thứ tự đến.
- Webhook không đủ tin cậy, nên bắt buộc có **polling bù** (reconciliation) theo `update_time`.

### Vòng đời đơn hàng

| TikTok Shop | Shopee |
|---|---|
| `UNPAID` → `ON_HOLD` (người mua còn được hủy tự do) → `AWAITING_SHIPMENT` → `PARTIALLY_SHIPPING` → `AWAITING_COLLECTION` → `IN_TRANSIT` → `DELIVERED` → `COMPLETED` (hết quyền hoàn trả); `CANCELLED` | `UNPAID` → (`PENDING`, chỉ trả về khi bật `request_order_status_pending`) → `READY_TO_SHIP` → `PROCESSED` (đã có mã vận đơn) → `RETRY_SHIP` (lấy hàng thất bại) → `SHIPPED` → `TO_CONFIRM_RECEIVE` → `COMPLETED`; `IN_CANCEL` → `CANCELLED`; `TO_RETURN` |
| Hủy: `CANCELLATION_REQUEST_PENDING / _SUCCESS / _CANCEL / _COMPLETE` | Hủy: `cancel_order` (nhà bán hủy), `handle_buyer_cancellation` (duyệt yêu cầu hủy ở `IN_CANCEL`) |
| Hoàn trả: loại `REFUND`, `RETURN_AND_REFUND`, `REPLACEMENT`; 9 trạng thái từ `RETURN_OR_REFUND_REQUEST_PENDING` tới `_COMPLETE`, kèm tranh chấp (arbitration) | Hoàn trả: `REQUESTED`, `ACCEPTED`, `CANCELLED`, `JUDGING`, `PROCESSING`, `SELLER_DISPUTE`, `CLOSED`. `completed_scenario=RRAOC` là yêu cầu trả hàng sau khi đơn đã hoàn tất |

Sơ đồ chuyển trạng thái chính xác của Shopee là ảnh trong tài liệu, chưa đọc được: **chưa xác minh**.

**Hệ quả thiết kế:**

- Cần **canonical order status** và bảng ánh xạ cho từng sàn (anti-corruption layer).
- TikTok `ON_HOLD`: **chưa được xử lý giao hàng** cho tới `AWAITING_SHIPMENT`. Có nên giữ tồn kho ngay từ `ON_HOLD` không? Nên giữ, để tránh oversell. Đây là quyết định cần ghi thành ADR.
- Trạng thái có thể "lùi" về mặt logic (đơn đã hoàn tất vẫn phát sinh trả hàng), nên state machine phải cho phép những chuyển trạng thái này.

### Giao hàng

- **TikTok:** đơn vị giao hàng là **package**, không phải order. Sàn có thể gộp hoặc tách kiện (webhook `PACKAGE_UPDATE`). `shipping_type` có `TIKTOK` (sàn lo vận chuyển, in nhãn từ sàn) và `SELLER` (nhà bán tự gửi rồi cập nhật tracking). `POST /fulfillment/202309/packages/{id}/ship` gọi lần hai trả lỗi 11006021.
- **Shopee:** một đơn có thể tách thành nhiều kiện (`split_order`, chỉ ở `READY_TO_SHIP`, tối đa 5 kiện ngoài TW). Luồng: `get_shipping_parameter` (pickup, dropoff hay non-integrated) → `ship_order`/`mass_ship_order` → lấy tracking number (có thể đến muộn, qua `order_trackingno_push`) → tạo vận đơn bất đồng bộ qua 4 bước (`create_shipping_document` → poll `get_shipping_document_result` hoặc chờ push → `download_shipping_document`). Chỉ in được trước `LOGISTICS_PICKUP_DONE`.

**Hệ quả thiết kế:** có thực thể `Package`/`Shipment` tách khỏi `Order`. In vận đơn là **job bất đồng bộ nhiều bước**. Thao tác ship phải **idempotent**.

### Sản phẩm và tồn kho

- **TikTok:** product → SKU (tối đa 100 SKU/product), tồn kho là danh sách `{warehouse_id, quantity}`, giá trị 0–999.999. Từ tháng 10/2026 có chế độ cập nhật đa kho INCREMENTAL (khuyến nghị) và FULL. Sửa sản phẩm phải qua duyệt (`AUDITING`), và trong lúc chờ duyệt vẫn có đơn về theo SKU cũ. `external_product_id` dùng làm idempotency key khi tạo sản phẩm. Ảnh phải upload lên sàn trước.
- **Shopee:** item → model (qua `tier_variation`). `update_stock` nhận 1–50 model mỗi lần, có `location_id` cho đa kho. Không được trộn cấu trúc có và không có `location_id`.
- **Cả hai sàn từ chối cập nhật tồn kho nếu số mới nhỏ hơn số đang giữ cho khuyến mãi/campaign.**

**Hệ quả thiết kế:** tồn kho đẩy lên sàn phải tính tới phần khuyến mãi đang giữ. Lỗi "từ chối cập nhật" là chuyện thường ngày, phải có trạng thái lỗi cho từng listing và hiển thị cho người dùng.

### Giới hạn API và đồng bộ tăng dần

| | TikTok Shop | Shopee |
|---|---|---|
| Rate limit | **Động**, không công bố QPS cố định. Đơn vị cô lập: **app × shop**, thêm giới hạn app × endpoint. Bị chặn: HTTP 429 và/hoặc mã 36009002, có thể có `Retry-After`. Gợi ý khởi điểm: ghi nặng 0,2–1 req/s, ghi thường 1–3, đọc 3–10, đọc batch 5–20 | HTTP 429. App liên tục retry khi bị giới hạn có thể **bị hạn chế**, phải mở ticket mới gỡ. QPS cụ thể: **chưa xác minh** |
| Lấy danh sách đơn | `POST /order/202309/orders/search`, cursor `page_token`, tối đa 100/trang, lọc theo `update_time`. Tài liệu cảnh báo `update_time` có thể vượt khoảng tìm kiếm, nên **cửa sổ phải chồng lên nhau** | `get_order_list` chỉ trả `order_sn`, **khoảng thời gian tối đa 15 ngày**, cursor; sau đó `get_order_detail` tối đa **50 đơn/lần**. Từ 05/11/2026 có field `warning` khi hệ thống sàn quá tải |
| Phiên bản API | Đặt tên YYYYMM, nằm trong path; bản cũ còn dùng ≥ 2 tháng sau khi có bản mới | v2 |

**Hệ quả thiết kế:** rate limiter phân tán theo khóa (sàn, app, shop, nhóm endpoint). Hàng đợi có **độ ưu tiên** (xác nhận giao hàng > cập nhật tồn kho > đăng sản phẩm hàng loạt). **Fairness giữa các Workspace**. Đồng bộ tăng dần với checkpoint và cửa sổ chồng lấn. Gom request theo batch (50 đơn, 50 model).

## A3, A4. Yêu cầu chức năng và phi chức năng

Đã chuyển sang [SRS](requirements/srs.md): yêu cầu P0 ở chương 3, danh sách P1/P2 ở chương 6, yêu cầu phi chức năng ở chương 7. Mã tính năng (F1.1, F4.2…) và mã NFR (N1…) được giữ nguyên, nên các tham chiếu trong Phần B và C vẫn tra được trong SRS.

---

# Phần B: Thiết kế tổng quan

## B1. Bounded context và service

```
                         Next.js (seller app, admin)
                                   │
                    Spring Cloud Gateway ─── Keycloak (OIDC)
   ┌──────────┬───────────┬────────┼──────────┬────────────┬────────────┐
workspace  catalog    inventory  order    fulfillment   reporting   notification
   │          │           │        │          │            │            │
   └──────────┴───────────┴── Kafka (event backbone) ─────┴────────────┘
                                   │
                ┌──────────────────┴──────────────────┐
         channel-connector                      webhook-ingress
   (gọi API sàn: token, rate limit,        (nhận push: verify chữ ký,
    sync, adapter từng sàn)                 ghi Kafka, trả 200 ngay)
                │                                     ▲
                ▼                                     │
      ┌─────────────────── simulators ────────────────┴──┐
      │  tiktok-sim · shopee-sim · carrier-sim           │
      └──────────────────────────────────────────────────┘
```

| Service | Trách nhiệm | Dữ liệu sở hữu | Lưu trữ |
|---|---|---|---|
| **gateway** | Định tuyến, xác thực JWT, rate limit theo Workspace, CORS | — | Redis (rate limit) |
| **workspace** | Workspace, Account, Member, vai trò, gói dịch vụ, hạn mức | workspace, account, member, plan, quota usage | PostgreSQL |
| **channel-connector** | Kết nối shop, token, gọi API sàn, rate limit sàn, đồng bộ tăng dần, chuyển dữ liệu sàn ↔ canonical | shop connection, encrypted token, sync checkpoint, outbound job | PostgreSQL + Redis |
| **webhook-ingress** | Nhận push, kiểm chữ ký, ghi Kafka, trả 200 | — (không có DB, chỉ dedupe ngắn hạn) | Redis |
| **catalog** | Master product/SKU, combo, listing, mapping, job đăng sản phẩm | product, sku, listing, mapping | PostgreSQL (+ OpenSearch cho tìm kiếm) |
| **inventory** | Kho, sổ cái tồn, reservation, quy tắc phân bổ, tính published stock | warehouse, stock ledger, reservation, allocation rule | PostgreSQL + Redis |
| **order** | Đơn canonical, state machine, điều phối saga xử lý đơn, hủy, hoàn trả | order, order line, order history | PostgreSQL |
| **fulfillment** | Package, shipment, vận đơn, adapter hãng vận chuyển, tracking | package, shipment, label job | PostgreSQL + MinIO (PDF) |
| **reporting** | Read model cho dashboard và báo cáo | projection | ClickHouse (+ Kafka Streams) |
| **notification** | Thông báo trong app (SSE), email; sau này là webhook ra | notification, delivery log | PostgreSQL |

Vài quyết định cần làm rõ (mỗi cái nên có một ADR):

- **Vì sao tách webhook-ingress khỏi channel-connector?** Hai việc có yêu cầu vận hành ngược nhau. Ingress cần độ trễ thấp, ổn định, không phụ thuộc gì (để không bị sàn tắt subscription). Connector thì chậm, phụ thuộc sàn, hay bị rate limit. Tách ra để scale và deploy độc lập, và để connector có sập thì ingress vẫn nhận push.
- **Vì sao inventory tách khỏi catalog?** Tồn kho có tần suất ghi cao và yêu cầu nhất quán chặt. Catalog ít ghi, đọc nhiều. Gộp lại thì lock của tồn kho ảnh hưởng tới catalog.
- **Ranh giới canonical:** chỉ channel-connector biết khái niệm của từng sàn (`ordersn`, `shop_cipher`, `model_id`). Mọi service khác chỉ thấy model canonical.
- **Không bắt đầu với đủ 10 service.** Giai đoạn 1 có thể gộp workspace vào gateway/Keycloak, gộp reporting vào order. Tách ra khi có lý do (xem lộ trình C18).

## B2. Event chính

Đặt tên theo quá khứ (việc đã xảy ra). Key là khóa partition Kafka, quyết định thứ tự.

> Bảng dưới là gợi ý ban đầu. Danh mục event của Giai đoạn 1 (event mang trạng thái đầy đủ kèm version, tên, topic, key) đã chốt ở [ticket 09 của map kiến trúc G0–G1](.scratch/architecture-g0-g1/issues/09-g1-contracts.md#answer) và thay bảng này cho G1.

| Event | Producer | Consumer | Key |
|---|---|---|---|
| `ChannelNotificationReceived` (thô, đã verify chữ ký) | webhook-ingress | channel-connector | `shopId` |
| `ShopConnected` / `ShopAuthorizationExpired` / `ShopDisconnected` | channel-connector | catalog, order, notification | `shopId` |
| `ChannelOrderSynced` (đã chuẩn hóa, kèm `channelUpdateTime`) | channel-connector | order | `channel:orderId` |
| `OrderImported` / `OrderStatusChanged` / `OrderCancelled` | order | inventory, fulfillment, reporting, notification | `orderId` |
| `StockReserved` / `StockReservationFailed` / `StockReleased` / `StockDeducted` | inventory | order | `orderId` |
| `AvailabilityChanged` (available mới của một master SKU) | inventory | channel-connector, catalog, reporting | `skuId` |
| `ListingStockPushRequested` (đã gom, theo listing) | channel-connector (nội bộ) | channel-connector worker | `shopId` |
| `ListingSyncFailed` | channel-connector | notification, catalog | `listingId` |
| `ShipmentArranged` / `TrackingNumberAssigned` / `LabelReady` / `ShipmentDelivered` | fulfillment | order, channel-connector, notification | `orderId` |
| `ListingMapped` / `ProductPublished` | catalog | inventory, channel-connector | `skuId` / `listingId` |
| `ReturnRequested` / `ReturnReceived` | order | inventory, reporting | `orderId` |

Topic gợi ý: mỗi aggregate một topic (`order.events`, `inventory.events`, ...), event có envelope chung: `eventId`, `eventType`, `occurredAt`, `workspaceId`, `aggregateId`, `aggregateVersion`, `traceparent`, `schemaVersion`.

## B3. Luồng chính

### Luồng 1: Đơn mới từ Shopee, đồng bộ tồn sang TikTok

```
shopee-sim ──push──▶ webhook-ingress ── verify HMAC, dedupe nhanh ──▶ Kafka: ChannelNotificationReceived ──▶ (trả 200)
                                                                    │
channel-connector ◀─────────────────────────────────────────────────┘
   │ rate limiter (shopee, app, shop)  →  get_order_detail (batch ≤ 50)
   ▼
 ChannelOrderSynced ──▶ order: upsert theo (channel, orderId); bỏ qua nếu channelUpdateTime cũ hơn
                         │ map trạng thái → canonical; nếu đơn mới: OrderImported (qua outbox)
                         ▼
                    inventory: reserve theo SKU (idempotent theo orderId) → StockReserved
                         │ tính lại available → AvailabilityChanged(skuId)
                         ▼
               channel-connector: tìm mọi listing gắn SKU → áp quy tắc phân bổ
                         │ gom (coalesce) theo listing trong 1–2 s → rate limiter → update_inventory (TikTok)
                         ▼
                    tiktok-sim nhận số tồn mới  ⇒ đo stock_sync_lag
```

### Luồng 2: Xử lý đơn (saga do order điều phối)

```
OrderImported → [reserve tồn] → (đơn sang trạng thái sẵn sàng giao trên sàn) → [arrange shipment ở fulfillment]
  → [lấy tracking] → [đẩy tracking/ship lên sàn qua connector] → [tạo vận đơn PDF] → ReadyToPack
Bù khi lỗi:
  - Hết hàng (StockReservationFailed) → đánh dấu đơn "thiếu hàng", báo người dùng (không tự hủy trên sàn)
  - Người mua hủy giữa chừng → release tồn, hủy shipment nếu đã tạo
  - Ship lên sàn lỗi vĩnh viễn → hủy shipment ở hãng, đưa đơn về hàng chờ xử lý tay
```

### Luồng 3: Đối soát (reconciliation)

```
Mỗi N phút, cho từng shop: get_order_list(update_time từ checkpoint − overlap, tới now)
  → so với DB → đơn thiếu/lệch → phát ChannelOrderSynced như webhook bình thường
  → lưu checkpoint; metric reconciliation_found_missing (lý tưởng là 0, khác 0 tức webhook đã mất)
Hằng đêm: so published stock mong muốn với số tồn thực trên sàn → đẩy lại phần lệch
```

---

# Phần C: Kỹ thuật và nơi áp dụng

Mỗi kỹ thuật ghi theo nhịp: **dùng ở đâu**, **vì sao cần ở chỗ đó**, **công nghệ**, và **bẫy hay thử nghiệm đáng làm**.

Phiên bản nền: Java 25, **Spring Boot 4.1.x** (cùng dòng với `sp-jpa`). Mỗi service là một repo với build riêng (polyrepo, xem `adr/0001-polyrepo.md`). Spring Cloud phải chọn release train tương thích Boot 4.1: tra bảng tương thích trên spring.io/start.spring.io lúc dựng, không đoán. Kafka 4.x (KRaft, không còn ZooKeeper), PostgreSQL 17+.

## C1. Kiến trúc và phân rã

| Kỹ thuật | Dùng ở đâu | Vì sao |
|---|---|---|
| **DDD: bounded context, aggregate** | Order, Inventory (StockItem theo SKU × kho), Listing | Ranh giới service đi theo ranh giới nghiệp vụ. Aggregate là đơn vị nhất quán: một transaction chỉ sửa một aggregate |
| **Database per service** | Mọi service có DB/schema riêng | Không service nào đọc trực tiếp bảng của service khác. Cần dữ liệu của nhau thì qua API hoặc event |
| **Anti-corruption layer, ports & adapters (hexagonal)** | channel-connector: interface `MarketplacePort` có `TikTokAdapter`, `ShopeeAdapter`; fulfillment: `CarrierPort` | Ngăn khái niệm của sàn rò vào lõi. Thêm sàn mới chỉ viết adapter (N13). Chạy được với simulator hoặc sàn thật bằng cấu hình |
| **Canonical data model** | Order status, product/variant, stock | Một mô hình chung, mỗi sàn ánh xạ vào |
| **API Gateway** | gateway | Một cổng vào: xác thực, rate limit theo Workspace, định tuyến |
| **BFF** (tùy chọn) | Next.js server (route handler) hoặc một service BFF | Gom nhiều API cho một màn hình, giảm round-trip từ trình duyệt |
| **Modular monolith trước, tách sau** | Giai đoạn đầu | Học được cách chọn ranh giới. Tách khi có số đo chứng minh cần (scale khác nhau, deploy khác nhau) |
| **ADR** | `adr/` của repo `docs` (cấp hệ thống) và `docs/adr/` trong từng repo service | Ghi lại quyết định và lý do. Đây là chất liệu tốt cho phỏng vấn |

## C2. Giao tiếp đồng bộ

| Kỹ thuật | Dùng ở đâu | Ghi chú |
|---|---|---|
| **REST + OpenAPI (contract-first)** | API cho FE, API giữa service (ít), simulator | Spec ở `openapi/` của repo `contracts`, sinh client/server stub |
| **HTTP client có timeout tường minh** | Mọi lời gọi ra ngoài, đặc biệt là gọi sàn | Spring `RestClient` / HTTP Interface. Không bao giờ để timeout mặc định vô hạn |
| **Service discovery bằng DNS của Kubernetes** | Gọi nội bộ | Không cần Eureka khi chạy trên K8s. Đây là chủ đề hay bị hỏi: khi nào còn cần Eureka |
| **gRPC** (tùy chọn) | order → inventory để kiểm tồn nhanh | Để so sánh với REST: độ trễ, contract, streaming |
| **Versioning API** | API public cho Workspace (F10.2) | Version trong path hoặc header; quy tắc thay đổi tương thích ngược |
| **Pagination bằng cursor** | Danh sách đơn | Offset chậm và lệch dữ liệu khi có ghi đồng thời. Giống cách sàn làm |

## C3. Event-driven architecture

| Kỹ thuật | Dùng ở đâu | Vì sao, bẫy |
|---|---|---|
| **Kafka làm event backbone** | Mọi luồng bất đồng bộ | Lưu bền, replay được, nhiều consumer group độc lập |
| **Chọn partition key để có thứ tự** | `skuId` cho `AvailabilityChanged`, `orderId` cho event đơn, `shopId` cho notification | Kafka chỉ đảm bảo thứ tự trong một partition. Partition theo `skuId` nghĩa là mọi thay đổi của một SKU được xử lý tuần tự, **giảm nhu cầu lock**. Bẫy: hot partition khi một SKU bán cực chạy trong flash sale. Nên thí nghiệm |
| **Transactional Outbox** | order, inventory, catalog, fulfillment | Ghi DB và phát event phải "cùng thành công hoặc cùng thất bại". Không làm thì gặp dual-write: lưu đơn rồi crash trước khi gửi Kafka |
| **CDC với Debezium** đọc bảng outbox | Relay outbox → Kafka | So sánh với polling publisher (job quét bảng outbox): độ trễ, tải DB, độ phức tạp vận hành |
| **Idempotent consumer / inbox table** | Mọi consumer có side effect | Kafka giao at-least-once. Lưu `eventId` đã xử lý cùng transaction với thay đổi nghiệp vụ |
| **Xử lý sai thứ tự bằng version** | order (theo `channelUpdateTime`), listing | Event cũ đến sau event mới thì bỏ qua. Đây là bài toán có thật vì sàn không đảm bảo thứ tự (A2) |
| **Event notification vs event-carried state transfer** | Webhook sàn là notification (phải gọi API lấy dữ liệu); `ChannelOrderSynced` mang đủ state | Hiểu trade-off: dữ liệu cũ vs số lần gọi |
| **Schema Registry + Avro** (hoặc Protobuf) | `avro/` của repo `contracts` | Quy tắc tiến hóa schema (backward/forward compatible). Thí nghiệm: thêm field, đổi kiểu, deploy lệch phiên bản |
| **Retry topic + Dead Letter Topic** | Consumer gặp lỗi | Spring Kafka `@RetryableTopic`. Phân biệt lỗi tạm thời (retry) và lỗi vĩnh viễn (DLT). Cần công cụ xem và replay DLT |
| **Choreography vs orchestration** | Đồng bộ tồn kho dùng choreography; xử lý đơn dùng orchestration (B3) | Làm cả hai để so sánh khả năng theo dõi, độ ghép nối, xử lý lỗi |
| **Consumer lag làm tín hiệu** | Mọi consumer group | Lag là chỉ số sức khỏe chính và là tín hiệu autoscale (C13) |
| **Event sourcing** (giới hạn) | Sổ cái tồn kho (F4.3) | Tồn hiện tại = tổng các bút toán; có snapshot. Áp dụng ở đúng nơi có lợi, không áp dụng cho cả hệ thống |

## C4. Nhất quán dữ liệu và concurrency

Đây là nhóm kỹ thuật "ăn tiền" nhất của dự án, vì oversell là lỗi nghiệp vụ trực tiếp.

| Kỹ thuật | Dùng ở đâu | Chi tiết |
|---|---|---|
| **Saga (orchestration)** | Xử lý đơn (B3 luồng 2) | Trạng thái saga lưu trong DB của order; mỗi bước có compensation. So sánh tự viết với **Temporal** hoặc Spring State Machine |
| **Reservation pattern** | inventory | Giữ tồn có thời hạn; nhả khi hủy hoặc quá hạn. Đây là cốt lõi chống oversell |
| **Optimistic locking** (`@Version`) | StockItem, Order | Khi tranh chấp thấp. Đo tỷ lệ conflict khi tải cao |
| **Atomic update có điều kiện** | Trừ tồn: `UPDATE ... SET reserved = reserved + :q WHERE available >= :q` | So sánh với `SELECT FOR UPDATE` và với Redis Lua script. Viết thí nghiệm đo throughput và tính đúng |
| **Đơn luồng theo key** (single writer per partition) | Xử lý tồn kho theo `skuId` | Cách thay thế lock: nhờ partition Kafka, mỗi SKU chỉ một luồng ghi |
| **Distributed lock** | Refresh token theo shop (C5.3), job chạy một instance | Redis (Redisson) hoặc ShedLock (dựa trên DB). Hiểu fencing token và vì sao lock Redis không an toàn tuyệt đối |
| **Idempotency key** | API tạo đơn thủ công, ship package, mọi lệnh gửi sàn | Header `Idempotency-Key`, lưu kết quả lần đầu. Sàn cũng trả lỗi khi ship lần hai (TikTok 11006021): phải coi đó là "đã thành công" |
| **Reconciliation** | Đơn (B3 luồng 3), tồn kho trên sàn, settlement | Chấp nhận eventual consistency, nhưng phải có cơ chế **chứng minh** cuối cùng nhất quán |
| **Tính toán tồn kho** | inventory | `available = on_hand − reserved − safety`; published cho từng kênh = f(available, quy tắc %, buffer, ngưỡng về 0, tồn sàn giữ cho khuyến mãi); combo = min(con / số lượng) |
| **Coalescing / debounce** | Đẩy tồn lên sàn | 50 đơn cùng SKU trong 1 giây → 1 lần gọi sàn với số cuối cùng, không phải 50 lần. Đổi một chút độ trễ lấy rất nhiều quota |

## C5. Tích hợp hệ thống ngoài

### C5.1 Nhận webhook (webhook-ingress)

- Đọc **raw body** để verify HMAC (không parse JSON trước). So sánh bằng **constant-time compare** để tránh timing attack.
- Ghi Kafka với `acks=all` rồi trả 200. Nếu Kafka không ghi được thì trả 5xx để sàn retry. Tuyệt đối không trả 200 khi chưa ghi bền.
- Dedupe nhanh bằng Redis `SET NX` + TTL theo `notification_id` (TikTok) hoặc hash của body (Shopee). Đây chỉ là lớp tối ưu; consumer vẫn phải idempotent.
- Không phụ thuộc DB hay service nào khác. Chạy nhiều replica, có PodDisruptionBudget.
- Thử nghiệm: dùng Toxiproxy làm Kafka chậm 2 giây. Ingress còn trả lời trong 3 giây không? Có bị sàn coi là lỗi không?

### C5.2 Gọi API sàn và rate limit

- **Distributed rate limiter** (token bucket trên Redis, ví dụ Bucket4j + Redis hoặc Lua script tự viết), khóa theo `(channel, appId, shopId, endpointClass)`.
- **Rate limit thích nghi:** gặp 429 hoặc 36009002 thì giảm tốc, theo `Retry-After`; ổn định thì tăng dần (kiểu AIMD). Lý do: TikTok dùng quota động.
- **Hàng đợi theo độ ưu tiên:** lệnh giao hàng > cập nhật tồn > đồng bộ đơn định kỳ > đăng sản phẩm hàng loạt. Job hàng loạt không được làm nghẽn lệnh khẩn.
- **Fairness giữa Workspace:** chia lượt theo Workspace (weighted fair queuing) để Workspace 10.000 SKU không làm chậm Workspace 50 SKU.
- **Retry với exponential backoff + jitter**, có giới hạn. Không retry lỗi nghiệp vụ (4xx khác 429). Bẫy: Shopee có thể hạn chế app vì retry dồn dập.
- **Batching:** Shopee `get_order_detail` 50 đơn/lần, `update_stock` 50 model/lần.

### C5.3 Quản lý token

- Lưu token **mã hóa** (envelope encryption: data key mã hóa token, master key ở KMS/Vault hoặc K8s Secret trong lab).
- **Refresh chủ động** bằng scheduler: quét các shop sắp hết hạn (Shopee 4 giờ), refresh trước khoảng 30 phút.
- **Single-flight cho mỗi shop:** vì refresh token Shopee xoay vòng, hai lần refresh song song thì lần sau thất bại và shop mất kết nối. Giải pháp: distributed lock theo `shopId`, hoặc "owner" duy nhất cho mỗi shop (partition theo `shopId`). Đây là thí nghiệm đáng làm: tái hiện lỗi trước, rồi sửa.
- Access token cũ còn hiệu lực 5 phút sau khi refresh (Shopee): request đang bay không bị lỗi. Hiểu điều này để thiết kế cache token.
- Hết hạn hoặc bị thu hồi: phát `ShopAuthorizationExpired`, dừng mọi job của shop, báo người dùng.

### C5.4 Đồng bộ tăng dần (polling)

- Checkpoint `last_synced_update_time` cho mỗi shop và loại dữ liệu. Cửa sổ kế tiếp bắt đầu từ `checkpoint − overlap` (ví dụ 2 phút), vì `update_time` của sàn có thể "đến muộn".
- Chia khoảng: Shopee tối đa 15 ngày mỗi lần gọi, dùng cho backfill.
- Upsert idempotent; so `update_time` để bỏ bản cũ.
- Khi sàn trả `warning` báo quá tải (Shopee): đánh dấu kết quả có thể cũ, lên lịch quét lại.

### C5.5 Job dài và xử lý hàng loạt

- Đăng 5.000 sản phẩm, in 500 vận đơn, import Excel: tạo **job** có trạng thái, chia thành item, xử lý song song có giới hạn, **partial failure** (thành công 4.700, lỗi 300, cho phép retry riêng phần lỗi), có tiến độ real-time.
- Vận đơn Shopee là luồng bất đồng bộ nhiều bước: tạo → poll/push → tải về. Đây là ví dụ tốt cho state machine và polling có backoff.
- Công nghệ: Spring Batch, hoặc tự làm job/item table + worker qua Kafka. Nên làm cách tự viết trước để hiểu.

### C5.6 Gọi hãng vận chuyển (fulfillment)

- `CarrierPort` với adapter cho từng simulator hãng. Circuit breaker riêng từng hãng; có hãng dự phòng.
- Nhận webhook trạng thái giao hàng (tái dùng mẫu C5.1).

## C6. Resilience

| Kỹ thuật | Dùng ở đâu | Ghi chú |
|---|---|---|
| **Timeout** | Mọi lời gọi mạng | Ngân sách thời gian theo luồng |
| **Circuit breaker** | Mỗi sàn, mỗi hãng vận chuyển (Resilience4j) | Shopee sập thì mở breaker riêng của Shopee; TikTok vẫn chạy (N7) |
| **Bulkhead** | Thread pool / connection pool tách theo sàn; executor riêng cho job hàng loạt | Một sàn chậm không chiếm hết thread. Với Java 25 có virtual thread: bulkhead lúc này là giới hạn concurrency (semaphore), không phải số thread |
| **Retry + backoff + jitter** | Gọi sàn, consumer | Chỉ retry lỗi tạm thời, có giới hạn tổng |
| **Backpressure** | Consumer đẩy tồn; connector khi bị rate limit | Tạm dừng consumer (`pause`/`resume`) thay vì đọc vô hạn rồi tràn bộ nhớ |
| **Load shedding, graceful degradation** | Gateway khi quá tải; dashboard | Ưu tiên luồng đơn hàng; tạm tắt báo cáo nặng |
| **Graceful shutdown** | Mọi service | Xử lý xong message đang dở, commit offset, rồi mới tắt. Kết hợp `preStop` trên K8s |
| **Chaos testing** | Toxiproxy (độ trễ, ngắt mạng), Chaos Mesh (kill pod), simulator (sàn trả 5xx, 429) | Mỗi kịch bản có giả thuyết và số đo, kết quả ghi ở `experiments/` |

## C7. Lưu trữ, cache, đọc và báo cáo

| Kỹ thuật | Dùng ở đâu | Ghi chú |
|---|---|---|
| **PostgreSQL**: index, partitioning | `order` partition theo tháng; `stock_ledger` append-only | Áp dụng kiến thức từ `sp-jpa`: transaction, N+1, locking |
| **Migration bằng Flyway** | Mọi service | Migration tương thích ngược (expand/contract) để deploy không downtime |
| **Redis** | Rate limiter, dedupe, cache token, distributed lock, cache available stock | Hiểu khi Redis mất dữ liệu thì hệ quả là gì ở từng vai trò |
| **Cache-aside + invalidation qua event** | Catalog (đọc nhiều), mapping listing ↔ SKU | Cache invalid khi nhận `ListingMapped` |
| **CQRS** | Danh sách đơn tìm theo nhiều tiêu chí; dashboard | Ghi vào PostgreSQL, đọc từ projection (OpenSearch hoặc ClickHouse) dựng từ event |
| **OpenSearch** | Tìm sản phẩm, đơn hàng (tên người mua, mã đơn, SKU) | Đồng bộ qua event; chấp nhận trễ vài giây |
| **ClickHouse (OLAP)** | Báo cáo doanh số, lợi nhuận (F9) | Tách tải phân tích khỏi DB giao dịch |
| **Kafka Streams** | Số đơn và doanh số theo phút, top SKU, tốc độ bán (cho gợi ý nhập hàng, F4.9) | Windowing, state store, exactly-once trong Streams |
| **Object storage (MinIO)** | PDF vận đơn, file import/export | Presigned URL cho FE tải trực tiếp |

## C8. Multi-tenancy

- Mô hình: **shared database, shared schema, cột `workspace_id`**. So sánh với schema-per-tenant trong một ADR.
- `workspace_id` lấy từ JWT, truyền qua mọi lời gọi và event header. Lọc tự động (Hibernate filter, hoặc **PostgreSQL Row-Level Security** để có lớp bảo vệ thứ hai).
- Hạn mức theo gói (F1.4): đếm usage bằng event, chặn ở gateway hoặc service.
- Noisy neighbour: fairness ở connector (C5.2), rate limit theo Workspace ở gateway, metric gắn nhãn Workspace (cẩn thận cardinality).

## C9. Bảo mật

| Kỹ thuật | Dùng ở đâu |
|---|---|
| **OAuth2/OIDC với Keycloak** | Đăng nhập; service là resource server kiểm JWT (Spring Security) |
| **Phân quyền theo vai trò và phạm vi** (shop, kho) | Method security, kiểm tra theo Workspace |
| **Xác thực service-to-service** | mTLS qua service mesh (giai đoạn sau), hoặc client credentials |
| **Webhook HMAC** | Nhận (từ sàn) và gửi (cho Workspace, F10.3) |
| **Mã hóa secret khi lưu** | Token sàn (C5.3) |
| **Quản lý secret trên K8s** | Sealed Secrets hoặc External Secrets + Vault; không commit secret |
| **Che PII** | Log không chứa số điện thoại, địa chỉ người mua (logback masking) |
| **Audit log** | Thao tác thay đổi tồn kho, hủy đơn, đổi quyền (F1.3) |
| **NetworkPolicy** | Chỉ gateway nhận traffic ngoài; DB chỉ nhận từ service sở hữu |
| **Quét lỗ hổng** | Quét image (Trivy), dependency trong CI |

## C10. Observability

| Kỹ thuật | Dùng ở đâu | Ghi chú |
|---|---|---|
| **OpenTelemetry** | Mọi service | Spring Boot 4.1 có auto-config xuất trace, metric và log qua OTLP (`management.otlp.metrics.export.url`, `management.opentelemetry.logging.export.otlp.endpoint`) |
| **Trace xuyên Kafka** | Mọi producer/consumer | Truyền `traceparent` trong header message, để một đơn đi qua webhook → connector → order → inventory → connector nằm trên một trace (N12) |
| **Structured logging (JSON)** | Mọi service | Log có `traceId`, `workspaceId`, `orderId`, `shopId`; tìm trên Loki |
| **Metric RED/USE** | HTTP, consumer, DB pool | Rate, errors, duration; Kafka consumer lag |
| **Business metric** | `stock_sync_lag`, `orders_imported_total{channel}`, `reconciliation_found_missing`, `oversell_detected_total`, `channel_api_429_total`, `token_refresh_failures_total` | Đây là metric thể hiện sức khỏe sản phẩm, quan trọng hơn CPU |
| **Stack Grafana LGTM** | Loki (log), Grafana, Tempo (trace), Mimir/Prometheus (metric); OTel Collector hoặc Grafana Alloy ở giữa | |
| **SLO và alert theo burn rate** | N2, N3, N9 | Alert theo mức tiêu hao error budget, không alert theo CPU |
| **Dashboard sức khỏe tích hợp** | Từng shop, từng sàn | Đồng thời là tính năng cho người dùng (F2.5) |
| **Runbook** | `runbooks/` | Mỗi alert gắn với một runbook |

## C11. Container và Kubernetes

| Kỹ thuật | Dùng ở đâu |
|---|---|
| **Build image** | Spring Boot Buildpacks (`bootBuildImage`) hoặc Jib; layered jar; image không chạy bằng root |
| **JVM trong container** | `-XX:MaxRAMPercentage`, request/limit hợp lý; thử CDS/AOT cache để khởi động nhanh hơn |
| **Probe** | Liveness, readiness, startup qua Actuator health groups; readiness phụ thuộc Kafka/DB, liveness thì không |
| **Config** | ConfigMap + biến môi trường; Secret cho thông tin nhạy cảm |
| **Helm chart dùng chung** | Một chart "spring-service" cho mọi service, values riêng cho từng service |
| **Kustomize overlay** | `local`, `staging` |
| **Gateway API** | Expose gateway và webhook-ingress ra ngoài cụm (thay cho Ingress) |
| **HPA + KEDA** | HPA theo CPU/RPS cho API; **KEDA theo Kafka consumer lag** cho consumer (flash sale) |
| **PodDisruptionBudget, anti-affinity** | webhook-ingress, các consumer chính |
| **Hạ tầng trong cụm** | Cụm home lab (context `homelab`, xem `platform/docs/homelab-hyperv.md`): service, simulator, Keycloak, cùng Kafka, PostgreSQL, Redis, ClickHouse, OpenSearch. Hạ tầng dữ liệu dựng bằng operator (Strimzi, CloudNativePG) để học thêm. Compose ở `compose/` của repo `platform` chỉ dùng khi chạy thử nhanh trên MacBook |

## C12. CI/CD và GitOps

- CI (GitHub Actions): build, test, Testcontainers, kiểm tra contract, quét bảo mật, build image, push registry (registry trên VM `gw` của home lab).
- **GitOps với Argo CD**: repo `gitops` là nguồn sự thật; CI của service chỉ cập nhật image tag trong đó. Chart dùng chung publish từ repo `platform`, values theo môi trường nằm ở `gitops` (Argo CD multiple sources).
- **Reusable workflow**: mỗi repo service gọi workflow chung trong repo `platform` thay vì chép CI.
- **Canary hoặc blue-green** với Argo Rollouts, kèm phân tích tự động theo metric (tỷ lệ lỗi, `stock_sync_lag`).
- Migration DB chạy trước khi deploy, theo kiểu expand/contract.
- Feature flag (OpenFeature/flagd): bật tính năng theo Workspace.

## C13. Scale và hiệu năng

- Scale consumer theo **số partition**: số consumer tối đa có ích bằng số partition. Chọn số partition ngay từ đầu cho topic tồn kho.
- **Virtual threads** (Java 21+) cho service chủ yếu chờ I/O (connector gọi sàn). So sánh với thread pool cổ điển bằng số đo.
- Connection pool (HikariCP) đặt theo số replica × pool size ≤ giới hạn của PostgreSQL; cân nhắc PgBouncer.
- Hot key: một SKU flash sale nằm trên một partition. Thí nghiệm: đo, rồi thử các cách như gom theo cửa sổ thời gian hoặc tách "bucket tồn kho" cho SKU nóng.
- Profiling: JFR, async-profiler khi tối ưu có số đo.

## C14. Kiểm thử

| Tầng | Công cụ | Thử gì |
|---|---|---|
| Unit | JUnit 5, AssertJ | State machine đơn, công thức tồn kho, ánh xạ trạng thái từng sàn |
| Integration | **Testcontainers** (PostgreSQL, Kafka, Redis) | Outbox, idempotent consumer, locking dưới tải đồng thời |
| Contract | **Pact** (REST giữa service), kiểm tra tương thích schema Avro | Đổi API không làm vỡ consumer |
| Component với simulator | Docker Compose: service + simulator | Webhook trùng, sai thứ tự, token hết hạn |
| Load | **k6** hoặc Gatling (repo `load-tests`) | N3, N6: ngày thường, flash sale, tăng đột biến |
| Chaos | Toxiproxy, Chaos Mesh, lỗi từ simulator | N4, N7: sàn sập 10 phút, Kafka chậm, kill pod giữa saga |
| Property-based (tùy chọn) | jqwik | Bất biến tồn kho: không bao giờ âm, tổng bút toán = on_hand |

## C15. Frontend

- Next.js + TypeScript (App Router), TanStack Query cho data fetching, form có validation.
- Đăng nhập OIDC với Keycloak (Auth.js hoặc thư viện OIDC client).
- **SSE** để nhận đơn mới, tiến độ job, thông báo lỗi đồng bộ (đơn giản hơn WebSocket vì chỉ cần một chiều). Qua gateway thì cần cấu hình timeout và buffering phù hợp.
- Bảng lớn (danh sách đơn): phân trang cursor phía server, virtualized list.
- Màn hình chính: kết nối shop, sức khỏe kết nối, sản phẩm và mapping, tồn kho theo kho và theo kênh, danh sách đơn và xử lý hàng loạt, dashboard.

## C16. Ma trận kỹ thuật × service

✅ trọng tâm · ○ có dùng

| Kỹ thuật | gateway | workspace | connector | ingress | catalog | inventory | order | fulfillment | reporting | notification |
|---|---|---|---|---|---|---|---|---|---|---|
| Outbox + CDC | | | ○ | | ✅ | ✅ | ✅ | ✅ | | |
| Idempotent consumer | | | ✅ | | ○ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Xử lý sai thứ tự (version) | | | ✅ | | ○ | | ✅ | ○ | ○ | |
| Saga | | | | | | ○ | ✅ | ○ | | |
| Reservation, atomic update, lock | | | | | | ✅ | ○ | | | |
| Distributed lock / single-flight | | | ✅ | | | ○ | | | | |
| Rate limit phân tán | ✅ | | ✅ | | | | | | | |
| Circuit breaker, bulkhead | ○ | | ✅ | | | | | ✅ | | ○ |
| ACL / adapter | | | ✅ | ✅ | ○ | | | ✅ | | |
| Webhook HMAC | | | | ✅ | | | | ○ | | ✅ |
| Job dài, partial failure | | | ✅ | | ✅ | ○ | | ✅ | | |
| Reconciliation | | | ✅ | | | ✅ | ✅ | | | |
| CQRS / search | | | | | ✅ | | ✅ | | ✅ | |
| Stream processing | | | | | | ○ | | | ✅ | |
| Event sourcing (ledger) | | | | | | ✅ | | | | |
| Multi-tenancy, quota | ✅ | ✅ | ✅ | | ○ | ○ | ○ | | ○ | |
| SSE real-time | | | | | | | | | | ✅ |
| KEDA theo lag | | | ✅ | | | ✅ | ✅ | | ✅ | |
| Mã hóa secret | | | ✅ | ✅ | | | | ○ | | |

## C17. Simulator: thành phần hạng nhất

Simulator quyết định có đo được hệ thống hay không, nên phải thiết kế nghiêm túc như một service thật. Có thể viết bằng Spring Boot để dùng lại kiến thức.

**tiktok-sim, shopee-sim** (cùng lõi, khác "dialect"):

- API tối thiểu: OAuth (cấp code, đổi token, refresh với **xoay vòng** đúng như Shopee), danh sách và chi tiết đơn (cursor, giới hạn khoảng thời gian), cập nhật tồn kho (từ chối khi thấp hơn phần giữ cho khuyến mãi), ship package (lỗi khi ship lần hai), lấy vận đơn bất đồng bộ.
- Ký và kiểm chữ ký đúng thuật toán của từng sàn.
- **Bộ sinh đơn**: người mua ảo đặt hàng theo phân phối Poisson với tốc độ cấu hình được, theo kịch bản (ngày thường, flash sale 500 đơn/s, livestream dồn vào vài SKU). Simulator tự giữ "tồn kho trên sàn" của từng listing và **ghi lại mọi lần bán khi tồn trên sàn đã về 0 so với tồn thật**, tức đếm oversell (N5).
- **Webhook có cấu hình lỗi**: tỷ lệ trùng, tỷ lệ đảo thứ tự, tỷ lệ mất, độ trễ; retry theo đúng lịch của sàn; tắt subscription khi tỷ lệ thành công thấp (Shopee).
- **Lỗi có chủ đích**: rate limit động (429, `Retry-After`), 5xx ngẫu nhiên, độ trễ cao, sàn sập trong N phút, trả `warning` quá tải.
- Điều khiển qua admin API để test tự động bật/tắt kịch bản.

**carrier-sim**: tạo vận đơn, cập nhật hành trình theo thời gian (lấy hàng → đang giao → giao thành công/thất bại), webhook trạng thái, đối soát COD.

**Chỉ số simulator xuất ra**: đơn đã sinh, đơn bị oversell, độ trễ tồn kho thấy được trên sàn, số 429 đã trả, tỷ lệ webhook thành công. Đây là các con số để kể khi phỏng vấn.

## C18. Lộ trình gợi ý

Mỗi giai đoạn kết thúc bằng một thứ chạy được trên cụm home lab và một bản ghi thí nghiệm có số đo.

| Giai đoạn | Nội dung | Kỹ thuật trọng tâm | Kết quả đo được |
|---|---|---|---|
| **0. Nền tảng** | Repo `docs`, `platform`, `gitops`, template repo cho service, cụm home lab, Argo CD, PostgreSQL, Kafka, Keycloak, LGTM, CI | K8s, GitOps, OTel | Một service "hello" có trace và dashboard |
| **1. Lõi đồng bộ** | shopee-sim tối thiểu; connector (OAuth, poll đơn); order; catalog + mapping; inventory cơ bản; FE xem đơn và tồn | REST, ACL, Flyway, multi-tenancy | Đơn từ simulator hiện trên FE |
| **2. Event-driven** | webhook-ingress; outbox + Debezium; idempotent consumer; đồng bộ tồn kho sang tiktok-sim; DLT | Kafka, outbox, thứ tự, idempotency | `stock_sync_lag` p95; số oversell ở 20 đơn/s |
| **3. Chịu lỗi và tuân thủ sàn** | Rate limit thích nghi, ưu tiên, fairness; token single-flight; reconciliation; circuit breaker | Resilience4j, Redis, distributed lock | N4 với webhook mất 100%; N8 khi sàn giảm quota |
| **4. Xử lý đơn** | Saga xử lý đơn, fulfillment, carrier-sim, vận đơn bất đồng bộ, hoàn trả | Saga, state machine, job dài | Saga đúng khi kill pod giữa chừng |
| **5. Tải và scale** | Kịch bản flash sale; KEDA theo lag; hot SKU; tinh chỉnh partition, pool, virtual thread | KEDA, profiling, partition | N6: 500 đơn/s, oversell và độ trễ |
| **6. Đọc và báo cáo** | OpenSearch, ClickHouse, Kafka Streams; dashboard real-time (SSE) | CQRS, stream processing | Độ trễ projection |
| **7. Vận hành production-grade** | Canary (Argo Rollouts), SLO alert, runbook, NetworkPolicy, secret, mesh/mTLS; postmortem từ chaos | SRE, bảo mật | Một canary tự rollback nhờ metric |

## C19. Chủ đề phỏng vấn gắn với dự án

Mỗi dòng là một câu chuyện "vấn đề, cách làm, số đo" kể được từ dự án:

1. **Chống oversell khi 3 kênh cùng bán một SKU:** reservation, atomic update vs lock vs đơn luồng theo partition; số đo oversell trước và sau.
2. **Dual-write và outbox:** vì sao không gửi Kafka ngay trong `@Transactional`; Debezium vs polling publisher.
3. **Webhook trùng và sai thứ tự:** idempotency, version theo `update_time`, reconciliation làm lưới an toàn.
4. **Refresh token xoay vòng gây mất kết nối:** tái hiện race condition, sửa bằng single-flight.
5. **Tuân thủ rate limit động của bên thứ ba:** token bucket phân tán, AIMD, hàng đợi ưu tiên, fairness giữa Workspace.
6. **Saga xử lý đơn:** orchestration vs choreography, compensation, kill pod giữa saga.
7. **Flash sale:** KEDA theo lag, hot partition, backpressure.
8. **Truy vết một đơn qua 6 service:** OTel xuyên Kafka, business metric, SLO.
9. **Thêm sàn mới không sửa lõi:** hexagonal, ACL, canonical model.
10. **Tiến hóa schema event** khi deploy lệch phiên bản.

---

## Nguồn

**Tài liệu sàn (chính thức)**

- TikTok Shop: [Authorization overview](https://partner.tiktokshop.com/docv2/page/authorization-overview-202407) · [Seller authorization guide](https://partner.tiktokshop.com/docv2/page/seller-authorization-guide) · [Sign your API request](https://partner.tiktokshop.com/docv2/page/sign-your-api-request) · [Common errors](https://partner.tiktokshop.com/docv2/page/common-errors) · [Webhooks overview](https://partner.tiktokshop.com/docv2/page/tts-webhooks-overview) · [Webhook configuration](https://partner.tiktokshop.com/docv2/page/configuration-guide) · [Get Order List](https://partner.tiktokshop.com/docv2/page/get-order-list-202309) · [Search Cancellations](https://partner.tiktokshop.com/docv2/page/search-cancellations-202309) · [Search Returns](https://partner.tiktokshop.com/docv2/page/search-returns-202309) · [Ship Package](https://partner.tiktokshop.com/docv2/page/ship-package-202309) · [Shipping documents](https://partner.tiktokshop.com/docv2/page/get-package-shipping-document-202309) · [Product API guide](https://partner.tiktokshop.com/docv2/page/solution-guidance-product-api) · [Update Inventory](https://partner.tiktokshop.com/docv2/page/update-inventory-202309) · [Rate limits](https://partner.tiktokshop.com/docv2/page/rate-limits) · [API versioning](https://partner.tiktokshop.com/docv2/page/api-versioning)
- Shopee Open Platform: [Authorization](https://open.shopee.com/developer-guide/20) · [Signing](https://open.shopee.com/developer-guide/16) · [Push mechanism](https://open.shopee.com/developer-guide/18) · [order_status_push](https://open.shopee.com/push-mechanism/1) · [Data definition](https://open.shopee.com/developer-guide/31) · [Order & logistics guide](https://open.shopee.com/developer-guide/229) · [get_order_list](https://open.shopee.com/documents/v2/v2.order.get_order_list?module=94&type=1) · [update_stock](https://open.shopee.com/documents/v2/v2.product.update_stock?module=89&type=1) · [FAQ](https://open.shopee.com/faq?categoryId=2054)

**Sản phẩm OMS (trang công khai, mang tính marketing)**

- Việt Nam/SEA: [Sapo Omnichannel](https://sapo.vn/omnichannel.html) · [Sapo: tích hợp sàn](https://www.sapo.vn/blog/tich-hop-shopee-lazada-tiktok-shop) · [Sapo: xử lý lỗi đồng bộ](https://www.sapo.vn/cap-nhat-tinh-nang/cach-xu-ly-san-pham-va-don-hang-dong-bo-loi) · [BigSeller](https://www.bigseller.pro/) · [Ginee](https://ginee.com/vn/insights/what-is-ginee-vietnam/) · [Nhanh.vn combo](https://pos.manual.nhanh.vn/pos/san-pham/khainiem-sp/loai-san-pham/san-pham-combo) · [Pancake POS: kết nối Shopee](https://docs.pos.pages.fm/pos/thiet-lap-shop/kenh-ban/ket-noi-kenh-ban/shopee) · [KiotViet](https://www.kiotviet.vn/) · [Zetpy: kịch bản oversell](https://support.zetpy.com/doc/overselling-scenarios-scenario-handling)
- Toàn cầu: [Linnworks](https://www.linnworks.com/solutions/inventory-management/) · [ChannelEngine](https://www.channelengine.com/info-page-for-ai-and-llms) · [Zoho Inventory pricing](https://www.zoho.com/inventory/pricing/) · [Sellercloud](https://sellercloud.com/)

**Kỹ thuật**

- Spring Boot 4.1 reference: observability, OTLP export (spring.io/projects/spring-boot)
- Chris Richardson, *Microservices Patterns*: saga, outbox, CQRS (microservices.io)
- Debezium outbox event router; Spring Kafka `@RetryableTopic`; Resilience4j; KEDA Kafka scaler
