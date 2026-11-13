---
status: accepted
date: 2026-11-12
---

# ADR-0005: Dùng Kafka giữa service ngay từ Giai đoạn 1, cố ý dual-write cho tới Giai đoạn 2

Ở Giai đoạn 1, mọi luồng giữa các service đều đi qua Kafka, trừ một lệnh REST nội bộ là catalog gọi inventory để khai báo tồn ban đầu (F3.3c). Lý do là Kafka đã có từ Giai đoạn 0 (C18), và giữ tồn (F4.2a–b) ở Giai đoạn 1 đã cần idempotent consumer.

Ở Giai đoạn 1, những service lấy DB của chính mình làm nguồn sự thật (order, catalog, inventory) **cố ý dual-write**. Chúng commit transaction rồi mới gửi event, không có outbox. Giai đoạn 2 thay phần gửi này bằng outbox + Debezium, và đo số event bị mất trước và sau. Đó là câu chuyện C19.2. Muốn kể được nó, phải có một bản "trước" chạy thật, có cùng contract và cùng consumer, chỉ khác phía phát.

Code domain luôn gọi một port publish duy nhất **bên trong** transaction. Ở Giai đoạn 1, port này hoãn việc gửi tới sau commit (`@TransactionalEventListener(AFTER_COMMIT)`). Ở Giai đoạn 2, nó ghi một dòng outbox trong cùng transaction. Chỗ gọi giữ nguyên, chỉ đổi bean.

channel-connector **không** dual-write và không bao giờ cần outbox. Dữ liệu nó phát (Order, Listing) có nguồn sự thật ở sàn và đọc lại được. Quy tắc của nó là: gửi, chờ broker ack, rồi mới dời checkpoint. Crash ở giữa thì gửi lại, còn consumer xử lý trùng nhờ đã idempotent (BR-20, BR-31).

Bối cảnh ở ticket [08 Giao tiếp giữa service ở G1](../.scratch/architecture-g0-g1/issues/08-g1-communication.md).

## Phương án đã cân nhắc

- **REST đồng bộ ở Giai đoạn 1, chuyển sang Kafka ở Giai đoạn 2.** Bị loại vì hai lý do. Thứ nhất, Giai đoạn 2 sẽ đổi cùng lúc cách truyền và outbox, nên phép đo không còn tách được phần đóng góp của outbox. Thứ hai, các luồng order → inventory phải viết hai lần.
- **Kafka ngay, kèm polling publisher.** Polling publisher đã là outbox (job quét bảng outbox). Như vậy không còn bản "trước outbox" để đo, chỉ so được polling với Debezium.
- **Dual-write bằng cách gửi trong transaction, trước commit.** Bị loại vì lỗi của nó là event ma (Reservation cho Order không tồn tại). Gửi sau commit là cách một dev cẩn thận hay viết, và lỗi của nó là mất event: đúng thứ C19.2 muốn kể.

## Hệ quả

- Ở Giai đoạn 1, crash giữa commit và gửi làm mất event. Nếu mất event đơn mới từ order, kéo bù (F5.2b) **không** vá được. Order đã lưu với cùng `update_time` nên bị bỏ qua, Reservation thiếu mãi, và Oversell xảy ra mà không ai thấy. Chấp nhận được vì Giai đoạn 1 chưa đo N5 (bắt đầu ở Giai đoạn 2). Không được chạy Giai đoạn 1 như bản production.
- Giai đoạn 2 chỉ được thay bản cài đặt của port publish. Nếu phải sửa code domain thì nghĩa là ranh giới port đã bị rò.
- Contract Avro, Schema Registry và idempotent consumer (bảng inbox) có ngay từ Giai đoạn 1, sớm hơn C18.

## Sửa đổi

- 2026-11-13 ([ticket 11](../.scratch/architecture-g0-g1/issues/11-service-template.md)): ở Giai đoạn 1 **không có bảng inbox**. Cả sáu event G1 đều mang trạng thái đầy đủ kèm version ([ticket 09](../.scratch/architecture-g0-g1/issues/09-g1-contracts.md)), nên consumer idempotent bằng version guard (upsert `WHERE stored_version < :v`). Inbox quay lại khi có event không mang trạng thái (lệnh, thông báo, từ Giai đoạn 2).
