# commerce-hub: Đặc tả yêu cầu phần mềm (SRS)

- Phiên bản: 1.1
- Ngày: 2026-11-13 (1.1: BR-19 với Master SKU chưa khai báo tồn, ticket 10 của map kiến trúc G0–G1)
- Trạng thái: Đã chốt cho P0
- Liên quan: [Project Charter](../project-charter.md) · [Glossary](../GLOSSARY.md) · [Domain model](domain-model.md) · [Luồng người dùng](user-flows.md) · [Ma trận truy vết](traceability.md) · [Kỹ thuật áp dụng](../requirements-and-techniques.md)

---

## 1. Giới thiệu

### 1.1 Mục đích

Tài liệu này đặc tả **hệ thống phải làm gì**, ở mức có thể kiểm thử. Đặc tả **làm thế nào** (service, công nghệ, pattern) nằm ở Phần B và C của [tài liệu kỹ thuật](../requirements-and-techniques.md), và sẽ được viết lại thành tài liệu kiến trúc ở phase thiết kế.

Dự án là dự án học (xem [Charter](../project-charter.md)). Nghiệp vụ được giữ ở mức vừa đủ. Mỗi yêu cầu P0 có ghi **Case kỹ thuật**: tình huống production mà yêu cầu đó buộc hệ thống phải xử lý, kèm mục tương ứng trong Phần C.

### 1.2 Phạm vi

commerce-hub là SaaS quản lý bán hàng đa sàn. Nhà bán đăng ký Account, tạo Workspace, mời nhân viên và kết nối nhiều Shop trên TikTok Shop và Shopee. Hệ thống:
- gom Listing về và ghép với Master SKU;
- giữ một nguồn tồn kho chung, đẩy số tồn lên mọi Shop;
- gom Order từ mọi Shop về một nơi;
- hỗ trợ xử lý đơn tới khi có vận đơn.

Sàn thật được thay bằng **Simulator** tương thích API (chương 8).

### 1.3 Quy ước

| Ký hiệu | Nghĩa |
|---|---|
| **P0 / P1 / P2** | P0: MVP, đặc tả chi tiết trong tài liệu này. P1: bản đầy đủ. P2: mở rộng. P1 và P2 chỉ được liệt kê (chương 6) |
| **F1.1a** | Yêu cầu chức năng. Phần số là mã tính năng (F1–F10, cũng là mã Phần C của [tài liệu kỹ thuật](../requirements-and-techniques.md) dùng), chữ cái là yêu cầu con. Mọi mã tính năng có ở chương 3 (P0) hoặc chương 6 (P1/P2) |
| **BR-xx** | Quy tắc nghiệp vụ. Mỗi quy tắc được định nghĩa một lần, tại yêu cầu đầu tiên dùng nó. Chương 5 có bảng tổng hợp |
| **N-xx** | Yêu cầu phi chức năng |
| **SIM-xx** | Yêu cầu cho Simulator |
| **PA-x** | Yêu cầu cho Platform Admin |
| **AS-xx** | Giả định, thường thay cho thông tin về sàn chưa xác minh được (chương 9) |
| **AC** | Tiêu chí nghiệm thu, viết dạng Given / When / Then |

Thuật ngữ in đậm hoặc viết hoa chữ đầu (Workspace, Listing, Available…) dùng đúng nghĩa trong [GLOSSARY.md](../GLOSSARY.md).

---

## 2. Mô tả tổng quan

### 2.1 Bối cảnh hệ thống

```
   Owner / Member (trình duyệt)          Platform Admin (trình duyệt)
                 │                                  │
                 ▼                                  ▼
        ┌──────────────────────── commerce-hub ─────────────────────┐
        │  Account · Workspace · Shop · Catalog · Inventory · Order │
        │  Package · Notification                                   │
        └───────┬───────────────────────┬───────────────────┬──────┘
         OAuth, Open API,         Webhook (push)         SMTP
         ký HMAC                  ký HMAC                  │
                ▼                       │                  ▼
      ┌───────────────── Simulator ─────┴──┐         Hộp thư (Mailpit
      │  tiktok-sim · shopee-sim           │          khi dev)
      │  + người mua ảo, chaos, bộ đếm     │
      └────────────────────────────────────┘
```

### 2.2 Người dùng

| Vai trò | Thuộc | Làm gì trong P0 |
|---|---|---|
| **Owner** | Workspace | Toàn quyền, kể cả xóa Workspace. Mỗi Workspace có đúng một Owner và không đổi được |
| **Quản lý** | Workspace | Mọi việc trừ xóa Workspace và gỡ Owner |
| **Vận hành** | Workspace, giới hạn theo Shop | Xử lý đơn và giao hàng, ghép Listing |
| **Kho** | Workspace, giới hạn theo Warehouse | Khai báo và điều chỉnh tồn, đóng gói, bàn giao Package |
| **Kế toán** | Workspace | Chỉ xem đơn và tồn (P0). Báo cáo tài chính ở P1/P2 |
| **Platform Admin** | Hệ thống | Quản lý Workspace, theo dõi tích hợp, xử lý hàng đợi lỗi |

Bảng quyền chi tiết ở F1.2a.

### 2.3 Môi trường vận hành

- Ứng dụng web cho desktop, độ rộng từ 1280 px trở lên, chạy trên hai phiên bản mới nhất của Chrome, Edge và Safari. Giao diện cho điện thoại để P2.
- Giao diện tiếng Việt. Hiển thị giờ theo Asia/Ho_Chi_Minh, tiền theo VND.
- Chạy trên cụm Kubernetes home lab. Simulator chạy trong cùng cụm hoặc ở máy khác.

### 2.4 Ràng buộc

