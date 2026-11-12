# 07 Frontend truy cập API: trực tiếp hay qua BFF

Type: grilling
Status: resolved
Blocked by: 05
Map: [Kiến trúc G0–G1](../map.md)

## Question

Next.js gọi gateway trực tiếp từ trình duyệt hay đi qua BFF (route handler của Next.js)? Token OIDC lưu ở đâu (cookie httpOnly phía BFF hay bộ nhớ trình duyệt), refresh thế nào. Ảnh hưởng tới SSE ở G2 và CORS ở gateway.

## Answer

Chốt ngày 2026-11-13 (người dùng), sau ba vòng grilling (Q1–Q13). Quyết định khó đảo ngược: [ADR-0011](../../../adr/0011-nextjs-bff-with-server-side-session.md). Sự thật về Next.js 16.4.6, Auth.js, Better Auth, `openid-client` 6.8.9 và Keycloak 26.8.2 (tra 2026-11-13) nằm ở [tra cứu 11/2026](../../../research/2026-11-nextjs-bff-oidc.md).

### Hình dạng

| Đoạn | Quyết định |
|---|---|
| Trình duyệt → `seller-web` | Cùng origin. Cookie `__Host-session` (`HttpOnly; Secure; SameSite=Lax; Path=/`), giá trị là ID phiên ngẫu nhiên 256 bit |
| `seller-web` → Keycloak | Confidential client, Authorization Code + PKCE `S256`, `openid-client` 6 + `jose` |
| `seller-web` → gateway | Route handler `/api/[...path]` chuyển 1:1 sang `/<path>`, gắn Bearer, lọc header |
| Ra ngoài cụm | Chỉ `app.<domain-lab>` (seller-web) và `auth.<domain-lab>` (Keycloak). Webhook-ingress thêm ở G2 |
| Gateway | ClusterIP. NetworkPolicy chỉ nhận traffic từ `seller-web`. Không cấu hình CORS |

### Các quyết định

1. **BFF, không phải SPA public client** (Q1, ADR-0011).
2. **BFF mỏng** (Q2). Không có endpoint gom ở G1. Data fetching chỉ chạy ở client qua TanStack Query, Server Components chỉ dựng khung trang. Màn hình cần hai service (ticket 09) thì trang chính phân trang ở service chính, rồi một query phụ thuộc lấy nhãn theo lô.
3. **Phiên ở Postgres** (Q3). Bảng phiên trong database `seller_web` trên `pg-main`. Access token và refresh token được mã hóa AES-GCM, khóa lấy từ Sealed Secret, mỗi dòng ghi `key_id` để xoay khóa: khóa mới mã hóa, khóa cũ vẫn giải mã cho tới khi phiên cũ hết hạn (≤ 10 giờ). Phiên được đánh index theo `sid` của ID token. Bảng không có `workspace_id` và không bật RLS, vì phiên thuộc Account (ngoại lệ có chủ đích của ADR-0010, ghi trong ADR-0011).
4. **Workspace đang chọn nằm trong URL** `/w/{workspaceId}/…` (UUID, không có slug) (Q4). API client gửi `X-Workspace-Id`. BFF chuyển tiếp nguyên và không kiểm gì, vì service trả 404 khi Account không phải Member. Query key của TanStack Query chứa `workspaceId`. Chuyển Workspace (F1.1c) chỉ là điều hướng.
5. **Expose và CORS** (Q5) như bảng trên. Test API ở tầng dưới dùng token client credentials trong cụm hoặc `kubectl port-forward`. Đã sửa dòng NetworkPolicy ở Phần C.
6. **CSRF** (Q6): mọi `/api/*` phải có `Sec-Fetch-Site: same-origin`, hoặc khi thiếu header đó thì `Origin` phải trùng origin của app; sai thì trả 403. Dùng Lax thay vì Strict để link từ email (xác minh, đặt lại mật khẩu, thông báo G2) không làm mất phiên.
7. **Thư viện và route** (Q7): Next.js 16.4.x, `openid-client` 6 + `jose`, tự viết tầng phiên. Loại Auth.js v5 (chỉ nhận bản vá, vẫn beta) và Better Auth 1.7: cả hai không có backchannel logout phía client và refresh không có khóa. `proxy.ts` (chạy trên Node) chỉ chuyển hướng trang: chưa có phiên thì đưa về `/auth/login?returnTo=…`. Các route: `/auth/login`, `/auth/callback`, `/auth/logout`, `/auth/session`, `/auth/backchannel-logout`, cộng proxy `/api/*`. `returnTo` chỉ nhận đường dẫn tương đối cùng origin (Q13).
8. **Xác minh email không chặn đăng nhập (F1.1a)** (Q8). Keycloak bật Verify email của realm thì chặn đăng nhập, trái SRS, nên:
   - **Tắt** Verify email ở realm.
   - Callback của lần đăng ký đầu (`prompt=create`) mà `email_verified=false` thì BFF chuyển tiếp sang authorize kèm `kc_action=VERIFY_EMAIL`. Keycloak gửi email, người dùng bấm "để sau" được.
   - Banner "Chưa xác minh email" có nút gửi lại, cũng đi qua `kc_action`. Thời gian chờ 60 giây do Keycloak giữ.
   - Cổng chặn thật nằm ở `workspace`: tạo Workspace (và chấp nhận lời mời ở G2) kiểm claim `email_verified`.
   - Bấm link ở cùng trình duyệt thì Keycloak redirect về callback và BFF có token mới. Bấm ở máy khác thì `GET /auth/session` tự refresh khi token hiện tại có `email_verified=false` (mỗi phiên tối đa một lần mỗi 10 giây). Màn hình "Kiểm tra email" gọi endpoint này khi tab được focus lại và poll mỗi 5 giây. Khi refresh, Keycloak tính lại claim từ trạng thái hiện tại của user.
