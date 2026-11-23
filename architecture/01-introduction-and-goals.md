# 1. Giới thiệu và mục tiêu

commerce-hub là SaaS quản lý bán hàng đa sàn cho nhà bán trên TikTok Shop và Shopee, ở chất lượng production. Sàn thật được thay bằng Simulator. Đây là dự án học: nghiệp vụ chỉ vừa đủ để sinh ra các case kỹ thuật mà một hệ thống ecommerce production phải xử lý ([Charter](../project-charter.md#1-vì-sao-có-dự-án-này)).

## 1.1 Tổng quan yêu cầu ở G0–G1

**Giai đoạn 0, Nền tảng.** Chưa có yêu cầu chức năng. Đầu ra là:
- cụm home lab chạy Argo CD, PostgreSQL, Kafka, ~~Schema Registry~~, Keycloak và LGTM (bỏ Schema Registry từ 2026-11-24, [ADR-0019](../adr/0019-no-contracts-repo.md));
- repo `docs`, `platform`, `gitops` (`libs/service-kit` bỏ từ 2026-11-15, [ADR-0018](../adr/0018-self-contained-services-no-shared-library-yet.md); `contracts` bỏ từ 2026-11-24, [ADR-0019](../adr/0019-no-contracts-repo.md));
- service `hello` (cũng là template service) có trace và dashboard (khung của N12).

**Giai đoạn 1, Lõi đồng bộ.** Kết thúc khi đơn tạo trên simulator hiện trên giao diện. Yêu cầu thuộc G1 theo [ma trận truy vết](../requirements/traceability.md):

| Nhóm | Yêu cầu | Service sở hữu |
|---|---|---|
| Account, Workspace, phân quyền | F1.1a–c, F1.2a–b | `workspace`, Keycloak |
| Kết nối Shop | F2.1a (OAuth), F2.4a (kéo dữ liệu ban đầu, mức cơ bản) | `channel-connector` |
| Sản phẩm, Listing | F3.1a, F3.2a, F3.3a–c | `catalog` (+ `channel-connector`, `inventory`, `order`) |
| Tồn kho | F4.1a–b, F4.2a–b, F4.3a | `inventory` |
| Đơn hàng | F5.1a, F5.2b (poll), F5.2c | `order`, `channel-connector` |
| Simulator | SIM-01..08 cho Shopee, admin API tối thiểu | `marketplace-sim` |
| Phi chức năng | N11 (cô lập Workspace, mã hóa token), N12 (khung trace) | mọi service |

Chưa có ở G1: webhook (F5.2a, G2), đẩy tồn lên sàn (F4.1c, G2), TikTok (G2), làm mới token single-flight (F2.2a, G3), xử lý đơn và giao hàng (F5.3a, F6, G4).

## 1.2 Mục tiêu chất lượng

Năm mục tiêu quan trọng nhất ở G0–G1, theo thứ tự ưu tiên. Cách đạt từng mục tiêu nằm ở [mục 4](04-solution-strategy.md).

| # | Mục tiêu | Nghĩa cụ thể ở G0–G1 | Yêu cầu |
|---|---|---|---|
| 1 | **Cô lập Workspace** | Không truy vấn nào đọc hay ghi được dữ liệu của Workspace khác, kể cả khi code quên điều kiện lọc. Có test tự động ở ba tầng | BR-04, N11 |
| 2 | **Đúng đắn của tồn kho** | Sổ cái và số dư không lệch nhau dưới ghi đồng thời và khi event đến lặp. Oversell đếm được, Short order gắn và gỡ đúng | BR-19, BR-20, BR-28, BR-29, N5, N16 |
| 3 | **Tiến hóa sang G2 mà không đổi contract** | G2 thay dual-write bằng outbox, thêm webhook và TikTok mà không sửa consumer hay schema event | ADR-0005, N13 |
| 4 | **Mở rộng sàn** | Thêm sàn mới chỉ cần viết adapter trong `channel-connector` và dialect trong simulator, không sửa `order` hay `inventory` | N13 |
| 5 | **Truy vết và đo được** | Một Order truy được qua mọi service bằng một trace. Mọi giai đoạn có số đo trong `experiments/` | N12, Charter G4–G5 |

Tài nguyên home lab (32 GB RAM) không phải mục tiêu chất lượng mà là ràng buộc cứng ([mục 2](02-constraints.md)). Nhiều lựa chọn ở G0–G1 được quyết vì ràng buộc này.

## 1.3 Bên liên quan

| Vai trò | Ai | Cần gì từ tài liệu này |
|---|---|---|
| Chủ dự án, kiến trúc sư, lập trình viên, vận hành | Chủ repo | Ranh giới service, lý do của từng quyết định, chỗ cố ý lệch chuẩn |
| Trợ lý phân tích, thiết kế, review | Claude | Bối cảnh đủ để viết spec (`/to-spec`), ticket và code đúng quyết định đã chốt |
| Người đọc portfolio, người phỏng vấn | Bên ngoài (repo public, [ADR-0006](../adr/0006-public-repos-on-personal-account.md)) | Câu chuyện kiến trúc và trade-off ([C19](../requirements-and-techniques.md#c19-chủ-đề-phỏng-vấn-gắn-với-dự-án)) |
