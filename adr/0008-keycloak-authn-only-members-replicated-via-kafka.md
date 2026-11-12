---
status: accepted
date: 2026-11-13
---

# ADR-0008: Keycloak chỉ xác thực, Member được nhân bản tới từng service qua Kafka

Keycloak dùng **một realm** `commerce-hub` và chỉ trả lời câu hỏi "Account nào". Token chỉ mang `sub`, email và `email_verified`. Mọi thứ về Workspace (Member, Role, Scope) nằm ở service `tenant`. Workspace đang làm việc không nằm trong token mà đi theo từng request bằng header `X-Workspace-Id`. Vì vậy chuyển Workspace (F1.1c) không phải đổi token.

`tenant` phát trạng thái đầy đủ của từng Member lên một topic Kafka **compacted**. Gỡ Member thì phát tombstone. Mỗi service đọc toàn bộ topic vào bộ nhớ qua thư viện chung `libs/workspace-access`. Thư viện tự gán mọi partition, không dùng consumer group, và đọc lại từ đầu mỗi lần khởi động. Từ `sub` và `X-Workspace-Id`, thư viện dựng ra `MemberContext` (các Role và Scope), và service tự kiểm quyền trên chính tài nguyên của mình. Gateway chỉ kiểm JWT và định tuyến.

Lý do là BR-07: thu hồi quyền phải có hiệu lực trong 5 giây, không chờ token hết hạn. Hướng này còn giữ được quyết định của [08 Giao tiếp giữa service ở G1](../.scratch/architecture-g0-g1/issues/08-g1-communication.md): không có REST đọc đồng bộ giữa service, nên `tenant` không nằm trên đường xử lý của mọi request. Bối cảnh ở ticket [05 Mô hình danh tính và Workspace trong token](../.scratch/architecture-g0-g1/issues/05-identity-model.md).

## Phương án đã cân nhắc

- **Realm cho mỗi Workspace.** Bị loại vì một Account là Member của nhiều Workspace (GLOSSARY) sẽ bị nhân bản danh tính. 1.000 realm còn buộc phải chỉnh cache và làm việc quản trị nặng.
- **Một realm + Organizations (Workspace = Organization).** Organizations đã GA từ 26.0, có claim `organization`. Bị loại vì claim chỉ đúng tại lúc phát token, nên gỡ Member chỉ có hiệu lực sau tối đa 5 phút, trái BR-07. Scope theo Shop/Warehouse (F1.2b) cũng không có chỗ đặt tự nhiên. Có thể xét lại khi làm SSO doanh nghiệp.
- **Workspace hoặc Role làm claim trong token.** Chuyển Workspace phải xin token mới, và thu hồi quyền phải chờ token hết hạn.
- **Gateway hỏi `tenant` đồng bộ, có cache, rồi chuyển Role và Scope xuống service bằng header.** Bị loại vì service phải tin header do gateway thêm. Nếu thay header bằng JWT nội bộ do gateway ký thì gateway lại thành nơi phát token. Ngoài ra `tenant` sập là toàn hệ thống sập.
- **Mỗi service tự gọi REST tới `tenant`.** Trái quyết định 7 của ticket 08, và vẫn đặt `tenant` vào đường nóng.

## Hệ quả

- **Không phải Member thì Workspace coi như không tồn tại.** Header trỏ vào Workspace mà Account không phải Member, hoặc đọc/ghi đối tượng ngoài Scope, đều trả **404**, không trả 403. Cùng luật với AC của F1.1c và BR-04.
- **Nhất quán cuối cùng có chủ đích.** Ngay sau khi tạo Workspace, event chưa kịp tới service nên request vào đó bị 404 trong vài trăm mili giây. Thư viện không gọi `tenant` khi không thấy Member. Màn hình đầu của Workspace mới đọc từ `tenant`, còn test e2e thì poll chờ Member xuất hiện.
- **Readiness chặn tới khi đọc kịp end offset** ghi nhận lúc khởi động. Không làm vậy thì trong lúc rolling update, pod mới trả 404 cho Member thật. Khi Kafka không tới được, pod đứng ở trạng thái chưa ready, không fail-open.
- Mỗi pod giữ một bản đầy đủ. Ở cỡ 1.000 Workspace × 50 Member = 50.000 dòng, bản này chỉ chiếm vài MB trong JVM 512 Mi (ADR-0004). Nếu có thêm thuộc tính lớn hoặc số Member tăng cỡ 10 lần thì phải xét lại.
- Thư viện chỉ giữ enum Role, kiểu Scope và `MemberContext`. **Mỗi service tự giữ phần bảng quyền F1.2a** về tài nguyên của mình, nên sửa quyền ở một service không buộc mọi service lên phiên bản thư viện mới.
- Gọi giữa service (F3.3c) dùng token client credentials kèm `X-Workspace-Id`. Bên nhận chấp nhận Workspace từ một service account trong danh sách cho phép mà không kiểm Member.
- **`tenant` là service thứ tư dual-write theo ADR-0005**, sau order, catalog, inventory. Crash giữa commit và gửi làm mất event, ví dụ Owner của Workspace mới bị 404 mãi. Vì value mang trạng thái đầy đủ nên gửi lại là idempotent. `tenant` có lệnh quản trị phát lại trạng thái của một Workspace. Giai đoạn 2 chuyển sang outbox như các service kia.
- BR-07 (Giai đoạn 3) chỉ còn phụ thuộc độ trễ consumer của từng service, cộng việc đóng SSE. Khóa Account trong khoảng ≤ 5 phút access token còn sống là việc của Giai đoạn 3–4.
