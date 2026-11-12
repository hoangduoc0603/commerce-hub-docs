# Thời điểm sàn trừ tồn và giữ tồn (TikTok Shop, Shopee)

Tra cứu ngày 12/11/2026 để quyết định khi nào commerce-hub giữ tồn cho đơn từ sàn. Hai trang tài liệu chính thức render bằng JS, nên được đọc qua endpoint JSON công khai mà chính trang gọi (nội dung giống hệt trang).

Nhãn: **[CT]** tài liệu chính thức · **[TC]** nguồn thứ cấp · **[CXM]** chưa xác minh · **[SL]** suy luận.

## TikTok Shop

| Điểm | Kết luận | Nhãn |
|---|---|---|
| ON_HOLD | Xảy ra **sau khi thanh toán**, kéo dài 1 giờ. Trong lúc này mọi thao tác fulfillment lỗi 21011044 và địa chỉ người nhận trả về rỗng. Đơn không có ON_HOLD (`is_on_hold_order=FALSE`) vẫn phải đợi 1 giờ mới được ship. Bắt buộc cho mọi app từ Q1/2026 | CT |
| Khi đặt hàng | Webhook 71 `order_created`: tồn chuyển từ available sang **committed** | CT |
| Khi hủy | `order_canceled`: committed trả về available, **nhưng** phụ thuộc cờ `enable_auto_restock` của từng SKU (API `inventory/operation/settings` 202608; nếu bỏ trống khi gửi thì mặc định `false`) | CT |
| Khi ship | `order_shipped`: committed bị trừ hẳn | CT |
| Đơn UNPAID có commit tồn không | Rất có thể có, vì UNPAID là "order is placed". Tài liệu không ghi thẳng | SL |
| Thời hạn thanh toán UNPAID | Không tìm thấy | CXM |
| Đơn COD có bỏ qua UNPAID không | Không tìm thấy | CXM |
| Tồn giữ cho campaign/creator | Inventory Search có `committed_quantity` và `campaign_inventory`/`creator_inventory`. Đẩy tồn thấp hơn phần đang khóa thì lỗi 12052165 / 12052393. Hai tài liệu (webhook 27 và 71) mâu thuẫn về việc "available" có gồm phần giữ hay không | CT |
| Khuyến nghị của sàn | Chặn fulfillment khi ON_HOLD. Đẩy **số tuyệt đối**, không đẩy delta. Gộp thay đổi khi nhiều đơn. Đối soát định kỳ bằng Inventory Search | CT |

Nguồn: partner.tiktokshop.com/docv2/page/6969b89b40cf18049cb6eb42, 656d9d5fe87cdf02c1625d01, 6894134ba28e5204961601a5, 65b35776ba276602e1fab962, 6aaa6e4ad7ff2a050242b08e, 69e9cc34186bcf04b431d1f2, 650a9191c16ffe02b8eec161, 6aa1271d41c44a049f0bc1d4, 6503068fc20ad60284b38858, 672995e79ba2a002fe5dc92e, 6ad9fc9384a56d02d177ff3a. Academy VN: seller-vn.tiktok.com/university/essay?knowledge_id=6837776050571010.

## Shopee

| Điểm | Kết luận | Nhãn |
|---|---|---|
| Trạng thái | `UNPAID` = đơn đã tạo, chưa thanh toán. `PENDING` (chỉ trả khi gửi `request_order_status_pending=true`) có `pending_terms`: `SYSTEM_PENDING`, `KYC_PENDING`, `ARRANGE_SHIPMENT_PENDING`. `pay_time` là lúc chuyển UNPAID → PAID | CT |
| Khi đặt hàng | Tồn bị trừ thẳng vào `seller_stock`/`shopee_stock` lúc đặt hàng (FAQ 59) | CT |
| Đơn UNPAID có bị trừ không | Gần như chắc chắn có | SL |
| Khi hủy | Tồn promotion được trả lại (ví dụ trong push 8). Tồn thường: không có câu chính thức | CT / CXM |
| COD | Không bỏ qua giai đoạn chờ: `LOGISTICS_NOT_STARTED` = "pending COD verification (currently unpaid)"; có lý do hủy "COD Rejected" | CT |
| Thời hạn thanh toán | Không có nguồn chính thức | CXM |
| API tồn | `stock_info_v2`: `total_reserved_stock` **chỉ là tồn giữ cho promotion**, `total_available_stock`, `seller_stock[{location_id, stock}]`. Không có trường riêng cho tồn giữ bởi đơn. `update_stock` yêu cầu số mới ≥ tồn promotion đang giữ | CT |
| Push 8 `reserved_stock_change_push` | Chỉ phát khi đặt hoặc hủy đơn làm thay đổi tồn giữ cho promotion. Payload: `item_id`, `variation_id`, `changed_values`, `promotion_type`, `promotion_id`, `action` (`place_order`/`cancel_order`), `ordersn`, `update_time` | CT |

Nguồn: open.shopee.com/developer-guide/31, /229, /223; /documents/v2/v2.order.get_order_detail, v2.order.get_order_list; /faq/59, /140, /207; /push-mechanism/5.

## OMS khác ([TC])

- **BigSeller**: phân bổ tồn khi đơn về, trừ kho khi bấm Ship, tự nhả khi đơn hủy. Đơn trả trước chỉ đồng bộ sau khi khách thanh toán, đơn COD đồng bộ khi khách xác nhận (help.bigseller.pro/en_US/detailPage/4/3/24/content).
- **Ginee**: khóa tồn khi đơn về, trừ khi shipped (bài 18/12/2021).
- **Sapo, Nhanh.vn, KiotViet, Haravan**: không có tài liệu công khai đủ chi tiết.

## Hệ quả cho commerce-hub

1. Cả hai sàn trừ tồn bán được ngay lúc đặt hàng, nên commerce-hub giữ tồn ngay khi thấy đơn ở bất kỳ trạng thái chưa hủy nào, kể cả UNPAID. Nhả khi sàn báo hủy. Không tự đặt timer hủy đơn chưa thanh toán.
2. Phải nhập đơn **trước** khi đẩy tồn lên sàn đó. Nếu đẩy số tuyệt đối mà chưa tính đơn vừa về, ta sẽ trả lại phần sàn vừa trừ và gây Oversell.
3. Tồn sàn đang khóa cho promotion/campaign là ràng buộc dưới của số được đẩy. Đẩy thấp hơn thì sàn từ chối.
4. Không giả định TikTok tự hoàn tồn khi hủy. Vì hệ thống luôn đẩy số tuyệt đối từ Available, điều này không ảnh hưởng tính đúng, chỉ cần đẩy lại sau khi hủy.
5. Simulator phải tái hiện: commit tồn lúc đặt hàng (kể cả UNPAID), cửa sổ ON_HOLD 1 giờ, cờ auto-restock, tồn khóa cho promotion và lỗi từ chối cập nhật, COD screening.
6. Các điểm [CXM] được ghi vào SRS dưới dạng giả định, kèm cách kiểm chứng khi có sandbox.
