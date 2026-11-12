# commerce-hub

Ngôn ngữ chung của commerce-hub, hệ thống SaaS quản lý bán hàng đa sàn: một nhà bán quản lý sản phẩm, tồn kho và đơn hàng từ nhiều shop trên TikTok Shop, Shopee ở một nơi.

## Người dùng và không gian làm việc

**Account**:
Danh tính đăng nhập của một người, định danh bằng một email. Một Account tồn tại độc lập với mọi Workspace.
_Avoid_: User (khi muốn nói danh tính), login

**Workspace**:
Không gian làm việc của một nhà bán, đồng thời là ranh giới cô lập dữ liệu duy nhất. Mọi Shop, Warehouse, Master SKU, Order đều thuộc đúng một Workspace.
_Avoid_: Tenant (chỉ dùng khi nói về kiến trúc multi-tenant), organization, company, store

**Member**:
Một Account tham gia một Workspace với một hoặc nhiều Role. Một Account có thể là Member của nhiều Workspace.
_Avoid_: Membership, employee, staff, user

**Role**:
Vai trò cố định mà một Member giữ trong Workspace, quyết định Member được làm gì: Owner, Quản lý, Vận hành, Kho, Kế toán.
_Avoid_: Permission (một Role gồm nhiều quyền), group

**Scope**:
Phạm vi một Role của Member áp dụng: Vận hành áp dụng cho mọi Shop hoặc một danh sách Shop, Kho áp dụng cho mọi Warehouse hoặc một danh sách Warehouse. Ngoài Scope, Member không thấy dữ liệu.
_Avoid_: Quyền hạn, phân vùng

**Owner**:
Member đã tạo Workspace, có toàn quyền trên Workspace đó. Mỗi Workspace có đúng một Owner, và Owner không bao giờ đổi.
_Avoid_: Admin (dễ nhầm với Platform Admin)

**Platform Admin**:
Người thuộc đội vận hành commerce-hub, quản lý mọi Workspace. Không phải Member của Workspace nào.
_Avoid_: Admin, superuser

## Kênh bán

**Marketplace**:
Một sàn thương mại điện tử mà hệ thống tích hợp (TikTok Shop, Shopee). Trong dự án, mỗi Marketplace được thay bằng một Simulator.
_Avoid_: Platform, sàn (trong tài liệu tiếng Anh)

**Channel**:
Một nguồn đơn hàng: một Marketplace hoặc kênh bán riêng của nhà bán.
_Avoid_: Source

**Shop**:
Một gian hàng cụ thể trên một Marketplace mà Workspace đã được ủy quyền truy cập. Một Workspace có nhiều Shop, kể cả nhiều Shop trên cùng Marketplace.
_Avoid_: Channel account, store, seller account

**Simulator**:
Bản giả lập một Marketplace hoặc hãng vận chuyển, tái hiện hành vi thật của nó (kể cả lỗi) để hệ thống được kiểm chứng như khi chạy với sàn thật.
_Avoid_: Mock, stub, fake

## Sản phẩm

**Master SKU**:
Đơn vị hàng hóa gốc trong Workspace, là đơn vị quản lý tồn kho.
_Avoid_: Product (khi muốn nói đơn vị tồn kho), item, variant

**Listing**:
Một sản phẩm hoặc biến thể đang đăng trên một Shop (TikTok: SKU; Shopee: model).
_Avoid_: Product, item, offer

**Mapping**:
Liên kết giữa một Listing và một Master SKU. Listing không có Mapping thì không được đồng bộ tồn kho.
_Avoid_: Link, binding

## Tồn kho

**Warehouse**:
Một địa điểm chứa hàng của Workspace. Mọi con số tồn kho đều tính theo Warehouse.
_Avoid_: Location, store

**On hand**:
Số lượng thực có của một Master SKU trong một Warehouse.
_Avoid_: Stock, quantity

**Reservation**:
Phần tồn đang giữ cho một dòng đơn chưa xuất kho.
_Avoid_: Hold, lock, allocation

**Available**:
Số còn bán được: On hand trừ Reservation và safety stock. Có thể âm khi đã bán vượt.
_Avoid_: Sellable, free stock

**Published stock**:
Số tồn hệ thống đẩy lên một Listing, tính từ Available theo quy tắc phân bổ. Hệ thống là nguồn sự thật: số trên sàn lệch với Published stock thì bị ghi đè.
_Avoid_: Channel stock, platform stock

**Oversell**:
Tình huống đơn đã bán vượt số thực có, thể hiện bằng Available âm.
_Avoid_: Overselling, negative stock

## Đơn hàng

**Order**:
Một đơn hàng từ một Channel, được biểu diễn theo mô hình chung không phụ thuộc sàn.
_Avoid_: Purchase, transaction, channel order

**Package**:
Một kiện hàng được giao của một Order, gắn với một vận đơn. Một Order có thể có nhiều Package. Package theo dõi công việc trong kho (nhặt, đóng gói, bàn giao), còn trạng thái của Order phản ánh trạng thái trên sàn.
_Avoid_: Parcel, shipment (khi muốn nói kiện hàng), kiện

**Unmapped line**:
Dòng đơn thuộc một Listing chưa có Mapping. Dòng này chưa được giữ tồn, và Order chứa nó chưa được xử lý giao.
_Avoid_: Unknown item, orphan line

**Short order**:
Order đã giữ tồn vượt quá số thực có (làm Available âm), chờ người vận hành quyết định. Hệ thống không tự hủy Order trên sàn.
_Avoid_: Backorder, out-of-stock order
