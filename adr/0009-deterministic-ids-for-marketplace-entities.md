---
status: accepted
date: 2026-11-13
---

# ADR-0009: ID tất định (UUIDv5) khi hai context phải cùng biết một ID mà không gọi nhau

Thực thể có gốc ở sàn dùng ID **tất định**, do channel-connector tính bằng UUIDv5 từ khóa tự nhiên:

- `listingId = v5(shopId, mã sản phẩm trên sàn, mã biến thể trên sàn)`
- `orderId = v5(shopId, mã đơn của sàn)`
- `orderLineId = v5(orderId, listingId)`, vì mỗi (Order, Listing) có đúng một dòng đơn canonical

Warehouse mặc định của Workspace cũng theo nguyên tắc này: `warehouseId = v5(workspaceId, "default-warehouse")`. Nhờ vậy `workspace` (Scope của Role Kho), FE và inventory cùng biết ID của nó, dù inventory chỉ tạo Warehouse khi lần đầu chạm tới Workspace.

Mọi thực thể khác tạo bên trong hệ thống (Workspace, Shop, Master SKU, `eventId`…) dùng UUIDv7 do service sở hữu sinh ra.

Lý do: dòng đơn từ connector sang order chỉ mang mã của sàn, còn bản sao Mapping trong order thì theo Listing của catalog. Với ID tất định, cả hai luồng (`ChannelOrderSynced`, `ChannelListingSynced`) cho ra cùng một `listingId` mà không cần bảng tra. Khóa tự nhiên mang dáng của sàn chỉ nằm trong connector (N13). Hai context không phải trao đổi để thống nhất ID, nên không thêm REST đồng bộ hay event nào (ticket 08, quyết định 7). Bối cảnh ở ticket [09 Contract và canonical model của G1](../.scratch/architecture-g0-g1/issues/09-g1-contracts.md).

## Phương án đã cân nhắc

- **Consumer tự sinh ID (catalog sinh `listingId`, order sinh `orderId`).** Bị loại vì order phải tra Listing theo khóa phức hợp (Shop, mã sản phẩm, mã biến thể). Khóa này mang dáng của sàn và lan sang cả order lẫn catalog. Dòng đơn về trước Listing còn phải giữ khóa tự nhiên làm tham chiếu tạm.
- **connector giữ bảng registry cấp UUIDv7.** Bị loại vì connector có thêm trạng thái mà mất là sai: kéo lại sẽ ra ID khác. connector cũng phải đọc DB cho mỗi dòng đơn. Hiện connector không cần outbox chính vì nó không có trạng thái là nguồn sự thật (ADR-0005).
- **Warehouse mặc định do event `WorkspaceCreated` tạo ra.** Bị loại vì phải thêm một contract chỉ để `workspace` biết ID của Warehouse.

## Hệ quả

- Kết nối lại một Shop trong chính Workspace cũ (BR-09) cho ra lại đúng các ID cũ, vì `shopId` được giữ. Shop vào Workspace khác thì có `shopId` mới, nên mọi ID cũng mới (BR-08).
- UUIDv5 là ngẫu nhiên giống v4, nên insert vào B-tree kém cục bộ hơn v7. Ở G1 chuyện này không đáng kể. G5 (1 triệu đơn, 500 đơn/s) đo lại kích thước và độ phân mảnh index của `order` và `order_line`.
- Namespace UUID và cách nối chuỗi (thứ tự, ký tự phân cách) là một phần của contract. Đổi chúng thì mọi ID đổi theo, nên chúng được cố định trong repo `contracts`, kèm test với giá trị mẫu.
- Sàn đổi khóa tự nhiên (ví dụ Shopee cấp `model_id` mới khi người bán dựng lại biến thể) thì sinh ra Listing mới và mất Mapping. Cách sinh ID nào cũng gặp chuyện này. Kết quả giống như khi Listing mới về: BR-14 có thể tự ghép lại.