9. **Refresh** (Q9):
   - Refresh chủ động khi access token còn dưới 60 giây lúc chuyển tiếp request.
   - Tuần tự hóa bằng `SELECT … FOR UPDATE` trên dòng phiên, chỉ giữ trong lúc gọi Keycloak (timeout 5 giây). Request chờ khóa đọc lại dòng, không refresh lần nữa.
   - `invalid_grant` thì xóa phiên, trả 401 `session_expired`, và client chuyển cả trang sang `/auth/login?returnTo=…`. Keycloak không tới được thì trả 503 và giữ phiên.
   - Gateway trả 401 thì BFF chuyển nguyên về, không tự retry, chỉ đánh dấu phiên phải refresh ở request kế tiếp. TanStack Query retry query một lần, mutation thì báo lỗi.
   - Phiên BFF hết hạn theo `refresh_expires_in` (idle 30 phút, tối đa 10 giờ), có job dọn phiên hết hạn.
10. **Backchannel logout và đăng xuất** (Q10):
    - Client `seller-web` bật *Backchannel logout session required*, tắt Front channel logout.
    - URL backchannel trỏ vào Service trong cụm (`http://seller-web.<ns>.svc…/auth/backchannel-logout`). NetworkPolicy mở chiều Keycloak → seller-web.
    - Kiểm `logout_token` bằng `jose`: `typ=logout+jwt`, `iss`, `aud`, có claim `events`, không có `nonce`, `iat` không quá 2 phút. Sau đó xóa phiên theo `sid`, không có `sid` thì xóa theo `sub`.
    - Người dùng đăng xuất: revoke refresh token, xóa phiên, redirect tới `end_session_endpoint` kèm `id_token_hint`.
    - Khóa Account dùng `POST /users/{id}/logout` (có gửi backchannel). "Sign out all active sessions" của realm không gửi backchannel; lúc đó BFF chỉ biết khi lần refresh kế tiếp gặp `invalid_grant`.
    - AC của F1.1b đạt: đặt lại mật khẩu → backchannel → request kế tiếp của trình duyệt thứ hai nhận 401.
