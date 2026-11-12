# 12 Kiến trúc shopee-sim cho SIM-01..08

Type: grilling
Status: resolved
Blocked by:
Map: [Kiến trúc G0–G1](../map.md)

## Question

shopee-sim ở G1 (SIM-01..08: OAuth, ký, đơn, API lấy đơn) được thiết kế thế nào để G2 thêm tiktok-sim không viết lại?
- Lõi dùng chung + "dialect" từng sàn (C17): một repo hai artifact, hay lib trong `libs/`.
- Trạng thái simulator (shop, token, đơn, tồn trên sàn) lưu ở đâu; có cần bền qua restart không.
- Admin API điều khiển kịch bản; cấu hình các giả định AS-xx (SRS chương 9) bằng gì.
- Simulator chạy trong cụm như service thường (Helm, GitOps) hay riêng.

## Answer

Chốt ngày 2026-11-12 (người dùng), sau hai vòng grilling. Mục tiêu là đủ công cụ giả lập để test và tiết kiệm tài nguyên. Không tách thêm khi chưa có lý do đo được.

### Đơn vị triển khai

1. **Một repo `simulators/marketplace-sim`, một deployable phục vụ cả hai sàn cùng lúc**. Điều này khớp ADR-0001, nơi `marketplace-sim` chứa cả TikTok Shop và Shopee. Tên `shopee-sim` ở ticket 02 và ticket 04 đổi thành `marketplace-sim`. G2 thêm TikTok không thêm pod nào, ngân sách vẫn 512 Mi.
2. **Module**: `sim-core` cộng mỗi sàn một dialect (`dialect-shopee` ở G1, `dialect-tiktok` ở G2), tất cả build thành một image.
3. **Định tuyến**: Ingress có hai hostname (`shopee-sim.<lab-domain>`, `tiktok-sim.<lab-domain>`, có TLS) cùng trỏ về một Service. Ứng dụng chia request cho dialect theo đường dẫn (Shopee `/api/v2/...`; TikTok `/authorization/...`, `/order/202309/...`) và không đọc header `Host`. Có một test chặn trường hợp route của hai dialect trùng nhau.
4. **Nút "sàn sập N phút" (SIM-17)** làm trong ứng dụng, áp cho từng dialect (trả 503 hoặc timeout). Không kill pod, vì kill pod thì cả hai sàn cùng sập.
5. **Triển khai** như service thường: chart chung (tên chốt ở ticket 11), Argo CD, namespace riêng `simulators`. Connector dùng hostname Ingress làm base URL, vì trang ủy quyền (SIM-04) phải mở được từ trình duyệt, và Shopee phục vụ trang ủy quyền với API trên cùng host.

### Ranh giới core / dialect

- **Core** giữ phần cả hai sàn giống nhau và không phụ thuộc giao thức:
  - kho trạng thái: App, Shop, ủy quyền, token, Listing, đơn trên sàn;
  - vòng đời token, có tham số cho thời hạn và chính sách xoay vòng (Shopee xoay vòng, TikTok theo AS-07);
  - registry các nút chỉnh và giả định AS-xx;
  - admin API, bộ đếm, seed dữ liệu.
- **Dialect** là adapter HTTP và những luật riêng của từng sàn: đường dẫn, tham số, phân trang, thuật toán ký (SIM-06), mã lỗi, tên trạng thái, **máy trạng thái đơn** (Shopee duyệt COD, TikTok ON_HOLD).
- Quy tắc: ở G1 chỉ đưa vào core những gì tài liệu cả hai sàn ghi giống nhau. Sang G2 có TikTok làm phép so sánh thứ hai mới tách thêm.

### Phạm vi G1

SIM-01..08 cho dialect Shopee, thêm hai phần:
- **API đọc Listing của Shopee** (`get_item_list`, `get_model_list`), để F3.2a chạy được. Chưa trừ tồn: SIM-10..12 để G2.
- **Admin API tối thiểu**: tạo App, tạo Shop, seed Listing, tạo đơn cho một Shop, và chuyển trạng thái đơn bằng tay (thanh toán, hủy, duyệt COD). Phần này thay bộ sinh đơn (SIM-18) cho tới G2. Giao diện quản trị (SIM-21) để G2.

### Trạng thái, thời gian, cấu hình

- **Lưu bền**: database `marketplace_sim` trên `pg-main` (ADR-0003), migration bằng Flyway như service thường, để token và đơn còn nguyên qua rollout hay OOM. Sàn thật không mất dữ liệu.
- **Giờ thật, không có đồng hồ ảo**: mọi thời hạn chỉnh được bằng cấu hình (mã ủy quyền, access token, refresh token, ON_HOLD, AS-03…). Admin API có hành động "hết hạn ngay" cho token, mã ủy quyền và đơn chưa thanh toán của một Shop. Lý do loại đồng hồ ảo: request ký bằng giờ thật sẽ bị từ chối khi lệch quá 5 phút (SIM-06).
- **Admin API chạy trên port riêng**, tách khỏi API giả lập sàn, để không bao giờ đụng `/api/v2/...` và có thể chặn bằng NetworkPolicy.
- **Cấu hình AS-xx (SIM-02) có hai lớp**:
  1. mặc định lúc khởi động bằng `@ConfigurationProperties`, đặt tên theo mã (ví dụ `assumptions.as-03.unpaid-auto-cancel=24h`), giá trị nằm trong values ở `gitops`;
  2. ghi đè lúc chạy qua admin API, theo phạm vi toàn cục hoặc từng Shop, lưu trong DB.
- **Khóa của App**: App nạp từ cấu hình lúc khởi động, đọc từ Secret dùng Sealed Secrets. Secret của connector giữ cùng `partner_id`/`partner_key`. Test cần thêm App (SIM-03) thì tạo qua admin API. Shop và Listing luôn seed qua admin API.

### Contract

- **Không viết OpenAPI cho API của Shopee.** Nếu connector và simulator sinh code từ cùng một bản OpenAPI tự viết, chúng sẽ cùng sai khi mình hiểu sai tài liệu, và SIM-01 không còn kiểm được. Mỗi bên tự cài đặt từ tài liệu chính thức, có ghi chép tra cứu kèm ngày. Simulator có bộ test tuân thủ dựng từ ví dụ trong tài liệu Shopee (ví dụ ký request, payload mẫu, mã lỗi).
- **OpenAPI của admin API** đặt trong `contracts`, vì k6 và test e2e dùng nó (SIM-21). Thêm vào danh sách contract của ticket 09.

### Không viết ADR

ADR-0001 đã chốt `marketplace-sim` là một repo. Gộp hai sàn vào một deployable thì đảo ngược được rẻ, vì image đã là một và tách ra chỉ cần thêm Deployment. Vì vậy không đủ điều kiện "khó đảo ngược".

### Để lại

- Simulator ghi chung `pg-main` với hệ thống đang được đo, nên ở G5 (500 đơn/s) có thể làm nhiễu N6. Đã ghi vào mục Out of scope của map (thuộc G5), xem lại khi có số đo.
- Seed tất định (SIM-22), webhook (SIM-14, SIM-15) và việc không truyền trace context (SIM-23) thuộc G2–G3.
