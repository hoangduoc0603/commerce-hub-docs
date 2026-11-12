# 10 Mô hình ghi của inventory ở G1

Type: grilling
Status: open
Blocked by: 08
Map: [Kiến trúc G0–G1](../map.md)

## Question

StockItem, Reservation và sổ cái (F4.1a–b, F4.2a–b, F4.3a) lưu thế nào ở G1: sổ cái là nguồn sự thật (event sourcing giới hạn, C3) hay bảng số dư cộng bảng bút toán? Ghi đồng thời bằng atomic update có điều kiện, optimistic locking hay `SELECT FOR UPDATE` (C4)? Bất biến nào phải kiểm (N16), và idempotency của lệnh giữ tồn theo khóa nào (BR liên quan, ADR-0002).

## Comments
- 2026-11-12: Từ ticket [08 Giao tiếp giữa service ở G1](08-g1-communication.md#answer): inventory nhận dòng đơn đã có Master SKU qua Kafka, key theo Order, nên hai Order cùng Master SKU có thể ghi song song. inventory là nguồn sự thật của Short order và phát event khi trạng thái đổi. StockItem được tạo lúc lần đầu khai báo tồn (REST từ catalog, F3.3c) hoặc lần đầu giữ tồn.
