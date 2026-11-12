---
status: accepted
date: 2026-11-13
---

# ADR-0011: Next.js làm BFF, phiên lưu ở Postgres, gateway không ra ngoài cụm

Phần server của Next.js (`seller-web`) là **confidential client** OIDC của Keycloak (Authorization Code + PKCE `S256`). Access token và refresh token chỉ nằm ở server, trong bảng phiên của database `seller_web` trên `pg-main`, được mã hóa AES-GCM. Trình duyệt chỉ giữ cookie `__Host-session` (`HttpOnly; Secure; SameSite=Lax`), giá trị là ID phiên ngẫu nhiên. Mọi lời gọi API từ trình duyệt đi tới route `/api/*` cùng origin. BFF gắn `Authorization: Bearer`, lọc header theo một danh sách cho phép, rồi chuyển 1:1 xuống gateway. BFF **mỏng**: không có endpoint gom dữ liệu, không chứa logic nghiệp vụ. Màn hình cần dữ liệu của hai service thì trình duyệt tự gom bằng TanStack Query.

Ra ngoài cụm chỉ có `seller-web` và Keycloak. Gateway là ClusterIP, chỉ nhận traffic từ `seller-web`, và **không cấu hình CORS**.

Có ba lý do. RFC 10017 xếp BFF an toàn nhất cho ứng dụng chứa dữ liệu cá nhân (N11, thông tin người mua). `EventSource` không gửi được header `Authorization`, nên SSE ở Giai đoạn 2 vẫn phải đi bằng cookie. Backchannel logout (F1.1b) và refresh ngay sau khi xác minh email (F1.1a) đều cần một nơi giữ phiên phía server ([ADR-0008](0008-keycloak-authn-only-members-replicated-via-kafka.md)). Bối cảnh ở ticket [07 Frontend truy cập API](../.scratch/architecture-g0-g1/issues/07-frontend-access.md#answer), sự thật về thư viện ở [tra cứu 11/2026](../research/2026-11-nextjs-bff-oidc.md).

## Phương án đã cân nhắc

- **SPA public client giữ token trong trình duyệt, gọi thẳng gateway.** Bị loại vì token lộ trước XSS, gateway phải mở CORS, và SSE không gắn được Bearer.
- **Phiên trong cookie mã hóa (stateless).** Bị loại vì backchannel logout phải tìm phiên theo `sid`, nên đằng nào cũng cần store để giữ danh sách thu hồi. Refresh token dùng một lần cũng không tuần tự hóa được khi không có chỗ khóa chung.
- **Phiên trong bộ nhớ của tiến trình Node.** Bị loại vì mỗi lần rollout làm rơi mọi phiên, và chạy 2 replica (N15) thì hỏng.
- **Redis làm session store.** Bị loại ở Giai đoạn 1 vì Redis chỉ có từ Giai đoạn 3 và chưa có trong ngân sách ([ADR-0004](0004-single-instance-by-default-on-homelab.md)). `pg-main` đã có sẵn.
- **Auth.js v5 hoặc Better Auth.** Bị loại vì cả hai đều không có backchannel logout phía client, và refresh không có khóa, nên request song song làm hỏng refresh token dùng một lần. Auth.js còn chỉ nhận bản vá, v5 chưa bao giờ ra bản stable. Chọn `openid-client` 6 và `jose`, tự viết tầng phiên.
- **BFF gom dữ liệu cho từng màn hình.** Bị loại vì BFF sẽ phụ thuộc contract của mọi service và chứa logic hiển thị. Gọi same-origin thêm một lượt thì tốn không đáng kể.

## Hệ quả

- **Refresh được tuần tự hóa bằng `SELECT … FOR UPDATE`** trên dòng phiên. Request chờ khóa đọc lại dòng và dùng token mới. `invalid_grant` nghĩa là phiên đã chết, kể cả khi realm đặt not-before mà không gửi backchannel: BFF xóa phiên và trả 401.
- **BFF là thành phần có trạng thái.** Nó có migration Flyway riêng theo [db-migration.md](../standards/db-migration.md) và role `seller_web_owner`/`_migrator`/`_app`. Không có `_lookup`, và bảng phiên **không có `workspace_id`, không bật RLS** vì phiên thuộc Account chứ không thuộc Workspace. Đây là ngoại lệ có chủ đích của [ADR-0010](0010-workspace-isolation-shared-schema-with-mandatory-rls.md).
- **Workspace đang chọn nằm trong URL trang** (`/w/{workspaceId}/…`), không nằm trong phiên. Trình duyệt gửi `X-Workspace-Id`, BFF chuyển tiếp nguyên, service kiểm Member. Hai tab mở hai Workspace không ghi đè nhau.
- **CSRF** được chặn bằng `SameSite=Lax` cộng kiểm `Sec-Fetch-Site`/`Origin` ở mọi `/api/*`. Không dùng Strict vì Strict làm mất phiên khi người dùng bấm link từ email.
- **Backchannel logout đi trong cụm**: Keycloak gọi Service `seller-web`, không đi đường public. Client bật *Backchannel logout session required*, tắt front channel logout.
- **SSE ở Giai đoạn 2 đi qua BFF**: BFF tự đóng stream khi access token hết hạn và `EventSource` nối lại. Độ trễ thu hồi phiên của một Account vì thế có giới hạn trên là 5 phút. Gỡ Member vẫn đóng trong 5 giây ở service (BR-07).
- Muốn có API công khai cho bên thứ ba thì phải mở thêm một đường vào gateway (HTTPRoute, CORS hoặc token riêng). Đó là một quyết định mới, không phải bật một cờ.
