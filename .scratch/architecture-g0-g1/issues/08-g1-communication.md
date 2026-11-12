# 08 Giao tiếp giữa service ở G1

Type: grilling
Status: open
Blocked by: 02
Map: [Kiến trúc G0–G1](../map.md)

## Question

G1 chưa có outbox + Debezium (C18 đặt ở G2), nhưng đã có giữ tồn F4.2a và sổ cái F4.3a. Các luồng sau đi bằng gì ở G1:
- channel-connector → order (đơn kéo về, F5.2b, F5.2c)
- order → inventory (giữ, nhả tồn, F4.2a–b; [ADR-0002](../../../adr/0002-reserve-stock-on-first-sight.md))
- channel-connector → catalog (Listing, F3.2a), catalog ↔ inventory (ghép, F3.3)

Lựa chọn: REST đồng bộ ở G1 rồi chuyển sang Kafka ở G2; Kafka ngay từ G1 với polling publisher đơn giản; Kafka ngay với dual-write có chủ đích để G2 đo được lỗi. Chọn cách nào để G2 vẫn kể được câu chuyện "trước và sau outbox" (C19.2).
