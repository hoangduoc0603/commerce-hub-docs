# 17 channel-connector ở G1: polling đơn và mã hóa token sàn

Type: grilling
Status: open
Blocked by:
Map: [Kiến trúc G0–G1](../map.md)

## Question

Hai phần của `channel-connector` mà G1 cần nhưng chưa ticket nào chốt (lộ ra ở ticket [14](14-arc42-c4.md)):

- **Polling đơn F5.2b** (N4, SIM-08): job chạy đơn instance (ShedLock?) hay chia theo Shop; lịch chạy và cửa sổ chồng lấn; checkpoint lưu ở đâu và theo khóa nào (Shop × loại dữ liệu). Thứ tự đã chốt ở ticket [08](08-g1-communication.md#answer): gửi, chờ ack, rồi mới dời checkpoint. Kéo dữ liệu ban đầu F2.4a ở G1 dùng chung cơ chế này hay riêng.
- **Mã hóa token sàn khi lưu** (N11, BR-10): khóa nằm ở đâu (Sealed Secret, KMS không có ở lab), mã hóa theo trường hay theo hàng, xoay khóa thế nào. `seller-web` đã có mẫu AES-GCM kèm `key_id` ở [ADR-0011](../../../adr/0011-nextjs-bff-with-server-side-session.md); dùng lại mẫu đó hay khác.
