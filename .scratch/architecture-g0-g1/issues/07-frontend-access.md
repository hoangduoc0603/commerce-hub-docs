# 07 Frontend truy cập API: trực tiếp hay qua BFF

Type: grilling
Status: open
Blocked by: 05
Map: [Kiến trúc G0–G1](../map.md)

## Question

Next.js gọi gateway trực tiếp từ trình duyệt hay đi qua BFF (route handler của Next.js)? Token OIDC lưu ở đâu (cookie httpOnly phía BFF hay bộ nhớ trình duyệt), refresh thế nào. Ảnh hưởng tới SSE ở G2 và CORS ở gateway.

## Comments
- 2026-11-13: Từ ticket [05 Mô hình danh tính và Workspace trong token](05-identity-model.md#answer): BFF gửi `X-Workspace-Id` theo Workspace người dùng đang chọn (chuyển Workspace không đổi token). BFF phải refresh token ngay khi người dùng quay về từ link xác minh email (claim `email_verified`), và nhận backchannel logout để đặt lại mật khẩu đăng xuất được trình duyệt khác (F1.1b). Đăng ký mở trang Keycloak bằng `prompt=create` ([ADR-0008](../../../adr/0008-keycloak-authn-only-members-replicated-via-kafka.md)).
