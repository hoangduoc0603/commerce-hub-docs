# 05 Mô hình danh tính và Workspace trong token

Type: grilling
Status: resolved
Blocked by: 01, 02
Map: [Kiến trúc G0–G1](../map.md)

## Question

Keycloak, gateway và service `tenant` chia việc thế nào cho F1.1a–c, F1.2a–b?
- Một realm + Organizations hay realm theo Workspace ([keycloak.md](../../../standards/keycloak.md)).
- Workspace hiện hành nằm ở đâu: claim trong token, header do FE gửi rồi gateway kiểm với `tenant`, hay token đổi khi chuyển Workspace (F1.1c).
- Vai trò và phạm vi theo Shop/Warehouse (F1.2a–b) lưu ở Keycloak hay ở `tenant`.
- Email xác minh F1.1a ở G1 do Keycloak gửi hay đợi notification (G2).

## Answer

Chốt ngày 2026-11-13 (người dùng), sau ba vòng grilling (Q1–Q24). Quyết định chính: [ADR-0008](../../../adr/0008-keycloak-authn-only-members-replicated-via-kafka.md). Sự thật về Keycloak 26.8.2 (Admin Guide, release notes, mã nguồn thẻ `26.8.2`, tra 2026-11-12) đã ghi vào [keycloak.md](../../../standards/keycloak.md).

### Chia việc giữa Keycloak, gateway và `tenant`

| Việc | Ở đâu |
|---|---|
| Mật khẩu, xác minh email, phiên, khóa đăng nhập (F1.1a–b, BR-02) | Keycloak, một realm `commerce-hub` |
| Account trong hệ thống (theo `sub`, email chuẩn hóa, thời điểm và phiên bản đồng ý chính sách) | `tenant`, tạo JIT ở lần gọi đầu (`GET /me`). Keycloak không đẩy event ra ngoài nếu không viết SPI |
| Workspace, Member, Role, Scope (F1.1c, F1.2a–b) | `tenant`; phát trạng thái đầy đủ của Member lên topic compacted |
| Workspace đang làm việc | header `X-Workspace-Id` mỗi request; chuyển Workspace không đổi token |
| Kiểm JWT | gateway và mọi service |
| Kiểm Member, Role, Scope | mỗi service, bằng bản sao trong bộ nhớ (`libs/workspace-access`); gateway không kiểm |

### Các quyết định

1. **Một realm, Keycloak chỉ xác thực.** Loại realm theo Workspace và Organizations (ADR-0008).
2. **Không phải Member, hoặc ngoài Scope, thì trả 404**, không trả 403 (BR-04).
3. **Bản sao Member trong bộ nhớ mỗi pod**: tự gán mọi partition, không dùng consumer group, đọc lại từ đầu khi khởi động. Readiness chỉ `UP` khi đã đọc tới end offset; Kafka không tới được thì pod không ready (không fail-open).
4. **Nhất quán cuối cùng ngay sau khi tạo Workspace** được chấp nhận. Thư viện không gọi `tenant` khi không thấy Member. Màn hình đầu của Workspace mới đọc từ `tenant`; test e2e poll chờ Member, không `sleep`.
5. **Thư viện chỉ giữ enum Role, kiểu Scope, `MemberContext`.** Mỗi service tự giữ phần bảng quyền F1.2a về tài nguyên của mình.
6. **Scope (F1.2b)**: truy vấn danh sách lọc theo `shop_id ∈ Scope` (Warehouse với Kho); Member giữ nhiều Role thì được hợp quyền của các Role.
7. **Gọi giữa service (F3.3c)**: token client credentials của client gọi, kèm `X-Workspace-Id`. Bên nhận chấp nhận Workspace từ service account trong danh sách cho phép, không kiểm Member, không chuyển tiếp token người dùng.
8. **Tạo Workspace cần `email_verified`** trong access token. BFF refresh token ngay khi người dùng quay về từ link xác minh.
9. **`tenant` dual-write theo ADR-0005** (service thứ tư), outbox ở G2. Có lệnh quản trị phát lại trạng thái Member của một Workspace; gửi lại là idempotent vì topic compacted mang trạng thái đầy đủ.
10. **Email ở G1 do Keycloak gửi thẳng** qua SMTP tới Mailpit. Case hàng đợi email có retry (C3) của F1.1a sang G2 cùng notification. Đã ghi vào ma trận truy vết.
11. **F1.1a xác minh bằng link 10 phút, gửi lại sau tối thiểu 60 giây** (Keycloak không có OTP email). SRS 1.2 đã sửa, kèm AC và [user-flows](../../../requirements/user-flows.md).
12. **BR-02 giữ ngưỡng 5 lần**, câu chữ viết theo cách Keycloak đếm (liên tiếp, mỗi lần cách ≤ 15 phút, cộng Quick Login Check 1 giây → chờ 1 phút). Rủi ro khóa trộm ghi là lệch chuẩn có chủ đích trong keycloak.md.
13. **Đồng ý chính sách**: execution Terms and Conditions lưu thời điểm; phiên bản suy ra từ bảng phiên bản kèm ngày hiệu lực đặt cạnh theme trong `gitops`.
14. **Đăng ký trên trang Keycloak** (`prompt=create`, theme tiếng Việt); `passwordBlacklist` đóng sẵn vào image.
15. **Đặt lại mật khẩu đăng xuất mọi phiên khác**: theme ép ô `logout-sessions` luôn bật và ẩn; trình duyệt khác bị đăng xuất nhờ backchannel logout tới BFF.
16. **G1 chỉ có Owner qua giao diện.** API đổi Role và Scope của Member đã có làm thật ở G1; Member khác tạo bằng fixture của test. Lời mời (F1.1d) ở G2.
17. **Platform Admin**: G1 chỉ khai báo realm role `platform-admin` (bắt buộc OTP) và client `admin-web` trong YAML realm; chưa dựng ứng dụng admin.
18. **GLOSSARY**: Member giữ một hoặc nhiều Role; thêm Role và Scope; "Membership" vào _Avoid_.

### Để cho ticket khác

- Tên topic, key và schema của event Member: ticket 09.
- Thư viện `libs/workspace-access` (bản sao, readiness, `MemberContext`) trong template service: ticket 11.
- BFF, refresh token sau khi xác minh email, backchannel logout: ticket 07.
- RLS nhận `tenant_id` từ `MemberContext`; Workspace trong consumer Kafka và job nền: ticket 06.
- Ngoài đích của map, ghi để G2–G4 dùng: cố định email khi mời (F1.1d) có hai cách Keycloak hỗ trợ, là tạo trước user rồi gọi Admin API `execute-actions-email` (email chỉ admin sửa được trong User Profile), hoặc bước workflow `invite-user` mới ở 26.8; `login_hint` chỉ điền sẵn, không khóa. Từ chối Account bị khóa trong ≤ 5 phút access token còn sống: G3–G4, cùng cơ chế với Member.

## Comments
