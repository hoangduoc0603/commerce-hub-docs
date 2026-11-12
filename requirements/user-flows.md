# commerce-hub: Luồng người dùng (P0)

- Phiên bản: 1.0, ngày 2026-11-12
- Mỗi luồng ghi rõ từng bước dùng yêu cầu nào trong [SRS](srs.md). Wireframe chỉ ở mức chữ; giao diện chi tiết được thiết kế khi làm frontend.

## Luồng 1: Onboarding, từ đăng ký tới khi tồn được đồng bộ

| # | Người dùng làm | Hệ thống làm | Yêu cầu |
|---|---|---|---|
| 1 | Đăng ký bằng email và mật khẩu, tick đồng ý chính sách | Gửi email có link xác minh | F1.1a |
| 2 | Bấm link xác minh trong email | Xác minh Account | F1.1a |
| 3 | Tạo Workspace "Shop Áo Nhà An" | Tạo Workspace, Warehouse mặc định, gán Owner | F1.1c, BR-17 |
| 4 | Bấm "Kết nối Shopee", đồng ý trên trang của sàn | Đổi mã lấy token, Shop `Active`, bắt đầu job kéo dữ liệu, hiện tiến độ | F2.1a, F2.4a |
| 5 | Kết nối thêm một shop TikTok | Như trên | F2.1a |
| 6 | Mở "Listing chưa ghép", thấy 120 Listing, chọn tất cả, bấm "Tạo Master SKU", tick "Lấy tồn trên sàn" | Gộp theo `seller_sku`, tạo khoảng 60 Master SKU, tự ghép, khai báo tồn theo số nhỏ nhất. Liệt kê 5 Listing không có `seller_sku` | F3.3c, BR-21 |
| 7 | Ghép tay 5 Listing còn lại | Ghép; giữ tồn bù cho các đơn đang mở | F3.3b, BR-16 |
| 8 | (không làm gì) | Với mọi Listing thỏa BR-22: tính Published stock, đẩy lên sàn | F4.1c |
| 9 | Mời nhân viên kho bằng email | Gửi lời mời, hiệu lực 7 ngày | F1.1d |

**Màn hình liên quan:** Đăng ký / Xác minh · Chọn Workspace · Shop (danh sách, nút kết nối, tiến độ kéo dữ liệu, hạn ủy quyền) · Listing (tab "Chưa ghép", hành động hàng loạt) · Master SKU · Tồn kho · Thành viên.

**Điểm cần chú ý:** ở bước 4–5, khi Master SKU chưa được khai báo tồn, hệ thống không chạm vào số tồn trên sàn (BR-21). Nhờ vậy shop vẫn bán bình thường trong lúc người dùng còn đang ghép hàng.

## Luồng 2: Một đơn bán ở Shopee làm giảm tồn ở TikTok

| # | Diễn biến | Yêu cầu |
|---|---|---|
| 1 | Người mua ảo đặt 2 SKU-A trên Shopee (`UNPAID`). Shopee trừ tồn Listing của nó | SIM-10 |
| 2 | Simulator gửi webhook. Hệ thống kiểm chữ ký, ghi bền, trả lời trong vài chục ms | F5.2a, BR-30 |
| 3 | Hệ thống lấy chi tiết đơn từ API, tạo Order `PendingPayment` | BR-31, BR-32 |
| 4 | Giữ tồn 2 SKU-A ngay, dù đơn chưa thanh toán | BR-18 |
| 5 | Available của SKU-A giảm 2 → đẩy số mới lên Listing TikTok (gộp nếu có nhiều đơn) | F4.1c, BR-24 |
| 6 | Người dùng thấy số đếm "Chờ thanh toán" tăng 1, không có thông báo riêng | F5.1a, F10.1a |

## Luồng 3: Xử lý đơn hằng ngày

| # | Người dùng làm | Hệ thống làm | Yêu cầu |
|---|---|---|---|
| 1 | Vận hành lọc "Chờ xử lý" | Danh sách đơn ở `ToProcess` thuộc các Shop trong phạm vi | F5.1a, F1.2b |
| 2 | Mở một đơn, bấm "Sắp xếp giao", chọn "Lấy tận nơi" | Kiểm BR-34, gửi lệnh idempotent, tạo Package | F6.1a, BR-35 |
| 3 | (chờ) | Mã vận đơn về, có thể muộn | F6.1b |
| 4 | Bấm "Tải vận đơn" | Chạy LabelJob, hiện tiến độ, rồi cho tải PDF | F6.1c |
| 5 | Nhân viên kho đánh dấu "Đã đóng gói", rồi "Đã bàn giao" | Trừ On hand (nếu sàn chưa báo `Shipping` trước đó), ghi bút toán | F4.2c, BR-27 |

**Trường hợp bị chặn:** đơn TikTok vừa thanh toán thì nút "Sắp xếp giao" bị vô hiệu, kèm dòng "Sàn đang giữ đơn, mở lúc 14:32". Đơn có Unmapped line thì nút dẫn sang màn hình ghép Listing.

## Luồng 4: Bán vượt (Short order)

| # | Diễn biến | Yêu cầu |
|---|---|---|
| 1 | SKU-B còn Available 1. Hai đơn ở hai Shop về cách nhau 200 ms, trước khi số mới kịp lên sàn | N3 |
| 2 | Cả hai đơn đều được giữ tồn; Available bằng −1; đơn thứ hai có cờ Short order; Oversell tăng 1 | BR-19 |
| 3 | Thông báo "Có đơn thiếu hàng" tới Vận hành và Kho | F10.1a |
| 4 | Người dùng chọn: nhập thêm hàng (khai báo tồn, cờ tự gỡ) hoặc hủy đơn trên sàn với lý do hết hàng | F4.1b, F5.4a |

## Luồng 5: Shop mất kết nối

| # | Diễn biến | Yêu cầu |
|---|---|---|
| 1 | Còn 7 ngày nữa là hết hạn ủy quyền: cờ "Sắp hết hạn", có thông báo trong app và email | F2.2b, BR-11 |
| 2 | Người dùng không xử lý. Tới hạn, lần làm mới token thất bại vĩnh viễn → `Disconnected`, lý do "Ủy quyền hết hạn" | F2.2a, BR-12 |
| 3 | Mọi lệnh tới Shop dừng; đơn và Listing chuyển chỉ đọc; Reservation giữ nguyên | F2.3a |
| 4 | Người dùng bấm "Ủy quyền lại" hai ngày sau | F2.1a |
| 5 | Shop `Active` trở lại, kéo bù đơn trong hai ngày, đẩy lại tồn cho mọi Listing thỏa BR-22 | BR-09, F2.4a, F4.1c |

## Luồng 6: Người mua yêu cầu hủy

| # | Diễn biến | Yêu cầu |
|---|---|---|
| 1 | Đơn `ToProcess` nhận yêu cầu hủy → cờ "Có yêu cầu hủy"; nút "Sắp xếp giao" bị chặn | F5.4b, BR-34 |
| 2 | Vận hành bấm "Chấp nhận" | F5.4b |
| 3 | Sàn chuyển đơn `CANCELLED` → Order `Cancelled`, nhả tồn, đẩy số mới lên các Shop | F4.2b, F4.1c |
