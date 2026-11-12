# commerce-hub: Ma trận truy vết

- Phiên bản: 1.0, ngày 2026-11-12
- Nối mỗi yêu cầu P0 trong [SRS](srs.md) với: thành phần sở hữu (theo [B1](../requirements-and-techniques.md#b1-bounded-context-và-service)), giai đoạn làm (theo [C18](../requirements-and-techniques.md#c18-lộ-trình-gợi-ý)), yêu cầu phi chức năng và Simulator liên quan, và kỹ thuật trọng tâm.
- Cột **Thiết kế**, **Test** và **Trạng thái** được điền khi làm từng increment. Cập nhật bảng này là một phần của Definition of Done ([Charter](../project-charter.md#5-mô-hình-phát-triển-sdlc)).

Thành phần sở hữu là đề xuất ban đầu và sẽ được chốt ở phase thiết kế. Theo B1, giai đoạn đầu có thể gộp một số service, ví dụ `tenant` gộp vào gateway và Keycloak.

## 1. Yêu cầu chức năng

| Yêu cầu | Sở hữu | Giai đoạn | NFR / SIM | Kỹ thuật trọng tâm | Thiết kế | Test | Trạng thái |
|---|---|---|---|---|---|---|---|
| F1.1a Đăng ký, xác minh | tenant, Keycloak | 1 | N11 | OIDC; G1 Keycloak gửi email trực tiếp, hàng đợi email có retry (C3) sang G2 cùng notification | | | Chưa làm |
| F1.1b Đăng nhập, quên mật khẩu | Keycloak | 1 | | OIDC, chống brute force | | | Chưa làm |
| F1.1c Tạo và chuyển Workspace | tenant, gateway | 1 | N11 | Multi-tenancy, RLS | | | Chưa làm |
| F1.1d Mời Member | tenant, notification | 2 | | Token mời, email | | | Chưa làm |
| F1.1e Xóa Workspace, Account | tenant, mọi service | 4 | N14 | Xóa phân tán theo event | | | Chưa làm |
| F1.2a–b Vai trò, phạm vi | tenant, mọi service | 1 | | Phân quyền theo phạm vi; Member nhân bản qua Kafka ([ADR-0008](../adr/0008-keycloak-authn-only-members-replicated-via-kafka.md)). G1 chỉ có Owner qua giao diện, Member khác tạo bằng fixture của test (lời mời ở G2) | | | Chưa làm |
| F1.2c Thu hồi quyền ngay | gateway, notification | 3 | | Thu hồi JWT, đóng SSE | | | Chưa làm |
| F2.1a Kết nối OAuth | channel-connector | 1 | SIM-04 | OAuth code flow, idempotent callback | | | Chưa làm |
| F2.2a Làm mới token | channel-connector | 3 | SIM-05 | Single-flight, distributed lock | | | Chưa làm |
| F2.2b Cảnh báo hết hạn | channel-connector, notification | 3 | SIM-17 | Scheduler | | | Chưa làm |
| F2.3a Ngắt kết nối | channel-connector | 3 | SIM-17 | Hủy lệnh đang xếp hàng | | | Chưa làm |
| F2.4a Kéo dữ liệu, kéo bù | channel-connector | 1 (cơ bản), 3 (đủ) | SIM-08, N7 | Job có checkpoint, hàng đợi ưu tiên, fairness | | | Chưa làm |
| F3.1a Master SKU | catalog | 1 | N17 | Optimistic locking, tìm kiếm | | | Chưa làm |
| F3.2a Kéo Listing | channel-connector, catalog | 1 | SIM-19 | ACL, upsert idempotent | | | Chưa làm |
| F3.3a–b Ghép tự động, thủ công | catalog, inventory, order | 1 | | Event bù trừ giữa context | | | Chưa làm |
| F3.3c Tạo Master SKU hàng loạt | catalog, inventory | 1 | | Job, thành công một phần | | | Chưa làm |
| F4.1a–b Available, khai báo tồn | inventory | 1 | | Atomic update, xung đột ghi | [ADR-0007](../adr/0007-stock-balance-plus-ledger-in-one-transaction.md) | | Chưa làm |
| F4.1c Đẩy tồn | inventory, channel-connector | 2 | N3, N8, SIM-12, SIM-16 | Coalescing, thứ tự theo key, rate limit | | | Chưa làm |
| F4.1d Lỗi đẩy tồn | channel-connector, notification | 2 | N8, SIM-11 | Phân loại lỗi, retry, DLT | | | Chưa làm |
| F4.1e Đối soát tồn | channel-connector | 3 | SIM-19 | Reconciliation | | | Chưa làm |
| F4.2a–b Giữ, nhả tồn | inventory | 1 | N5, N16, SIM-10 | Reservation, idempotent consumer | [ADR-0007](../adr/0007-stock-balance-plus-ledger-in-one-transaction.md) | | Chưa làm |
| F4.2c Trừ tồn thật | inventory, fulfillment, order | 4 | N16 | Idempotent theo sự kiện đến trước | | | Chưa làm |
| F4.3a Sổ cái | inventory | 1 | N16 | Event sourcing giới hạn, kiểm bất biến | [ADR-0007](../adr/0007-stock-balance-plus-ledger-in-one-transaction.md) | | Chưa làm |
| F5.1a Danh sách đơn | order (+ read model) | 1 | N17 | Cursor, CQRS | | | Chưa làm |
| F5.2a Webhook | webhook-ingress, channel-connector | 2 | N1, N2, N15, SIM-14, SIM-15 | HMAC, ghi bền rồi trả lời, dedupe, sai thứ tự | | | Chưa làm |
| F5.2b Kéo bù đơn | channel-connector | 1 (poll), 3 (đối soát) | N4, SIM-08 | Cửa sổ chồng lấn, checkpoint | | | Chưa làm |
| F5.2c Chuẩn hóa đơn | channel-connector, order | 1 | N13 | ACL, canonical model | | | Chưa làm |
| F5.3a Chuẩn bị hàng | order, fulfillment | 4 | SIM-07 | Saga, state machine | | | Chưa làm |
| F5.4a–b Hủy, yêu cầu hủy | order, channel-connector | 4 | SIM-09 | Lệnh idempotent, xác nhận bất đồng bộ | | | Chưa làm |
| F6.1a–d Giao hàng qua sàn | fulfillment, channel-connector | 4 | SIM-13 | Job nhiều bước, object storage, idempotency | | | Chưa làm |
| F10.1a Thông báo | notification | 2 | N17 | SSE, gộp theo cửa sổ, fan-out theo quyền | | | Chưa làm |
| PA-1, PA-2, PA-4 Quản trị Workspace, sức khỏe Shop | tenant, channel-connector | 3 | | Phân tách quyền vận hành | | | Chưa làm |
| PA-3 Hàng đợi lỗi | mọi consumer | 2 | | Công cụ xem và replay DLT | | | Chưa làm |

## 2. Yêu cầu phi chức năng theo giai đoạn

| NFR | Bắt đầu đo ở giai đoạn | Kịch bản |
|---|---|---|
| N1, N2 | 2 | Tải ngày thường, Kafka chậm (Toxiproxy) |
| N3, N5 | 2 | Nhiều đơn cùng SKU trên hai sàn |
| N4 | 3 | Mất 100% webhook trong 30 phút |
| N7, N8 | 3 | Sàn giảm hạn mức, một sàn sập, Workspace lớn chiếm 30% tải |
| N6 | 5 | Flash sale 500 đơn/s |
| N12 | 0 (khung), 2 (xuyên Kafka) | Một đơn đi qua mọi thành phần |
| N16 | 4 | Kill pod giữa saga, giữa lúc giữ tồn |
| N9, N10, N15 | 7 | SLO, diễn tập khôi phục, deploy dưới tải |
| N11, N14 | 1 (cô lập, mã hóa), 4 (xóa dữ liệu) | Test cô lập tự động, kiểm job dọn dẹp |
| N13 | Mỗi lần review thiết kế | Thêm sàn thứ ba ở mức giấy |
| N17 | 5 | Dữ liệu 1 triệu đơn |

## 3. Simulator theo giai đoạn

| Giai đoạn | SIM |
|---|---|
| 1 | SIM-01 tới SIM-08 cho `shopee-sim` (OAuth, ký, đơn, API lấy đơn) |
| 2 | `tiktok-sim`; SIM-10 tới SIM-12 (tồn), SIM-14, SIM-15 (webhook), SIM-18 (người mua ảo), SIM-20 (bộ đếm), SIM-21 |
| 3 | SIM-16, SIM-17 (giới hạn, chaos), SIM-19 (hành vi người bán), SIM-22 |
| 4 | SIM-09 (hủy), SIM-13 (giao hàng) |

## 4. Khác biệt so với lộ trình C18

- `carrier-sim` và đơn tự vận chuyển chuyển sang P1 (F6.2), nên giai đoạn 4 chỉ làm giao hàng qua sàn.
- Giai đoạn 1 đã có giữ tồn (F4.2a) và sổ cái (F4.3a). Lý do: chúng là nền cho mọi luồng sau, và cần có sớm để đo Oversell.
