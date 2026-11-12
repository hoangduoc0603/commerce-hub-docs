---
status: accepted
date: 2026-11-13
---

# ADR-0007: Bảng số dư cộng sổ cái trong cùng transaction, khóa bi quan theo thứ tự cố định

inventory lưu ba thứ trong cùng một transaction: số dư của từng StockItem (On hand, tổng Reservation, đã khai báo tồn hay chưa), các Reservation theo dòng đơn, và sổ cái LedgerEntry chỉ được thêm (BR-28). Khi ba biểu diễn này lệch nhau thì **sổ cái thắng**, còn số dư chỉ là snapshot dựng lại được từ sổ cái. BR-29 vì vậy là một kiểm tra thật: một job đọc cả ba trên cùng một snapshot (`REPEATABLE READ READ ONLY`), cảnh báo khi lệch, và không tự sửa.

Ghi đồng thời dùng `SELECT ... FOR UPDATE` dưới READ COMMITTED. Mọi luồng khóa theo cùng một thứ tự: các StockItem trước, theo (Master SKU, Warehouse); sau đó là trạng thái giữ tồn của các Order liên quan, theo order id. Mỗi event Order là một transaction và chạm mọi StockItem của Order đó, vì Short order là trạng thái theo Order (BR-19).

Bối cảnh ở ticket [10 Mô hình ghi của inventory ở G1](../.scratch/architecture-g0-g1/issues/10-inventory-write-model.md).

## Phương án đã cân nhắc

- **Event sourcing thuần (C3): chỉ có sổ cái, số dư tính bằng cách cộng dồn, có snapshot.** Bị loại vì chỉ có một biểu diễn thì BR-29 đúng hiển nhiên, không còn gì để kiểm. Thêm nữa, để chống ghi đồng thời phải khóa một thứ khác dòng số dư (advisory lock hoặc unique theo số thứ tự kèm retry), khó suy luận hơn.
- **Atomic update có điều kiện (C4: `... WHERE available >= :q`).** Không dùng được, vì BR-19 bắt luôn giữ tồn kể cả khi Available âm. Bản không điều kiện (`UPDATE ... RETURNING` từng item) vẫn đúng, nhưng một Order nhiều SKU thì phải tự sắp thứ tự từng câu và chen logic Short order vào giữa SQL.
- **Optimistic locking (`@Version`).** Bị loại vì lúc flash sale, hai Order cùng SKU về từ hai partition (event key theo Order, ticket 08) sẽ conflict và retry dồn dập.
- **Đơn luồng theo SKU nhờ partition Kafka (C3, C4).** Để lại cho G5. Event order → inventory key theo Order, nên muốn vậy phải thêm một topic chia lại theo SKU. Đây là thí nghiệm hot SKU của SRS chương 9.

## Hệ quả

- SKU nóng bị tuần tự hóa qua khóa dòng `stock_item`. Ở G1 chấp nhận được. G5 đo lại và so với đơn luồng theo SKU.
- Mọi luồng mới ghi vào inventory phải theo đúng thứ tự khóa trên. Nếu không sẽ deadlock với luồng giữ tồn, hoặc bị write skew khi gỡ cờ Short order.
- Sửa sai luôn là thêm bút toán đối ứng. Không có công cụ "dựng lại số dư" ở G1. Lệch thì cảnh báo, và người vận hành tự điều tra.
