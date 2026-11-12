---
status: accepted
date: 2026-11-12
---

# ADR-0002: Giữ tồn ngay khi thấy đơn, kể cả đơn chưa thanh toán

Cả TikTok Shop và Shopee đều trừ tồn bán được của listing ngay lúc người mua đặt hàng, trước khi thanh toán (xem [tra cứu 11/2026](../research/2026-11-marketplace-stock-reservation.md)). Vì vậy commerce-hub tạo Reservation cho mọi dòng đã ghép ngay khi lần đầu thấy Order ở bất kỳ trạng thái chưa hủy nào: UNPAID, ON_HOLD, PENDING, chờ duyệt COD đều tính. Reservation chỉ được nhả khi sàn báo Order đã hủy. Hệ thống không tự đặt hẹn giờ để hủy đơn chưa thanh toán, vì sàn là bên quyết định hủy và thời hạn thanh toán của cả hai sàn chưa xác minh được.

## Phương án đã cân nhắc

- **Chỉ giữ tồn khi đơn đã thanh toán.** Đây là cách nhiều người nghĩ tới đầu tiên, và một số OMS chỉ đồng bộ đơn trả trước sau khi khách thanh toán. Bị loại vì trong khoảng chờ thanh toán, sàn đã trừ tồn còn các kênh khác vẫn hiện số cũ, nên dễ Oversell nhất vào đúng lúc flash sale.

## Hệ quả

- Đơn chưa thanh toán mà bị hủy hàng loạt (khách bỏ giỏ) sẽ làm Available lên xuống liên tục. Chấp nhận, vì việc đẩy tồn đã được gộp theo Listing.
- Đơn phải được nhập vào hệ thống trước khi đẩy tồn lên sàn mà đơn đó thuộc về. Nếu không, số tuyệt đối đẩy lên sẽ trả lại phần sàn vừa trừ.
- Simulator phải trừ tồn lúc đặt hàng, kể cả với đơn UNPAID.
