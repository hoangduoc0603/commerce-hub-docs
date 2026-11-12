# 10 Mô hình ghi của inventory ở G1

Type: grilling
Status: resolved
Blocked by: 08
Map: [Kiến trúc G0–G1](../map.md)

## Question

StockItem, Reservation và sổ cái (F4.1a–b, F4.2a–b, F4.3a) lưu thế nào ở G1: sổ cái là nguồn sự thật (event sourcing giới hạn, C3) hay bảng số dư cộng bảng bút toán? Ghi đồng thời bằng atomic update có điều kiện, optimistic locking hay `SELECT FOR UPDATE` (C4)? Bất biến nào phải kiểm (N16), và idempotency của lệnh giữ tồn theo khóa nào (BR liên quan, ADR-0002).

## Answer

Chốt ngày 2026-11-13 (người dùng), sau hai vòng grilling. Lưu bằng **bảng số dư cộng sổ cái trong cùng transaction**, khi lệch thì sổ cái thắng. Khóa bi quan theo thứ tự cố định: [ADR-0007](../../../adr/0007-stock-balance-plus-ledger-in-one-transaction.md).

### Lưu trữ

- `stock_item`: (Master SKU, Warehouse), On hand, tổng Reservation, đã khai báo tồn hay chưa. Đây là snapshot của sổ cái. StockItem được tạo lúc lần đầu khai báo tồn hoặc lần đầu giữ tồn (`INSERT ... ON CONFLICT DO NOTHING`, `declared = false`).
- `reservation`: theo dòng đơn, trạng thái `Open`/`Released`/`Consumed`. Unique `(order_line_id) WHERE status = 'Open'` làm lưới an toàn. Một dòng ghép lại sang SKU khác sẽ có một Reservation `Released` cũ và một `Open` mới.
- `ledger_entry`: chỉ thêm (BR-28), một bút toán cho mỗi StockItem bị đổi. Thêm hai cột:
  - `idempotency_key`, unique theo `(workspace_id, idempotency_key)`, null với bút toán sinh từ Kafka;
  - `caused_oversell`: true khi bút toán giữ tồn làm Available của một StockItem **đã khai báo** chuyển xuống âm.
- `order_inventory_state`: theo Order, gồm `orderVersion` đã áp dụng, cờ Short order và version tăng dần của chính trạng thái này.
- Mọi bảng có `workspace_id` (C8). Cách cô lập Workspace do ticket 06 quyết.

### Giữ và nhả tồn từ Kafka (F4.2a–b, BR-18, BR-20)

- Event order → inventory mang **trạng thái đích của cả Order**: mọi dòng `(orderLineId, masterSkuId | null, qty = đặt − đã hủy)`, kèm `orderVersion`. Đây là version aggregate do order tự tăng mỗi khi Order đổi, kể cả khi đổi do ghép Listing (BR-16). Không dùng `update_time` của sàn.
- inventory tính delta = đích − hiện có cho từng dòng. Một transaction cho mỗi event, gồm: tạo item còn thiếu; khóa mọi `stock_item` liên quan; khóa `order_inventory_state`; bỏ qua nếu `orderVersion` ≤ version đã áp dụng (chặn redelivery và consumer zombie khi rebalance); ghi reservation, số dư và bút toán; tính lại Short order.
- Các trường hợp tự khớp nhờ trạng thái đích: hủy một phần, bỏ ghép (null nghĩa là nhả), ghép lại sang SKU khác (nhả item cũ, giữ item mới), hủy đến trước khi tạo (qty 0, F4.2b).
- Consumer này **không dùng bảng inbox**: kiểm version thay cho inbox. Inbox của template (ADR-0005) vẫn dùng cho các consumer khác.

### Khóa và isolation (C4)

