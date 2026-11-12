# 08 Giao tiếp giữa service ở G1

Type: grilling
Status: resolved
Blocked by: 02
Map: [Kiến trúc G0–G1](../map.md)

## Question

G1 chưa có outbox + Debezium (C18 đặt ở G2), nhưng đã có giữ tồn F4.2a và sổ cái F4.3a. Các luồng sau đi bằng gì ở G1:
- channel-connector → order (đơn kéo về, F5.2b, F5.2c)
- order → inventory (giữ, nhả tồn, F4.2a–b; [ADR-0002](../../../adr/0002-reserve-stock-on-first-sight.md))
- channel-connector → catalog (Listing, F3.2a), catalog ↔ inventory (ghép, F3.3)

Lựa chọn: REST đồng bộ ở G1 rồi chuyển sang Kafka ở G2; Kafka ngay từ G1 với polling publisher đơn giản; Kafka ngay với dual-write có chủ đích để G2 đo được lỗi. Chọn cách nào để G2 vẫn kể được câu chuyện "trước và sau outbox" (C19.2).

## Answer

Chốt ngày 2026-11-12 (người dùng), sau ba vòng grilling. Chọn **Kafka ngay từ G1, cố ý dual-write cho tới G2**: [ADR-0005](../../../adr/0005-kafka-from-g1-with-deliberate-dual-write.md).

### Bảng luồng G1

| Luồng | Cách | Nội dung (tên event, key, topic chốt ở ticket 09) | Phía phát |
|---|---|---|---|
| channel-connector → order | Kafka | Order đã chuẩn hóa (F5.2b poll, F5.2c) | gửi, chờ ack (`acks=all`), rồi dời checkpoint; không bao giờ cần outbox |
| channel-connector → catalog | Kafka | Listing đã kéo về (F3.2a) | như trên |
| catalog → order | Kafka | ghép, bỏ ghép Listing (F3.3a–b) | dual-write sau commit (G1), outbox (G2) |
| order → inventory | Kafka | dòng đơn kèm Master SKU: nhập, dòng được ghép hoặc bỏ ghép, hủy (F4.2a–b, BR-16, BR-20) | dual-write sau commit (G1), outbox (G2) |
| inventory → order | Kafka | Short order bật/tắt (BR-19) | dual-write sau commit (G1), outbox (G2) |
| catalog → inventory | REST lệnh | khai báo tồn ban đầu, idempotent theo (job, Master SKU) (F3.3c) | đồng bộ |
| FE → service | REST qua gateway | theo ticket 07 | — |

### Các quyết định

1. **Dual-write có chủ đích** chỉ áp dụng cho service mà DB của chính nó là nguồn sự thật: order, catalog, inventory. Dạng dual-write là gửi **sau commit**, nên khi hỏng thì mất event, không sinh event ma.
2. **Port publish**: code domain gọi `publish(event)` bên trong `@Transactional`. Bản G1 hoãn việc gửi tới `AFTER_COMMIT`, bản G2 ghi dòng outbox. Ticket 11 dựng port này trong template.
3. **channel-connector không bao giờ cần outbox**: sàn là nguồn sự thật và đọc lại được. Ở G1 không có `ShopConnected`: connector tự kéo Listing khi kết nối, còn FE đọc danh sách Shop qua REST của connector.
4. **order giữ bản sao Mapping** lấy từ event của catalog, và tự gắn Master SKU vào dòng đơn. inventory chỉ nhận dòng đã có Master SKU. BR-16 chạy theo choreography: catalog → order → inventory.
5. **inventory là nguồn sự thật của Short order**. Nó phát event khi trạng thái thiếu hàng của một Order đổi, còn order giữ bản sao để lọc (F5.1a).
6. **F3.3c theo thứ tự**: tạo Master SKU, gọi inventory khai báo tồn (REST), rồi mới tạo Mapping và phát event ghép. Làm ngược lại sẽ sinh Short order "ma" và làm chỉ số Oversell tăng sai. inventory tạo StockItem lúc lần đầu được khai báo tồn hoặc giữ tồn, nên catalog → inventory không cần event ở G1.
7. **Không có REST đọc đồng bộ giữa service ở G1.** Mỗi service giữ bản sao dữ liệu nó cần. FE (hoặc BFF, ticket 07) tự gom.
8. **Ràng buộc cho spec, tránh race nhập đơn và ghép Listing**: bản sao Mapping trong order có **một dòng cho mỗi Listing**, kể cả Listing chưa ghép. Lúc nhập đơn, transaction lấy `FOR SHARE` trên dòng của Listing. Lúc xử lý ghép hoặc bỏ ghép, transaction lấy `FOR UPDATE`. Nếu không làm vậy, dưới READ COMMITTED một dòng đơn có thể ở lại Unmapped line mãi mãi.

### Để cho ticket khác

- Tên event, key, topic, canonical model: ticket 09.
- Cách inventory ghi đồng thời: ticket 10. Event order → inventory key theo Order, nên hai Order cùng Master SKU vẫn có thể ghi song song.
- Retry và DLT của consumer, cùng bản cài đặt port publish: ticket 11.
- Cách đo dual-write ở G2 (failpoint giữa commit và gửi, bộ đếm Reservation thiếu): ngoài đích của map.

## Comments
- 2026-11-13: Từ ticket [05 Mô hình danh tính và Workspace trong token](05-identity-model.md#answer): `workspace` là service thứ tư cố ý dual-write theo ADR-0005 (phát event Member), kèm lệnh phát lại trạng thái của một Workspace ([ADR-0008](../../../adr/0008-keycloak-authn-only-members-replicated-via-kafka.md)).