- Không kết nối sàn thật (Charter mục 3). Mọi thông số về sàn lấy từ tài liệu chính thức tra ngày 11/2026 ([A2](../requirements-and-techniques.md#a2-đặc-điểm-các-sàn-ảnh-hưởng-tới-thiết-kế), [tra cứu tồn kho](../research/2026-11-marketplace-stock-reservation.md)).
- Đăng nhập chỉ bằng email và mật khẩu, qua chuẩn OIDC.
- Chỉ có một Warehouse mặc định cho mỗi Workspace. Mô hình dữ liệu vẫn tính theo Warehouse (BR-17).

---

## 3. Yêu cầu chức năng P0

### F1. Account, Workspace, phân quyền

#### F1.1a Đăng ký và xác minh Account

- Người dùng đăng ký bằng email và mật khẩu, và phải tick đồng ý chính sách xử lý dữ liệu cá nhân (Nghị định 13/2023). Thời điểm đồng ý và phiên bản chính sách được lưu lại.
- **BR-01:** Email là định danh duy nhất của Account trên toàn hệ thống, so sánh không phân biệt hoa thường và bỏ khoảng trắng hai đầu.
- Mật khẩu tối thiểu 10 ký tự, và không được nằm trong danh sách mật khẩu phổ biến.
- Email được xác minh bằng mã OTP 6 chữ số, hiệu lực 10 phút, gửi lại tối đa 5 lần mỗi giờ. Account chưa xác minh đăng nhập được nhưng không tạo được Workspace và không chấp nhận được lời mời.

AC:
- Given đã có Account `an@shop.vn`, When đăng ký bằng `AN@shop.vn `, Then bị từ chối với thông báo email đã được dùng.
- Given OTP gửi lúc 10:00, When nhập đúng mã lúc 10:11, Then báo mã hết hạn và cho gửi lại.

Case kỹ thuật: OIDC với Keycloak (C9). Gửi email qua hàng đợi, có retry (C3).

#### F1.1b Đăng nhập, quên mật khẩu

- Đăng nhập bằng email và mật khẩu.
- Quên mật khẩu: gửi link đặt lại qua email, link hiệu lực 30 phút và chỉ dùng một lần. Đặt lại mật khẩu xong thì mọi phiên đăng nhập khác bị đăng xuất.
- **BR-02:** Sai mật khẩu 5 lần liên tiếp trong 15 phút thì Account bị khóa đăng nhập 15 phút.

AC: Given Account đang đăng nhập trên hai trình duyệt, When đặt lại mật khẩu ở trình duyệt thứ nhất, Then trình duyệt thứ hai bị đăng xuất ở request kế tiếp.

#### F1.1c Tạo và chuyển Workspace

- Account đã xác minh tạo Workspace bằng một tên. Người tạo trở thành Owner.
- **BR-03:** Một Account là Owner của tối đa 5 Workspace chưa bị xóa. Platform Admin nâng được hạn mức này cho từng Account (PA-4).
- Mỗi Workspace có hạn mức mặc định: 50 Shop, 50 Member, 100.000 Master SKU. Platform Admin nâng được.
- Sau khi đăng nhập, người dùng chọn Workspace để làm việc trong số các Workspace mình là Member. Chỉ thuộc một Workspace thì vào thẳng.
- **BR-04:** Mọi thao tác và mọi dữ liệu đều thuộc đúng một Workspace. Member của Workspace A không thấy được bất kỳ dữ liệu nào của Workspace B, kể cả qua API, file tải về, thông báo hay thông báo lỗi.

AC: Given Member của A biết ID một Order của B, When gọi API xem Order đó, Then nhận 404 (không phải 403), và không có dữ liệu nào của B lộ ra.

Case kỹ thuật: Multi-tenancy, lọc theo workspace và Row-Level Security (C8), kiểm thử cô lập.

#### F1.1d Mời Member

- Owner hoặc Quản lý mời bằng email, chọn vai trò và phạm vi.
- Lời mời hiệu lực 7 ngày. Người mời thu hồi được lời mời chưa được chấp nhận.
- Người được mời đã có Account thì đăng nhập và chấp nhận. Chưa có Account thì đăng ký qua link mời, với email bị cố định đúng email được mời.
- Mời một email đã là Member thì báo lỗi. Mời lại một email đang có lời mời thì lời mời cũ bị hủy và tạo lời mời mới.

AC: Given lời mời gửi ngày 01/12, When bấm link ngày 09/12, Then báo hết hạn, và không tạo Membership nào.

#### F1.1e Xóa Workspace và Account

- Chỉ Owner xóa được Workspace, phải nhập lại tên Workspace để xác nhận.
- **BR-05:** Workspace bị xóa sẽ:
  - (1) lập tức chuyển mọi Shop sang `Disconnected`, lý do "Workspace bị xóa";
  - (2) Member không truy cập được nữa;
  - (3) Owner khôi phục được trong 30 ngày, nhưng Shop vẫn ở `Disconnected` và phải kết nối lại;
  - (4) sau 30 ngày, toàn bộ dữ liệu bị xóa hẳn, kể cả thông tin cá nhân người mua.
- **BR-06:** Không xóa được Account khi người đó còn là Owner của một Workspace chưa bị xóa. Xóa Account thì Account bị gỡ khỏi mọi Workspace mình là Member.

AC: Given Workspace bị xóa ngày 01/12, When job dọn dữ liệu chạy ngày 31/12, Then không còn bản ghi nào gắn với Workspace đó trong mọi kho dữ liệu, kể cả search index, file PDF và cache.

Case kỹ thuật: Xóa dữ liệu phân tán qua nhiều service theo event, chứng minh được đã xóa hết (C3, C9).

#### F1.2a Vai trò và quyền

Vai trò cố định, một Member có thể giữ nhiều vai trò.

| Hành động | Owner | Quản lý | Vận hành | Kho | Kế toán |
|---|---|---|---|---|---|
| Xóa, khôi phục Workspace | ✓ | | | | |
| Mời, gỡ Member, đổi vai trò | ✓ | ✓ (trừ Owner) | | | |
| Kết nối, ngắt kết nối Shop | ✓ | ✓ | | | |
| Tạo, sửa Master SKU; ghép Listing | ✓ | ✓ | ✓ | | |
| Khai báo, điều chỉnh tồn | ✓ | ✓ | | ✓ | |
| Xem đơn | ✓ | ✓ | ✓ | ✓ | ✓ |
| Hủy đơn, duyệt yêu cầu hủy, sắp xếp giao, tải vận đơn | ✓ | ✓ | ✓ | | |
| Đóng gói, bàn giao Package | ✓ | ✓ | ✓ | ✓ | |

#### F1.2b Phạm vi theo Shop và Warehouse

- Vai trò Vận hành có phạm vi là "mọi Shop" hoặc một danh sách Shop. Member chỉ thấy và thao tác được trên Order và Listing của các Shop trong phạm vi.
- Vai trò Kho có phạm vi là "mọi Warehouse" hoặc một danh sách Warehouse. Ở P0 chỉ có một Warehouse.

#### F1.2c Thay đổi quyền có hiệu lực ngay

- **BR-07:** Gỡ Member hoặc thu hẹp quyền có hiệu lực từ request kế tiếp, tối đa 5 giây, không phải đợi token đăng nhập hết hạn. Kết nối real-time (thông báo) của Member đó bị đóng.

AC: Given Member đang mở danh sách đơn, When Owner gỡ Member, Then trong 5 giây mọi request tiếp theo của Member bị từ chối và luồng thông báo bị ngắt.

Case kỹ thuật: Thu hồi quyền khi dùng JWT không trạng thái, ví dụ token sống ngắn kết hợp danh sách thu hồi hoặc kiểm tra phiên (C9).

---

### F2. Kết nối Shop

#### F2.1a Kết nối Shop qua OAuth

Luồng: chọn sàn → chuyển sang trang ủy quyền của sàn (Simulator) → nhà bán đồng ý → sàn chuyển về kèm mã ủy quyền → hệ thống đổi mã lấy token → Shop ở trạng thái `Active`.

- Mã ủy quyền dùng một lần. Shopee: hết hạn sau 10 phút. TikTok: sau 30 phút.
- Luồng có tham số `state` để chống giả mạo (CSRF). Callback mà sai `state` thì bị từ chối.
- **BR-08:** Một Shop (định danh bằng sàn và shop_id của sàn) chỉ thuộc một Workspace tại một thời điểm. Kết nối một Shop đang thuộc Workspace khác thì bị từ chối, kèm hướng dẫn ngắt kết nối ở nơi cũ trước. Hệ thống không tiết lộ Workspace cũ là của ai.
- **BR-09:** Kết nối lại một Shop từng thuộc chính Workspace này thì dùng lại mọi dữ liệu cũ (Listing, Mapping, Order), rồi chạy kéo bù (F2.4a) cho khoảng thời gian đã bị ngắt.
- Vượt hạn mức số Shop thì bị từ chối trước khi chuyển sang sàn.

AC:
- Given hai Workspace A và B, When B kết nối shop Shopee `shop_id=123` đang `Active` ở A, Then B nhận lỗi và A không bị ảnh hưởng gì.
- Given callback đã dùng mã `code=X`, When trình duyệt gửi lại đúng callback đó, Then không tạo kết nối thứ hai và không có lỗi nào lọt ra giao diện.

Case kỹ thuật: OAuth authorization code, idempotent callback, ràng buộc duy nhất giữa các Workspace (C5.3).

#### F2.2a Tự làm mới token

- Hệ thống làm mới access token **trước** khi hết hạn: Shopee 4 giờ, TikTok 7 ngày. Không đợi đến khi gặp lỗi 401.
- **BR-10:** Tại mọi thời điểm, mỗi Shop có nhiều nhất một thao tác làm mới token đang chạy (single-flight), bất kể hệ thống có bao nhiêu instance.
- Lỗi tạm thời (timeout, 5xx) thì thử lại có backoff. Lỗi vĩnh viễn (refresh token không hợp lệ hoặc đã hết hạn) thì Shop chuyển `Disconnected` với lý do "Ủy quyền hết hạn".
- Sau khi làm mới, các request đang chạy với access token cũ không bị lỗi. Shopee giữ token cũ hiệu lực thêm 5 phút.
- Token được mã hóa khi lưu (N11).

AC: Given 3 instance cùng thấy token của shop Shopee S sắp hết hạn, When cả 3 cùng cố làm mới, Then Simulator ghi nhận đúng 1 lần gọi refresh cho S và S vẫn `Active`.

Case kỹ thuật: Distributed lock hoặc owner theo shop, fencing (C4, C5.3). Có thí nghiệm: tái hiện lỗi mất kết nối trước khi sửa.

#### F2.2b Cảnh báo sắp hết hạn ủy quyền

- Mỗi Shop hiển thị ngày hết hạn ủy quyền và có nút "Ủy quyền lại", dẫn vào luồng F2.1a cho đúng Shop đó.
- **BR-11:** Shop được gắn cờ "Sắp hết hạn ủy quyền" khi còn dưới 7 ngày, hoặc khi nhận thông báo từ sàn (TikTok `UPCOMING_AUTHORIZATION_EXPIRATION`, Shopee push code 12), tùy cái nào đến trước. Cờ tự gỡ khi ủy quyền lại thành công.

#### F2.3a Ngắt kết nối

- **BR-12:** Shop chuyển `Disconnected` khi có một trong các lý do: người dùng ngắt, nhà bán thu hồi quyền trên sàn (TikTok `SELLER_DEAUTHORIZATION`, Shopee push code 2), ủy quyền hết hạn, Workspace bị xóa. Lý do được lưu lại và hiển thị.
- Khi Shop `Disconnected`:
  - Mọi lời gọi API sàn cho Shop đó dừng. Lệnh đang chờ trong hàng đợi bị hủy, và người dùng thấy lệnh nào chưa gửi được.
  - Order và Listing giữ nguyên ở chế độ chỉ đọc.
  - Reservation của các Order đang mở được giữ nguyên, vì đơn vẫn tồn tại trên sàn.
  - Thông báo gửi đi theo F10.1a.

AC: Given Shop có 200 lệnh đẩy tồn trong hàng đợi, When nhận webhook thu hồi quyền, Then sau thời điểm đó Simulator không nhận thêm request nào cho Shop này.

#### F2.4a Kéo dữ liệu ban đầu và kéo bù (backfill)

- Lần đầu kết nối: kéo toàn bộ Listing; kéo mọi Order cập nhật trong 30 ngày gần nhất; kéo mọi Order chưa ở trạng thái `Completed` hoặc `Cancelled`, bất kể thời điểm.
- Kết nối lại: kéo bù từ mốc đồng bộ cuối, lùi lại thêm một khoảng chồng lấn.
- Order kéo về theo đường này áp dụng đúng quy tắc như đơn nhận qua webhook, bao gồm giữ tồn (BR-18).
- Kéo dữ liệu là một job có tiến độ hiển thị cho người dùng. Job chạy tiếp được sau khi service khởi động lại, không làm lại từ đầu.
- Job có độ ưu tiên thấp hơn đồng bộ real-time và xử lý đơn, nên không làm chậm các Shop khác (N7).

AC: Given Shop có 20.000 đơn trong 30 ngày, When pod chạy job bị kill khi đã xong 60%, Then job chạy tiếp từ khoảng 60%, kết quả cuối không thiếu và không trùng đơn nào.

Case kỹ thuật: Job dài có checkpoint, chia cửa sổ thời gian theo giới hạn 15 ngày của Shopee, hàng đợi ưu tiên, fairness (C5.2, C5.4, C5.5).

---

### F3. Sản phẩm và Listing

#### F3.1a Master SKU

- Thuộc tính:
  - Mã SKU: bắt buộc, duy nhất trong Workspace theo BR-13.
  - Tên: bắt buộc.
  - Giá vốn (VND), mã vạch, ảnh: tùy chọn.
  - Trạng thái: `Active` hoặc `Archived`.
- **BR-13:** Mã SKU so sánh không phân biệt hoa thường và bỏ khoảng trắng hai đầu.
- P0 không có khái niệm "sản phẩm có nhiều biến thể": mỗi biến thể là một Master SKU riêng. Đây là cách đơn giản hóa có chủ đích.
- Chỉ lưu trữ (archive) được Master SKU khi nó không còn Mapping nào và không còn Reservation nào đang mở.
- Hai người cùng sửa một Master SKU: người lưu sau được báo dữ liệu đã thay đổi và phải tải lại. Không ghi đè im lặng.

Case kỹ thuật: Optimistic locking (C4). Tìm kiếm trên 100.000 SKU (C7).

#### F3.2a Kéo Listing từ sàn

- Listing được kéo về khi kết nối Shop (F2.4a), khi nhận webhook thay đổi sản phẩm, và định kỳ mỗi ngày một lần.
- Thông tin lưu: Shop, mã sản phẩm và mã biến thể trên sàn, `seller_sku`, tên, ảnh, giá, trạng thái trên sàn, số tồn trên sàn lần cuối đọc được.
- Listing bị xóa trên sàn thì chuyển trạng thái "Đã gỡ khỏi sàn". Mapping vẫn giữ để tra cứu, nhưng hệ thống không đẩy tồn cho Listing đó nữa.

#### F3.3a Ghép tự động theo seller_sku

- **BR-14:** Listing chưa ghép được tự ghép với Master SKU khi `seller_sku` của Listing trùng **đúng một** mã Master SKU (so sánh theo BR-13). Trùng nhiều hoặc không trùng cái nào thì để chưa ghép. Ghép tự động chạy khi Listing mới về và khi Master SKU mới được tạo.
- **BR-15:** Một Listing ghép với đúng một Master SKU. Một Master SKU có thể được ghép với nhiều Listing, ở nhiều Shop.

#### F3.3b Ghép và bỏ ghép thủ công

- Có danh sách Listing chưa ghép, lọc được theo Shop. Menu có số đếm Listing chưa ghép.
- **BR-16:** Khi ghép một Listing:
  - Mọi Unmapped line của Order đang mở thuộc Listing đó trở thành dòng đã ghép và được giữ tồn ngay.
  - Nếu Master SKU đã khai báo tồn, hệ thống đẩy tồn cho Listing.

  Khi bỏ ghép:
  - Reservation của các dòng đang mở thuộc Listing đó được nhả, và các dòng trở lại thành Unmapped line.
  - Hệ thống ngừng đẩy tồn cho Listing.

AC: Given 3 Order đang mở có Unmapped line của Listing L, mỗi dòng số lượng 1, When ghép L với SKU-A đang có Available 10, Then Available của SKU-A còn 7, và 3 Order không còn cờ Unmapped line.

Case kỹ thuật: Thay đổi ở một bounded context (catalog) kích hoạt bù trừ ở context khác (inventory, order) qua event, có idempotency (C3).

#### F3.3c Tạo Master SKU hàng loạt từ Listing (onboarding)

- Người dùng chọn các Listing chưa ghép rồi bấm "Tạo Master SKU". Hệ thống gom các Listing có cùng `seller_sku` (so sánh theo BR-13) thành một Master SKU có mã là `seller_sku` đó, rồi tự ghép. Listing không có `seller_sku` thì bị bỏ qua và liệt kê lại cho người dùng.
- Người dùng có thể chọn thêm "Lấy tồn hiện tại trên sàn làm tồn ban đầu". Nếu các Listing cùng Master SKU đang có số tồn khác nhau thì lấy **số nhỏ nhất**. Thao tác này được tính là khai báo tồn (BR-21).
- Thao tác chạy như một job: có tiến độ, cho phép thành công một phần, và chạy lại riêng phần lỗi được.

AC: Given Listing ở Shopee `seller_sku="AO-01"` có tồn 12, Listing ở TikTok `seller_sku="ao-01 "` có tồn 9, When tạo Master SKU và chọn lấy tồn từ sàn, Then có một Master SKU `AO-01` ghép với cả hai Listing, On hand 9.

---

### F4. Tồn kho

#### F4.1a Tính Available

- **BR-17:** Mọi con số tồn kho tính theo cặp (Master SKU, Warehouse). Ở P0 mỗi Workspace có một Warehouse mặc định, tạo cùng lúc với Workspace.
- Available = On hand − Reservation − safety stock. Ở P0 safety stock bằng 0 (F4.6 là P1).
- Available được phép âm (BR-19).

#### F4.1b Khai báo và điều chỉnh tồn

- Có hai thao tác:
  - "Đặt số tồn": nhập số On hand thực tế.
  - "Điều chỉnh": cộng hoặc trừ một lượng.
  Cả hai đều bắt buộc chọn lý do (kiểm kê, nhập hàng, hư hỏng, khác) và có ghi chú tùy chọn.
- **BR-21:** Master SKU chỉ được coi là **đã khai báo tồn** sau lần "Đặt số tồn" hoặc "Điều chỉnh" đầu tiên, hoặc sau khi lấy tồn từ sàn ở F3.3c. Khai báo bằng 0 cũng tính. Hệ thống không bao giờ đẩy tồn cho Master SKU chưa khai báo.
- "Đặt số tồn" phải gắn với số On hand người dùng nhìn thấy lúc mở màn hình. Nếu trong lúc đó có đơn làm On hand thay đổi, hệ thống báo cho người dùng và không ghi đè im lặng.

AC: Given On hand đang là 10 và người dùng mở form "Đặt số tồn", When trong lúc đó một Package được bàn giao làm On hand còn 9, rồi người dùng lưu số 15, Then hệ thống báo số đã thay đổi và hỏi lại, không lưu thẳng.

Case kỹ thuật: Tranh chấp ghi giữa thao tác người dùng và luồng tự động (C4).

#### F4.1c Đẩy tồn lên sàn

- **BR-22:** Hệ thống đẩy tồn cho một Listing khi thỏa **cả bốn** điều kiện: (1) Listing đã ghép, (2) Master SKU đã khai báo tồn, (3) Shop đang `Active`, (4) Listing chưa bị gỡ khỏi sàn.
- **BR-23:** Published stock = max(Available, 0), như nhau cho mọi Listing ghép với cùng một Master SKU. Quy tắc phân bổ theo kênh để P1 (F4.5).
- **BR-24:** Hệ thống luôn đẩy **số tuyệt đối**, không đẩy số chênh lệch.
  - Nhiều thay đổi liên tiếp của cùng Listing trong một cửa sổ ngắn (tối đa 2 giây) được gộp thành một lần đẩy với giá trị mới nhất.
  - Một giá trị cũ không bao giờ được đẩy sau một giá trị mới hơn.
  - Nếu giá trị bằng số sàn đã xác nhận lần gần nhất thì không đẩy.
- **BR-25:** Thay đổi tồn do một Order sinh ra phải được ghi nhận trước khi đẩy số mới lên chính Shop của Order đó. Đây là hệ quả của BR-24 và [ADR-0002](../adr/0002-reserve-stock-on-first-sight.md).
- Lệnh đẩy tồn có độ ưu tiên thấp hơn lệnh giao hàng và cao hơn job kéo dữ liệu. Lệnh tới Shopee được gom theo lô tối đa 50 model.
- Kích hoạt khi: Available thay đổi; Listing được ghép; Master SKU vừa được khai báo tồn lần đầu; Shop vừa được kết nối lại; đối soát phát hiện lệch (F4.1e).

AC:
- Given SKU-A ghép với 1 Listing Shopee và 1 Listing TikTok, Available 10, When 30 đơn của SKU-A về trong 1 giây từ Shopee, Then Listing TikTok nhận tối đa 2 lần cập nhật và giá trị cuối cùng là 0. Số lần gọi tới sàn được kiểm bằng bộ đếm của Simulator.
- Given Listing L ghép với SKU-B chưa khai báo tồn, When Available của SKU-B đổi vì có đơn, Then Simulator không nhận lệnh cập nhật nào cho L.

Case kỹ thuật: Coalescing, thứ tự theo key, rate limit phân tán, hàng đợi ưu tiên, batching (C3, C4, C5.2). Đo `stock_sync_lag` (N3).

#### F4.1d Lỗi khi đẩy tồn

- Lỗi tạm thời (429, 5xx, timeout): thử lại có backoff và jitter, tôn trọng `Retry-After`. Trong lúc chờ thử lại, nếu có giá trị mới hơn thì giá trị mới thay giá trị cũ (BR-24).
- **BR-26:** Lỗi vĩnh viễn (sàn từ chối vì số mới thấp hơn phần đang khóa cho khuyến mãi, Listing bị khóa, Listing không còn tồn tại):
  - Listing chuyển trạng thái đồng bộ "Lỗi", kèm lý do đã dịch sang tiếng Việt và mã lỗi gốc.
  - Gửi thông báo theo F10.1a.
  - Không thử lại ngay. Lần đẩy kế tiếp chỉ xảy ra khi có kích hoạt mới (F4.1c).
- Mỗi Listing hiển thị trạng thái đồng bộ: "Đã đồng bộ" (kèm thời điểm và giá trị), "Đang chờ", "Lỗi", hoặc "Không đồng bộ" (kèm lý do: chưa ghép, SKU chưa khai báo tồn, Shop ngắt kết nối).

AC: Given Simulator đang khóa 20 đơn vị của Listing L cho flash sale, When hệ thống đẩy 15, Then L chuyển "Lỗi" với lý do "Sàn đang giữ 20 sản phẩm cho khuyến mãi, không thể đặt thấp hơn", và hệ thống không thử lại cho tới khi Available đổi.

Case kỹ thuật: Phân loại lỗi tạm thời và vĩnh viễn, retry và dead letter (C3, C6). Không retry dồn dập gây sàn phạt (N8).

#### F4.1e Đối soát tồn hằng đêm

- Mỗi đêm, với mọi Listing thỏa BR-22, hệ thống đọc số tồn trên sàn và so với Published stock. Chỗ lệch được đẩy lại.
- Lệch do người bán sửa tay trên sàn: ghi vào lịch sử đồng bộ của Listing và gửi **một** thông báo tổng hợp cho mỗi Shop trong mỗi lần đối soát (F10.1a).

#### F4.2a Giữ tồn khi có đơn

- **BR-18:** Hệ thống tạo Reservation cho mọi dòng đã ghép ngay lần đầu thấy Order ở bất kỳ trạng thái chưa hủy nào, kể cả `PendingPayment` và `OnHold` ([ADR-0002](../adr/0002-reserve-stock-on-first-sight.md)). Số lượng giữ bằng số lượng đặt trừ số lượng đã hủy.
- **BR-19:** Reservation luôn được tạo, kể cả khi làm Available âm. Lý do: sàn đã bán thì hệ thống không thể từ chối. Order có ít nhất một dòng làm Available âm tại thời điểm giữ thì được gắn cờ **Short order**. Mỗi lần như vậy được tính vào chỉ số Oversell. Master SKU chưa khai báo tồn (BR-21) thì không gắn cờ và không tính Oversell, vì hệ thống chưa biết số thực có. Khi khai báo lần đầu mà Available âm, mọi Order đang có Reservation mở trên SKU đó được gắn cờ Short order, nhưng **không** tính vào Oversell.
- Cờ Short order tự gỡ khi Available của mọi SKU liên quan không còn âm, ví dụ sau khi khai báo thêm tồn, hoặc khi Order bị hủy. Short order vẫn xử lý giao bình thường được. Hệ thống không bao giờ tự hủy đơn trên sàn.
- **BR-20:** Giữ tồn là idempotent theo dòng đơn: nhận cùng một Order nhiều lần (webhook trùng, kéo bù, đối soát) không bao giờ giữ thêm.

AC:
- Given SKU-A có Available 1, When hai đơn từ hai Shop khác nhau, mỗi đơn mua 1, về gần như cùng lúc, Then Available bằng −1, đúng một đơn có cờ Short order, và Oversell tăng 1.
- Given SKU-C đã ghép nhưng chưa khai báo tồn, và 2 Order mỗi đơn mua 1 đã về, When người dùng đặt số tồn của SKU-C là 1, Then Available bằng −1, cả 2 Order có cờ Short order, và Oversell không tăng.
- Given một Order đã nhận, When Simulator gửi lại đúng webhook đó 5 lần và job đối soát cũng thấy Order này, Then Reservation của Order vẫn chỉ có một.

Case kỹ thuật: Reservation pattern, cập nhật nguyên tử, đơn luồng theo SKU, idempotent consumer (C3, C4). Đây là trọng tâm của N5.

#### F4.2b Nhả tồn

- Dòng bị hủy một phần hoặc Order chuyển `Cancelled` thì nhả phần Reservation tương ứng. Việc nhả tồn cũng idempotent.
- Nếu tin hủy đến trước tin tạo đơn (sai thứ tự), Order được tạo luôn ở trạng thái `Cancelled` và không có Reservation nào.

#### F4.2c Trừ tồn thật

- **BR-27:** Reservation của một Package chuyển thành trừ On hand tại thời điểm **sớm hơn** trong hai sự kiện:
  - người dùng xác nhận "Đã bàn giao" Package;
  - sàn báo Order đã chuyển sang `Shipping`.

  Sự kiện đến sau không trừ thêm lần nữa.
- Order bị hủy sau khi đã trừ tồn thật thì On hand **không** tự cộng lại. Hàng hoàn được xử lý ở F7 (P1). Trước đó, người dùng điều chỉnh tay theo F4.1b.

#### F4.3a Sổ cái tồn kho

- **BR-28:** Mọi thay đổi On hand hoặc Reservation đều là một bút toán chỉ được thêm, không sửa hay xóa. Bút toán gồm: thời điểm, Master SKU, Warehouse, thay đổi On hand, thay đổi Reservation, loại lý do (giữ, nhả, trừ, khai báo, điều chỉnh), tham chiếu (Order, dòng đơn, phiếu điều chỉnh) và người thực hiện (Member hoặc hệ thống). Muốn sửa sai thì thêm bút toán đối ứng.
- **BR-29:** Tại mọi thời điểm, On hand và tổng Reservation đang mở của một (Master SKU, Warehouse) phải bằng tổng các bút toán. Một kiểm tra định kỳ xác minh điều này và cảnh báo khi lệch.
- Người dùng xem được lịch sử bút toán của một SKU, lọc theo thời gian và loại.

Case kỹ thuật: Event sourcing giới hạn ở sổ cái, snapshot, kiểm bất biến (C3, C14 property-based).

---

### F5. Đơn hàng

#### F5.1a Danh sách đơn gộp

- Một danh sách Order của mọi Shop trong phạm vi quyền của Member.
- Lọc theo: trạng thái chuẩn hóa (mục 4.1), Shop, sàn, khoảng thời gian tạo, và các cờ (Short order, có Unmapped line, có yêu cầu hủy).
- Tìm theo mã đơn của sàn.
- Phân trang theo con trỏ. Không có lỗi trùng hay sót đơn khi dữ liệu thay đổi trong lúc người dùng đang lật trang.
- Có số đếm theo trạng thái. Đơn mới tăng số đếm theo thời gian thực, không bắn thông báo riêng cho từng đơn (F10.1a).
- Chi tiết Order hiển thị:
  - các dòng đơn: Listing, Master SKU, số lượng, số lượng đã hủy, giá;
  - các Package;
  - lịch sử trạng thái, gồm trạng thái gốc của sàn và trạng thái chuẩn hóa;
  - thông tin người nhận (đã che theo N11 với người không có quyền xử lý giao hàng).

Case kỹ thuật: Phân trang cursor, CQRS, read model cho danh sách lớn (C2, C7).

#### F5.2a Nhận đơn qua webhook

- **BR-30:** Endpoint nhận webhook chỉ làm ba việc: kiểm chữ ký, ghi bền, trả lời. Nó trả lời trong giới hạn của N1 và không xử lý nghiệp vụ trong request. Sai chữ ký thì trả 401 và không ghi gì. Nếu chưa ghi bền được thì trả lỗi để sàn gửi lại. Tuyệt đối không trả 2xx khi chưa ghi bền.
- **BR-31:** Webhook chỉ được coi là tín hiệu thay đổi. Sau khi nhận, hệ thống gọi API của sàn để lấy chi tiết mới nhất. Chỉ cập nhật Order khi `update_time` lấy được từ API **mới hơn hoặc bằng** giá trị đang lưu.
- Webhook trùng và webhook sai thứ tự không gây ra thay đổi sai (BR-20, BR-31).

AC: Given Simulator gửi lần lượt `ToProcess` → `PendingPayment` của cùng một đơn (đảo thứ tự), When hệ thống xử lý xong cả hai, Then Order ở `ToProcess`.

Case kỹ thuật: Webhook ingress tách riêng, HMAC với so sánh thời gian hằng, dedupe nhiều lớp, xử lý sai thứ tự bằng version (C3, C5.1). Đo N1, N2.

#### F5.2b Kéo bù đơn (đối soát)

- Mỗi 5 phút, với mỗi Shop `Active`, hệ thống kéo các Order có `update_time` từ mốc đồng bộ cuối trừ 10 phút chồng lấn tới hiện tại. Đơn thiếu hoặc lệch được xử lý giống như nhận qua webhook.
- Số đơn mà đối soát phát hiện thiếu được đo bằng một chỉ số. Giá trị khác 0 nghĩa là webhook đã bị mất.

AC: Given Simulator làm mất 100% webhook của Shop S trong 30 phút, When có 500 đơn được tạo trong khoảng đó, Then sau tối đa 15 phút cả 500 đơn có mặt trong hệ thống (N4).

#### F5.2c Chuẩn hóa đơn

- **BR-32:** Order được định danh bằng (Shop, mã đơn của sàn). Trạng thái của sàn được ánh xạ sang trạng thái chuẩn hóa theo bảng ở mục 4.1. Trạng thái chuẩn hóa luôn đi theo trạng thái sàn, kể cả khi đi "lùi".
- **BR-33:** Gặp trạng thái sàn không có trong bảng ánh xạ: giữ nguyên trạng thái chuẩn hóa cũ, lưu trạng thái gốc, phát cảnh báo cho Platform Admin. Việc xử lý Order không bị dừng, các thông tin khác vẫn được cập nhật.
- Dòng đơn của Listing chưa ghép trở thành Unmapped line (F3.3b).

#### F5.3a Chuẩn bị hàng

- **BR-34:** Chỉ Order ở `ToProcess` mới được sắp xếp giao hàng. Ngoài ra Order phải không có Unmapped line và không có yêu cầu hủy đang chờ. Order ở `PendingPayment` hoặc `OnHold` (kể cả trong 1 giờ chờ bắt buộc của TikTok) bị chặn, và giao diện ghi rõ lý do.
- Các bước trong kho được thao tác trên Package: `Chờ nhặt` → `Đã đóng gói` → `Đã bàn giao` (mục 4.2).

#### F5.4a Nhà bán hủy đơn

- Hủy được Order ở `PendingPayment`, `OnHold` hoặc `ToProcess`, nếu sàn cho phép ở trạng thái đó (Simulator làm theo AS-04). Bắt buộc chọn lý do theo danh sách của sàn.
- Lệnh hủy gửi lên sàn là idempotent. Order chỉ chuyển `Cancelled` khi sàn xác nhận, qua kết quả API hoặc qua đồng bộ. Trong lúc chờ, Order hiển thị "Đang chờ sàn hủy".
- Ở P0 chỉ hủy được cả đơn. Mô hình dữ liệu vẫn lưu số lượng đã hủy theo từng dòng, vì sàn có thể hủy một phần.

#### F5.4b Yêu cầu hủy từ người mua

- Yêu cầu hủy (TikTok: cancellation request; Shopee: `IN_CANCEL`) được hiện thành cờ "Có yêu cầu hủy" trên Order, kèm lý do và hạn trả lời nếu sàn có cung cấp.
- Người dùng chấp nhận hoặc từ chối. Kết quả cuối cùng theo trạng thái sàn trả về. Hết hạn mà không trả lời thì xử lý theo AS-05.

Case kỹ thuật (F5.3–F5.4): Lệnh gửi ra ngoài có idempotency key, xác nhận bất đồng bộ, saga xử lý đơn (C4).

---

### F6. Giao hàng qua sàn

#### F6.1a Sắp xếp giao hàng

- Hệ thống lấy các phương thức giao mà sàn cho phép (lấy tận nơi hoặc gửi tại bưu cục, kèm khung giờ hoặc địa điểm). Người dùng chọn một rồi xác nhận. P0 làm từng Order một.
- **BR-35:** Lệnh sắp xếp giao là idempotent. Gọi lại khi đã thành công trên sàn (ví dụ TikTok trả lỗi 11006021 "đã ship") được coi là thành công. Không bao giờ tạo hai lần giao cho cùng một Package.
- Package được tạo theo đơn vị giao hàng của sàn. TikTok: theo package của sàn. Shopee: mỗi Order một Package, trừ khi đơn bị tách.

#### F6.1b Mã vận đơn

- Mã vận đơn có thể có ngay hoặc đến muộn (Shopee push code 4, đồng bộ định kỳ). Trong lúc chưa có, Package hiển thị "Đang chờ mã vận đơn".

#### F6.1c Vận đơn PDF

- Tạo vận đơn là một job bất đồng bộ nhiều bước: yêu cầu tạo → chờ sàn xử lý (qua push hoặc kiểm tra lại có backoff) → tải file → lưu.
- Người dùng thấy tiến độ và thử lại được khi lỗi. File đã tải được lưu lại, lần tải sau không cần gọi sàn.
- Chỉ tạo được vận đơn trong khoảng thời gian sàn cho phép (Shopee: trước khi hãng vận chuyển lấy hàng).

AC: Given Simulator trả kết quả vận đơn sau 20 giây, When người dùng yêu cầu vận đơn, Then giao diện hiển thị "Đang tạo", và trong vòng 5 giây sau khi Simulator sẵn sàng, file tải về được.

#### F6.1d Thay đổi Package do sàn

- Sàn gộp hoặc tách kiện (TikTok `PACKAGE_UPDATE`) thì Package trong hệ thống được cập nhật theo. Nếu Package bị ảnh hưởng đã ở `Đã đóng gói` hoặc `Đã bàn giao`, nó được gắn cờ "Cần kiểm tra" để người dùng xử lý tay.

Case kỹ thuật (F6): Job bất đồng bộ nhiều bước, state machine, polling có backoff, lưu file trên object storage, idempotency với hệ thống ngoài (C4, C5.5, C7).

---

### F10. Thông báo

#### F10.1a Thông báo trong app và email

| Sự kiện | Trong app (real-time) | Email | Người nhận |
|---|---|---|---|
| Shop chuyển `Disconnected` | ✓ | ✓ | Owner, Quản lý |
| Shop được gắn cờ sắp hết hạn ủy quyền | ✓ | ✓ (một lần khi gắn cờ, một lần khi còn 1 ngày) | Owner, Quản lý |
| Listing đồng bộ lỗi (BR-26) | ✓ (gộp theo Shop, tối đa một thông báo mỗi 10 phút mỗi Shop) | | Owner, Quản lý, Vận hành có quyền trên Shop |
| Có Short order | ✓ | | Owner, Quản lý, Vận hành có quyền trên Shop, Kho |
| Order mới có Unmapped line | ✓ (gộp theo Shop, tối đa mỗi 10 phút) | | Owner, Quản lý, Vận hành có quyền trên Shop |
| Đối soát phát hiện tồn bị sửa ngoài hệ thống (F4.1e) | ✓ (một thông báo tổng hợp mỗi Shop mỗi lần đối soát) | | Owner, Quản lý |
| Order mới | Chỉ tăng số đếm, không có thông báo riêng | | |

- Thông báo trong app đến trong 5 giây kể từ sự kiện. Có danh sách thông báo, đánh dấu đã đọc, và số chưa đọc.
- Một sự kiện được xử lý lặp lại không tạo thêm thông báo (idempotent).
- Email gửi qua hàng đợi, có retry. Email lỗi không làm hỏng luồng nghiệp vụ.

Case kỹ thuật: SSE qua gateway, fan-out theo quyền, gộp thông báo theo cửa sổ thời gian, idempotent consumer (C3, C15).

---

### PA. Platform Admin

- **PA-1** Xem danh sách Workspace (tên, Owner, số Shop, số đơn 30 ngày, trạng thái). Khóa và mở khóa Workspace. Workspace bị khóa thì Member không đăng nhập vào được, và mọi đồng bộ của Workspace tạm dừng.
- **PA-2** Xem sức khỏe kết nối của mọi Shop: trạng thái, lần đồng bộ cuối, độ trễ đồng bộ, lỗi gần nhất. Lọc được theo sàn và theo trạng thái.
- **PA-3** Xem hàng đợi lỗi (message không xử lý được sau mọi lần thử): nội dung, lỗi, số lần thử. Cho phép chạy lại hoặc bỏ qua từng message hay theo lô, mỗi thao tác được ghi lại.
- **PA-4** Nâng hạn mức số Workspace cho một Account (BR-03) và hạn mức của một Workspace.
- Platform Admin dùng tài khoản riêng, không tạo được qua trang đăng ký công khai. Platform Admin không xem được thông tin cá nhân người mua.

Case kỹ thuật: Công cụ vận hành DLT, phân tách quyền giữa người dùng và đội vận hành (C3, C9).

---

## 4. Mô hình trạng thái

### 4.1 Trạng thái Order chuẩn hóa

| Chuẩn hóa | Hiển thị | TikTok Shop | Shopee |
|---|---|---|---|
| `PendingPayment` | Chờ thanh toán | `UNPAID` | `UNPAID`, kể cả đơn COD đang chờ duyệt |
| `OnHold` | Sàn đang giữ | `ON_HOLD`; hoặc `AWAITING_SHIPMENT` mà chưa qua 1 giờ chờ bắt buộc | `PENDING` (mọi `pending_terms`) |
| `ToProcess` | Chờ xử lý | `AWAITING_SHIPMENT` (đã qua 1 giờ) | `READY_TO_SHIP` |
| `ReadyToShip` | Chờ lấy hàng | `AWAITING_COLLECTION` | `PROCESSED`, `RETRY_SHIP` |
| `Shipping` | Đang giao | `PARTIALLY_SHIPPING`, `IN_TRANSIT` | `SHIPPED` |
| `Delivered` | Đã giao | `DELIVERED` | `TO_CONFIRM_RECEIVE` |
| `Completed` | Hoàn tất | `COMPLETED` | `COMPLETED` |
| `Cancelled` | Đã hủy | `CANCELLED` | `CANCELLED` |

Các quy trình con và cờ chạy song song với trạng thái chính, **không** phải trạng thái:

| Cờ / quy trình con | Nguồn |
|---|---|
| Có yêu cầu hủy | TikTok `CANCELLATION_REQUEST_PENDING`; Shopee `IN_CANCEL` |
| Đang chờ sàn hủy | Nhà bán đã gửi lệnh hủy (F5.4a) |
| Short order | BR-19 |
| Có Unmapped line | F3.3b |
| Hoàn trả (P1) | TikTok return/refund; Shopee `TO_RETURN` và return status |

Ghi chú:
- Trạng thái chuẩn hóa luôn đi theo sàn (BR-32). Hệ thống không chặn chuyển trạng thái "lạ", chỉ ghi lại.
- Shopee `IN_CANCEL` giữ trạng thái chuẩn hóa trước đó và bật cờ "Có yêu cầu hủy".
- TikTok `AWAITING_SHIPMENT` chưa qua 1 giờ: tính theo `paid_time` cộng 1 giờ (AS-02).

### 4.2 Trạng thái Package (công việc trong kho)

```
Chờ nhặt ──▶ Đã đóng gói ──▶ Đã bàn giao
    │              │
    └──────────────┴──▶ Đã hủy   (Order bị hủy trước khi bàn giao)
```

Thông tin phía sàn là **thuộc tính** của Package, không phải trạng thái: phương thức giao, mã vận đơn, trạng thái job vận đơn, cờ "Cần kiểm tra".

### 4.3 Trạng thái kết nối Shop

```
          kết nối (F2.1a)
 (mới) ───────────────▶ Active ◀──────────────┐
                          │  cờ: Sắp hết hạn   │ ủy quyền lại
                          ▼                    │ (BR-09)
                    Disconnected ──────────────┘
          lý do: người dùng ngắt | sàn thu hồi | hết hạn | Workspace bị xóa
```

`Paused` (F2.6) để P1.

### 4.4 Trạng thái đồng bộ của Listing

`Không đồng bộ` (kèm lý do) · `Đang chờ` · `Đã đồng bộ` (giá trị và thời điểm) · `Lỗi` (lý do). Chuyển giữa các trạng thái theo F4.1c và F4.1d.

---

## 5. Danh mục quy tắc nghiệp vụ

| Mã | Tóm tắt | Ở |
|---|---|---|
| BR-01 | Email duy nhất toàn hệ thống, không phân biệt hoa thường | F1.1a |
| BR-02 | Sai mật khẩu 5 lần trong 15 phút thì khóa 15 phút | F1.1b |
| BR-03 | Tối đa 5 Workspace sở hữu mỗi Account | F1.1c |
| BR-04 | Dữ liệu thuộc đúng một Workspace, cô lập tuyệt đối | F1.1c |
| BR-05 | Xóa Workspace: xóa mềm, ngắt mọi Shop, xóa hẳn sau 30 ngày | F1.1e |
| BR-06 | Không xóa Account khi còn là Owner | F1.1e |
| BR-07 | Thu hồi quyền có hiệu lực trong 5 giây | F1.2c |
| BR-08 | Một Shop chỉ thuộc một Workspace | F2.1a |
| BR-09 | Kết nối lại thì dùng lại dữ liệu và kéo bù | F2.1a |
| BR-10 | Làm mới token single-flight theo Shop | F2.2a |
| BR-11 | Cờ sắp hết hạn: dưới 7 ngày hoặc khi sàn báo | F2.2b |
| BR-12 | Các lý do ngắt kết nối | F2.3a |
| BR-13 | Mã SKU so sánh không phân biệt hoa thường, bỏ khoảng trắng | F3.1a |
| BR-14 | Tự ghép khi `seller_sku` trùng đúng một Master SKU | F3.3a |
| BR-15 | Một Listing ghép với đúng một Master SKU | F3.3a |
| BR-16 | Ghép thì giữ tồn bù; bỏ ghép thì nhả | F3.3b |
| BR-17 | Tồn tính theo (Master SKU, Warehouse); P0 có một Warehouse | F4.1a |
| BR-18 | Giữ tồn ngay khi thấy đơn chưa hủy | F4.2a |
| BR-19 | Luôn giữ tồn, cho phép Available âm, gắn cờ Short order | F4.2a |
| BR-20 | Giữ tồn idempotent theo dòng đơn | F4.2a |
| BR-21 | Chỉ đẩy tồn sau khi Master SKU đã khai báo tồn | F4.1b |
| BR-22 | Bốn điều kiện để đẩy tồn | F4.1c |
| BR-23 | Published stock = max(Available, 0) | F4.1c |
| BR-24 | Đẩy số tuyệt đối, gộp, không đẩy giá trị cũ sau giá trị mới | F4.1c |
| BR-25 | Ghi nhận đơn trước khi đẩy tồn lên Shop của đơn đó | F4.1c |
| BR-26 | Lỗi vĩnh viễn khi đẩy tồn: đánh dấu, thông báo, không thử lại ngay | F4.1d |
| BR-27 | Trừ tồn thật ở sự kiện sớm hơn: bàn giao hoặc `Shipping` | F4.2c |
| BR-28 | Sổ cái chỉ thêm, không sửa | F4.3a |
| BR-29 | Số dư phải bằng tổng bút toán | F4.3a |
| BR-30 | Webhook: kiểm chữ ký, ghi bền, trả lời; không trả 2xx khi chưa ghi bền | F5.2a |
| BR-31 | Webhook là tín hiệu; lấy chi tiết từ API, so `update_time` | F5.2a |
| BR-32 | Order định danh theo (Shop, mã sàn); trạng thái đi theo sàn | F5.2c |
| BR-33 | Trạng thái sàn lạ: giữ trạng thái cũ, cảnh báo, không dừng xử lý | F5.2c |
| BR-34 | Điều kiện được sắp xếp giao hàng | F5.3a |
| BR-35 | Sắp xếp giao idempotent, "đã ship" coi là thành công | F6.1a |

---

## 6. Tính năng P1 và P2 (chỉ liệt kê)

Đặc tả chi tiết khi tới lượt làm. Dòng không có mã là tính năng phát sinh khi phân tích yêu cầu.

| Mã | Tính năng | Ưu tiên |
|---|---|---|
| F1.3 | Audit log thao tác | P1 |
| F1.4 | Gói dịch vụ và hạn mức theo gói | P1 |
| F1.5 | Tính phí theo mức dùng | P2 |
| — | Đăng nhập bằng OTP qua email | P1 |
| — | Đăng nhập bằng Google | P2 |
| — | Vai trò tự định nghĩa | P2 |
| — | Giao diện tiếng Anh, giao diện cho điện thoại | P2 |
| F2.5 | Màn hình sức khỏe kết nối cho người dùng, dịch lỗi sàn | P1 |
| F2.6 | Tạm dừng và bật lại đồng bộ từng Shop (`Paused`) | P1 |
| F3.4 | Combo/bundle, ghép Listing với combo | P1 |
| F3.5 | Đăng sản phẩm từ master lên nhiều Shop | P1 |
| F3.6 | Sửa hàng loạt, import/export Excel | P1 |
| F3.7 | Theo dõi trạng thái duyệt sản phẩm của sàn | P1 |
| F3.8 | Sao chép sản phẩm giữa Shop | P2 |
| F3.9 | Danh sách loại trừ đồng bộ | P2 |
| — | Sản phẩm nhiều biến thể (nhóm các Master SKU) | P1 |
| F4.4 | Nhiều Warehouse, thứ tự ưu tiên kho | P1 |
| F4.5 | Quy tắc phân bổ theo kênh (phần trăm, buffer, ngưỡng về 0) | P1 |
| F4.6 | Safety stock, cảnh báo tồn thấp | P1 |
| F4.7 | Giữ tồn cho campaign; tính phần sàn đang khóa vào phân bổ | P1 |
| F4.8 | Nhập kho, kiểm kê, chuyển kho có chứng từ | P1 |
| F4.9 | Gợi ý nhập hàng, đơn mua hàng | P2 |
| F4.10 | Vị trí kệ, wave picking | P2 |
| F5.5 | Xử lý hàng loạt: xác nhận, in vận đơn, phiếu nhặt | P1 |
| F5.6 | Tạo đơn thủ công, nhận đơn kênh riêng qua API | P1 |
| F5.7 | Tách đơn, gộp kiện do người dùng chủ động | P1 |
| F5.8 | Quy tắc tự động xử lý đơn | P2 |
| F5.9 | Chế độ chịu tải livestream/flash sale | P2 |
| F6.2 | Đơn tự vận chuyển, hãng vận chuyển riêng, `carrier-sim` | P1 |
| F6.3 | Theo dõi hành trình, cảnh báo giao chậm | P1 |
| F6.4 | Đối soát COD | P2 |
| F7.1–F7.2 | Hoàn trả: đồng bộ, duyệt, nhận hàng hoàn, nhập lại kho | P1 |
| F7.3 | Báo cáo tỷ lệ hoàn | P2 |
| F8.1–F8.2 | Giá theo kênh, đồng bộ khuyến mãi của sàn | P1 |
| F8.3 | Giá sàn tối thiểu theo lợi nhuận | P2 |
| F9.1, F9.2, F9.4 | Dashboard doanh số, lợi nhuận theo đơn, báo cáo tồn | P1 |
| F9.3, F9.5 | Đối soát quyết toán sàn, hóa đơn điện tử giả lập | P2 |
| F10.1 (mở rộng) | Bản tin hằng ngày, tùy chỉnh thông báo theo người | P1 |
| F10.2–F10.3 | Open API cho Workspace, webhook gửi ra | P2 |

---

## 7. Yêu cầu phi chức năng

### 7.1 Quy mô mục tiêu

Các con số dưới đây là giả định dùng để thiết kế và kiểm thử tải, không phải số đo thực tế.

| Chỉ số | Giá trị |
|---|---|
| Số Workspace | 1.000 |
| Số Shop mỗi Workspace | tối đa 50 (khoảng 5.000 Shop toàn hệ thống) |
| Master SKU của Workspace lớn nhất | 100.000 |
| Lưu lượng đơn trung bình | 20 đơn/s toàn hệ thống (khoảng 1,7 triệu đơn/ngày) |
| Đỉnh flash sale | 500 đơn/s trong 10 phút |
| Mức lệch tải | Một Workspace lớn có thể chiếm tới 30% lưu lượng |

### 7.2 Danh sách yêu cầu

| Mã | Yêu cầu | Mục tiêu | Đo bằng |
|---|---|---|---|
| N1 | Webhook ack | p99 < 300 ms (giới hạn của sàn là 3 s) | Histogram ở điểm nhận webhook |
| N2 | Đơn mới xuất hiện trong hệ thống | p95 < 10 s khi qua webhook; < 5 phút khi webhook mất | Thời điểm sàn tạo đơn → thời điểm Order được ghi nhận |
| N3 | Đồng bộ tồn | p95 < 30 s, từ lúc nhận đơn tới lúc Shop khác nhận số mới | `stock_sync_lag` |
| N4 | Không mất đơn | 100% đơn trên sàn có mặt trong hệ thống sau tối đa 15 phút, kể cả khi mất 100% webhook | Chaos + bộ đếm Simulator |
| N5 | Oversell | Có đếm, và chỉ xảy ra trong cửa sổ trễ của N3 | Bộ đếm Simulator so với chỉ số Short order |
| N6 | Thông lượng | Chịu được tải ở mục 7.1 mà vẫn giữ N1–N3 | k6 + Simulator |
| N7 | Cô lập | Một sàn chậm hoặc sập không làm chậm sàn khác. Workspace chiếm 30% tải không làm p95 của Workspace nhỏ tăng quá 20% | Chaos, chỉ số theo Workspace |
| N8 | Tuân thủ giới hạn sàn | 0 lần bị sàn hạn chế vì retry dồn dập; tỷ lệ 429 < 1% | Bộ đếm Simulator |
| N9 | Sẵn sàng | SLO 99,9% cho API đọc; 99,95% cho điểm nhận webhook | SLO dashboard |
| N10 | Phục hồi | RPO ≤ 1 phút, RTO ≤ 15 phút cho DB chính | Diễn tập khôi phục từ backup |
| N11 | Bảo mật dữ liệu | Token sàn được mã hóa khi lưu. Cô lập Workspace có test tự động (BR-04). Thông tin cá nhân người mua (tên, SĐT, địa chỉ) bị che trong log, trace, thông báo lỗi; chỉ người có quyền xử lý giao hàng mới thấy đầy đủ | Review, test, quét log |
| N12 | Truy vết | Một Order truy được qua mọi thành phần bằng một trace, kể cả qua message bất đồng bộ | Tempo/Grafana |
| N13 | Mở rộng sàn | Thêm sàn mới chỉ cần viết adapter, không sửa phần đơn hàng và tồn kho | Review kiến trúc |
| N14 | Lưu trữ dữ liệu | Dữ liệu của Workspace bị xóa được xóa hẳn sau 30 ngày (BR-05). Log 14 ngày, trace 7 ngày | Job dọn dẹp, kiểm định kỳ |
| N15 | Triển khai không gián đoạn | Deploy phiên bản mới (kể cả migration DB) không làm mất webhook nào và không làm lỗi request nào của người dùng | Chạy tải trong lúc deploy |
| N16 | Tính đúng dưới lỗi hạ tầng | Kill bất kỳ pod nào ở bất kỳ thời điểm nào đều không làm sai sổ cái (BR-29) và không làm mất hay nhân đôi Reservation (BR-20) | Chaos (kill pod giữa luồng) |
| N17 | Hiệu năng giao diện | Danh sách 1 triệu đơn: trang đầu < 1 s (p95). Thông báo real-time đến < 5 s | Đo từ trình duyệt |

---

## 8. Yêu cầu cho Simulator

Simulator là một sản phẩm có yêu cầu riêng. Nếu Simulator không tái hiện đúng hành vi của sàn, các yêu cầu N4, N5, N7, N8 không đo được. Phạm vi P0 gồm `tiktok-sim` và `shopee-sim`, dùng chung lõi và khác nhau ở phương ngữ API.

### 8.1 Tương thích API

- **SIM-01** Simulator dùng đúng đường dẫn, tham số, cách phân trang, cách ký request, mã lỗi, payload webhook và chữ ký webhook như tài liệu chính thức tại 11/2026. Adapter viết cho Simulator phải chạy được với sàn thật chỉ bằng cách đổi base URL và khóa ứng dụng.
- **SIM-02** Chỗ nào tài liệu sàn chưa xác minh được (chương 9), Simulator làm theo giả định AS-xx tương ứng, và giả định đó chỉnh được bằng cấu hình.
- **SIM-03** Một Simulator phục vụ được nhiều app và nhiều shop (ít nhất 5.000 shop), mỗi shop có dữ liệu riêng.

### 8.2 Ủy quyền và ký

- **SIM-04** Có trang ủy quyền giả lập: chọn shop, đồng ý, chuyển về `redirect_uri` kèm mã. Mã dùng một lần. Thời hạn mã: Shopee 10 phút, TikTok 30 phút.
- **SIM-05** Token:
  - Shopee: access token 4 giờ; refresh token 30 ngày và **xoay vòng** (refresh token cũ mất hiệu lực ngay khi được dùng); access token cũ còn hiệu lực 5 phút sau khi refresh.
  - TikTok: access token 7 ngày; trường thời hạn trả về là Unix timestamp; việc xoay vòng refresh token cấu hình được (AS-07).
  - Ủy quyền có hạn tối đa cấu hình được. Mặc định của Shopee là 365 ngày.
- **SIM-06** Kiểm chữ ký request đúng thuật toán từng sàn. Request có `timestamp` lệch quá giới hạn thì bị từ chối (TikTok: cũ hơn 5 phút hoặc sớm hơn 30 giây; Shopee: 5 phút).

### 8.3 Đơn hàng và vòng đời

- **SIM-07** Vòng đời đơn đúng theo [A2](../requirements-and-techniques.md#vòng-đời-đơn-hàng) và mục 4.1:
  - TikTok: ON_HOLD 1 giờ sau thanh toán; có cả hai luồng, có và không có ON_HOLD; chặn mọi thao tác giao hàng trong lúc ON_HOLD (lỗi 21011044); địa chỉ người nhận để trống trong lúc ON_HOLD.
  - Shopee: luồng duyệt COD; `PENDING` chỉ trả về khi request có `request_order_status_pending=true`.
  - Đơn chưa thanh toán tự hủy sau một thời gian cấu hình được (AS-03).
- **SIM-08** API lấy đơn đúng giới hạn:
  - Shopee: khoảng thời gian tối đa 15 ngày; `get_order_detail` tối đa 50 đơn mỗi lần; field `warning` khi quá tải.
  - TikTok: tối đa 100 đơn mỗi trang, cursor `page_token`; `update_time` có thể vượt khoảng tìm kiếm (cấu hình được tỷ lệ).
- **SIM-09** Hủy đơn: nhà bán hủy được kèm lý do; người mua gửi yêu cầu hủy, nhà bán duyệt hoặc từ chối; hết hạn thì xử lý theo AS-05. Hủy một phần theo dòng cấu hình được (AS-04).

### 8.4 Tồn kho

- **SIM-10** Tồn của Listing bị trừ ngay khi đặt hàng, kể cả đơn chưa thanh toán (AS-01), và được trả lại khi đơn bị hủy. Riêng TikTok tuân theo cờ `enable_auto_restock` của từng SKU.
- **SIM-11** Có tồn khóa cho khuyến mãi và campaign. Cập nhật tồn thấp hơn phần đang khóa thì bị từ chối với đúng mã lỗi (TikTok 12052165/12052393; Shopee lỗi cập nhật tồn thấp hơn tồn giữ cho khuyến mãi). Có phát Shopee push code 8 khi đặt hoặc hủy đơn làm thay đổi tồn khuyến mãi.
- **SIM-12** API cập nhật tồn đúng giới hạn: Shopee tối đa 50 model mỗi lần; TikTok nhận số tuyệt đối theo kho.

### 8.5 Giao hàng

- **SIM-13** Có đủ:
  - tham số giao hàng (lấy tận nơi hoặc gửi tại bưu cục);
  - ship (gọi lần hai thì lỗi, TikTok 11006021);
  - mã vận đơn đến trễ (cấu hình được độ trễ, Shopee push code 4);
  - vận đơn bất đồng bộ 4 bước của Shopee;
  - TikTok tự gộp hoặc tách package (`PACKAGE_UPDATE`).

### 8.6 Webhook

- **SIM-14** Gửi webhook đúng ngữ nghĩa từng sàn:
  - timeout 3 giây, coi là lỗi nếu không nhận 2xx;
  - lịch retry: TikTok 2 phút → 30 phút → 3 giờ → 12 giờ; Shopee 300 s → 1800 s → 10800 s;
  - giao ít nhất một lần, không đảm bảo thứ tự;
  - Shopee tắt subscription khi tỷ lệ thành công dưới 30% trên hơn 600 push trong 6 giờ, và push bị lỡ không được gửi lại.
- **SIM-15** Mỗi loại webhook có các nút chỉnh, áp dụng theo shop hoặc toàn cục: tỷ lệ nhân đôi, tỷ lệ đảo thứ tự, tỷ lệ mất, độ trễ.

### 8.7 Giới hạn và lỗi có chủ đích

- **SIM-16** Rate limit theo app × shop × nhóm endpoint, hạn mức thay đổi được trong lúc chạy. Bị chặn thì trả 429 (TikTok thêm mã 36009002), có thể kèm `Retry-After`. App retry dồn dập khi đang bị chặn (vượt ngưỡng cấu hình) thì bị hạn chế, giống Shopee, và cần thao tác trên giao diện quản trị để gỡ.
- **SIM-17** Nút chaos: tỷ lệ lỗi 5xx; độ trễ phản hồi; sập hoàn toàn trong N phút; trả `warning` quá tải; thu hồi ủy quyền của một shop; gửi thông báo sắp hết hạn ủy quyền.

### 8.8 Người mua ảo và người bán trên sàn

- **SIM-18** Bộ sinh đơn theo kịch bản cấu hình được:
  - tốc độ (phân phối Poisson);
  - tập SKU, kể cả SKU nóng;
  - tỷ lệ COD, tỷ lệ bỏ thanh toán, tỷ lệ người mua hủy, tỷ lệ COD bị từ chối.

  Có sẵn các kịch bản: ngày thường (20 đơn/s), flash sale (500 đơn/s trong 10 phút), livestream (dồn vào vài SKU).
- **SIM-19** Hành vi người bán trên sàn: sửa tồn tay, tạo và kết thúc khuyến mãi khóa tồn, gỡ Listing, thêm Listing mới.

### 8.9 Kiểm chứng và điều khiển

- **SIM-20** Bộ đếm kiểm chứng, lấy được qua API và metric:
  - số đơn bán khi tồn thực đã hết (Oversell thực);
  - số đơn trên sàn chưa có trong hệ thống, tính theo thời gian (N4);
  - số request bị 429 và số lần bị hạn chế (N8);
  - thống kê webhook: gửi, thành công, retry, bị mất;
  - lịch sử giá trị tồn của từng Listing kèm thời điểm, để tính `stock_sync_lag`.
- **SIM-21** Giao diện quản trị nhỏ để xem và bật tắt mọi nút ở trên. Có API điều khiển để k6 và test tự động dùng được.
- **SIM-22** Kịch bản có seed ngẫu nhiên. Chạy lại cùng seed và cùng cấu hình thì sinh cùng chuỗi sự kiện, để lỗi tái hiện được.
- **SIM-23** Simulator tự xuất metric và log của chính nó, và không truyền trace context vào webhook, vì sàn thật không làm vậy.

---

## 9. Giả định và câu hỏi mở

Các điểm dưới đây chưa xác minh được từ tài liệu chính thức. Hệ thống và Simulator làm theo giả định, và giả định được chỉnh bằng cấu hình của Simulator (SIM-02). Kiểm lại khi có sandbox thật.

| Mã | Giả định | Cơ sở |
|---|---|---|
| AS-01 | Đơn `UNPAID` trên cả hai sàn đã bị trừ tồn bán được | Suy luận độ tin cậy cao ([tra cứu](../research/2026-11-marketplace-stock-reservation.md)) |
| AS-02 | TikTok `AWAITING_SHIPMENT` chưa giao được trong 1 giờ kể từ `paid_time` | Tài liệu nói phải giữ 1 giờ, nhưng không nói mốc tính |
| AS-03 | Đơn chưa thanh toán tự hủy sau 24 giờ (cả hai sàn) | Không tìm được nguồn chính thức |
| AS-04 | Cả hai sàn cho phép hủy một phần theo dòng khi nhà bán báo hết hàng | Chưa xác minh |
| AS-05 | Yêu cầu hủy của người mua tự được chấp nhận nếu nhà bán không trả lời trong 48 giờ | Chưa xác minh |
| AS-06 | Shopee trả tồn thường khi đơn bị hủy | Chỉ xác minh được với tồn khuyến mãi |
| AS-07 | Refresh token TikTok không xoay vòng, nhưng hệ thống vẫn thiết kế như có xoay vòng (BR-10) | Chưa xác minh |
| AS-08 | Hạn mức mặc định của Simulator: 10 request/s cho mỗi app × shop × nhóm endpoint (Shopee); TikTok theo gợi ý ở A2 | Shopee không công bố QPS |
| AS-09 | Đơn COD của TikTok không đi qua `UNPAID` mà vào thẳng `ON_HOLD` hoặc `AWAITING_SHIPMENT` | Chưa xác minh |

Câu hỏi mở, sẽ quyết định ở phase thiết kế (không ảnh hưởng hành vi người dùng thấy):
- Số partition cho các luồng tồn kho, và cách xử lý SKU nóng (C13).
- Cách hiện thực single-flight khi làm mới token: distributed lock hay owner theo shop (C5.3).
- Workflow engine cho saga xử lý đơn: tự viết hay Temporal (C4).
