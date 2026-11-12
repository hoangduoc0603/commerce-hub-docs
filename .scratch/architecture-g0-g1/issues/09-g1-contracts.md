# 09 Contract và canonical model của G1

Type: grilling
Status: open
Blocked by: 08
Map: [Kiến trúc G0–G1](../map.md)

## Question

Ở G1 tồn tại những event và API nào (tên, service sở hữu, key, version)? Canonical model của Order, Listing, Master SKU, StockItem đủ cho G1 gồm những trường nào, và trường nào là của riêng sàn phải ở lại channel-connector (N13)? Đầu ra là danh sách contract để `/to-spec` viết thành `.avsc`/OpenAPI, không viết file contract ở đây.

## Comments
- 2026-11-12: Từ ticket [08 Giao tiếp giữa service ở G1](08-g1-communication.md#answer): bảng luồng G1 cần đặt tên event và key. Gồm: Order đã chuẩn hóa (connector → order), Listing đã kéo về (connector → catalog), ghép và bỏ ghép Listing (catalog → order), dòng đơn kèm Master SKU (order → inventory), Short order bật/tắt (inventory → order). Thêm một lệnh REST nội bộ: khai báo tồn ban đầu (catalog → inventory), idempotent theo (job, Master SKU). Avro và Schema Registry có ngay từ G1 ([ADR-0005](../../../adr/0005-kafka-from-g1-with-deliberate-dual-write.md)).
- 2026-11-12: Từ ticket [12 Kiến trúc shopee-sim](12-shopee-sim.md#answer): thêm OpenAPI của **admin API simulator** (tạo App, Shop, seed Listing, tạo và chuyển trạng thái đơn, "hết hạn ngay", ghi đè AS-xx) vào danh sách contract. **Không** viết OpenAPI cho API của Shopee: connector và simulator mỗi bên tự cài đặt từ tài liệu chính thức.