11. **SSE ở G2, chỉ chốt hướng** (Q11):
    - `EventSource` gọi `/api/…/stream` cùng origin. Route handler trả `new Response(upstream.body)`, truyền `request.signal` xuống `fetch`, đặt `Cache-Control: no-cache, no-transform` và `X-Accel-Buffering: no`.
    - BFF tự đóng stream khi access token hết hạn (≤ 5 phút), và `EventSource` nối lại kèm `Last-Event-ID`. Không cần replica BFF nào giữ danh sách stream đang mở. Gỡ Member vẫn do service đóng trong 5 giây (BR-07).
12. **Proxy** (Q12):
    - Header chuyển tiếp nằm trong một danh sách cho phép duy nhất: `Accept`, `Content-Type`, `If-Match`, `If-None-Match`, `X-Workspace-Id`, `Idempotency-Key`. Cookie không bao giờ xuống gateway.
    - BFF mở server span bằng OTel Node SDK trong `instrumentation.ts` và gửi `traceparent` xuống gateway. `traceparent` từ trình duyệt bị bỏ qua (G1 chưa có RUM).
    - Body lỗi (Problem Details) chuyển nguyên về client.
13. **Migration và kết nối DB** (Q13): SQL nằm trong repo `frontend/seller-web`, chạy bằng Flyway Job ở hook `PreSync` như các service, với role `seller_web_owner`/`_migrator`/`_app`. App kết nối qua PgBouncer `transaction` bằng driver `pg`. Khóa ở mục 9 nằm gọn trong một transaction. Loại Prisma/Drizzle vì sẽ thành mẫu migration thứ hai phải vận hành.

### Tài liệu đã sửa

- [keycloak.md](../../../standards/keycloak.md): Verify email tắt ở realm + `kc_action`; refresh khi quay về; client OIDC dùng `openid-client`; backchannel trong cụm; khóa Account dùng per-user logout; bảng lựa chọn link ADR-0011.
- [Phần C](../../../requirements-and-techniques.md): gateway không còn CORS; dòng BFF; NetworkPolicy; dòng thư viện OIDC và SSE ở frontend.

### Để cho ticket khác

- Ticket 11: chart dùng cho `seller-web` (Node, không phải Spring Boot) cần Job Flyway, Sealed Secret chứa khóa phiên, và NetworkPolicy hai chiều Keycloak ↔ seller-web.
- Ticket 13: dev loop của frontend cần redirect URI `localhost` riêng cho client dev, và backchannel URL không tới được Mac (chấp nhận thiếu, hoặc dùng client dev không có backchannel).
- Ticket 14: C4 Container có `seller-web` là điểm vào duy nhất của trình duyệt, gateway nằm trong cụm, `seller_web` DB trên `pg-main`.
- Chi tiết gateway (fog): gateway không còn CORS, chỉ nhận traffic từ `seller-web`.
- Ngoài đích (G2): thí nghiệm `request.signal` abort ở standalone và rò bộ nhớ của compression khi client ngắt SSE.

## Comments
- 2026-11-13: Từ ticket [05 Mô hình danh tính và Workspace trong token](05-identity-model.md#answer): BFF gửi `X-Workspace-Id` theo Workspace người dùng đang chọn (chuyển Workspace không đổi token). BFF phải refresh token ngay khi người dùng quay về từ link xác minh email (claim `email_verified`), và nhận backchannel logout để đặt lại mật khẩu đăng xuất được trình duyệt khác (F1.1b). Đăng ký mở trang Keycloak bằng `prompt=create` ([ADR-0008](../../../adr/0008-keycloak-authn-only-members-replicated-via-kafka.md)).
- 2026-11-13: Từ ticket [09 Contract và canonical model của G1](09-g1-contracts.md#answer): G1 không có REST đọc giữa service và không có event Master SKU. Màn hình phải gom dữ liệu từ hai service: phân trang ở service chính rồi lấy nhãn theo lô ở service kia (Shop của connector, Master SKU của catalog, StockItem của inventory theo `masterSkuIds`). Lọc Available < 0 thì phân trang ở inventory; tìm theo mã hoặc tên Master SKU thì phân trang ở catalog. Ticket này quyết ai gom (trình duyệt hay BFF). Danh mục API theo service nằm ở Answer của ticket 09.