- READ COMMITTED, `SELECT ... FOR UPDATE`. Không dùng `WHERE available >= :q`, vì BR-19 bắt luôn giữ tồn. Không dùng `@Version`, vì sẽ retry dồn dập khi flash sale.
- **Thứ tự khóa áp dụng cho mọi luồng**: các `stock_item` trước, theo `(master_sku_id, warehouse_id)`; sau đó là các `order_inventory_state`, theo `order_id`. Sau khi khóa một Order, đọc lại Available của các item khác của Order đó. Ở READ COMMITTED, câu lệnh mới thấy dữ liệu vừa commit, nên tránh được write skew khi hai người khai báo hai SKU của cùng một Short order.
- Ranh giới nguyên tử: mọi StockItem mà một Order chạm tới, cùng trạng thái của các Order liên quan. Đã cập nhật domain model.

### Short order (BR-19)

- Gắn cờ: lúc giữ tồn, khi có một dòng làm Available của item **đã khai báo** âm. Bút toán đó có `caused_oversell = true`.
- SKU chưa khai báo: không gắn cờ, không tính Oversell. Lúc khai báo lần đầu mà Available âm, gắn cờ cho **mọi** Order có Reservation mở trên item đó, và **không** tính Oversell. Đã sửa BR-19 và thêm AC trong SRS.
- Gỡ cờ: mọi thao tác làm Available của một item lên ≥ 0 đều có thể gỡ cờ của Order **khác** (khai báo, điều chỉnh, nhả tồn do Order khác hủy hoặc bỏ ghép). Thao tác đó khóa thêm `order_inventory_state` của các Short order có Reservation mở trên item, theo đúng thứ tự khóa ở trên, rồi gỡ cờ nếu mọi item liên quan đã ≥ 0.
- Event inventory → order mang trạng thái `(orderId, short, stateVersion)`, không mang lệnh bật/tắt, để order bỏ được event cũ. Ở G1 có thể mất event do dual-write (ADR-0005).

### Lệnh REST (F4.1b, F3.3c)

- "Đặt số tồn": compare-and-set trên `expectedOnHand`. Lệch thì trả `409` kèm On hand hiện tại (AC của F4.1b). Chấp nhận lỗi ABA. "Điều chỉnh" là delta nên không kiểm.
- Idempotency: FE sinh `Idempotency-Key` cho mỗi lần mở form. F3.3c dùng `f33c:<jobId>:<masterSkuId>`. Trùng key thì trả lại bút toán đã có.

### Bất biến (BR-29, N16)

- Job định kỳ (mặc định 5 phút, cấu hình được), chạy `REPEATABLE READ READ ONLY`. Với mỗi StockItem, kiểm `on_hand` = Σ delta On hand, và `reserved` = Σ delta Reservation = Σ `qty` của Reservation `Open`. Xuất metric `inventory_invariant_violations` và cảnh báo khi > 0. Không tự sửa. Ở G1 cộng toàn bộ sổ cái; bản tăng dần để sau khi đo thấy chậm. Không cần ShedLock vì job chỉ đọc.
- N16 (kill pod): mọi thay đổi của một event nằm trong một transaction. Offset chỉ được commit sau commit DB. Redelivery bị chặn bằng kiểm version.
- Chỉ số Oversell (N5) = số bút toán có `caused_oversell`, xuất thành metric bằng truy vấn định kỳ. Không dùng counter trong bộ nhớ.

### Để cho ticket khác

- Ticket 09: hình dạng của hai event trên (trạng thái đích kèm `orderVersion`; trạng thái Short order kèm `stateVersion`). Đã ghi comment ở ticket đó.
- Property-based test cho BR-29 (C14): chiến lược test G1, đang trong fog của map.
- Đơn luồng theo SKU và hot SKU: G5 (SRS chương 9), đã nằm ngoài phạm vi map.

## Comments
- 2026-11-12: Từ ticket [08 Giao tiếp giữa service ở G1](08-g1-communication.md#answer): inventory nhận dòng đơn đã có Master SKU qua Kafka, key theo Order, nên hai Order cùng Master SKU có thể ghi song song. inventory là nguồn sự thật của Short order và phát event khi trạng thái đổi. StockItem được tạo lúc lần đầu khai báo tồn (REST từ catalog, F3.3c) hoặc lần đầu giữ tồn.
