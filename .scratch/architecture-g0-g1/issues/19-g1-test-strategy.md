# 19 Chiến lược test G1 và bộ test tuân thủ của simulator

Type: grilling
Status: resolved
Blocked by: 17
Map: [Kiến trúc G0–G1](../map.md)

## Question

Những gì đã chốt rải rác: Testcontainers chạy cả trên Mac lẫn CI, PgBouncer dùng `ghcr.io/cloudnative-pg/pgbouncer`, luồng đầy đủ chỉ kiểm trên lab ([13](13-dev-loop.md#answer)); test N11 ba tầng ([06](06-workspace-isolation.md#answer)); property-based test cho bất biến sổ cái BR-29 và test race thứ tự khóa ([10](10-inventory-write-model.md#answer)); e2e đi qua BFF với đăng nhập thật, test refresh song song, test backchannel logout cho F1.1b ([07](07-frontend-access.md#answer)). Còn lại:

- Contract test giữa service: có dùng Pact cho REST ở G1 không (chỉ còn một lệnh REST nội bộ F3.3c theo [08](08-g1-communication.md#answer)), event thì kiểm bằng schema compatibility là đủ hay cần thêm.
- e2e chạy ở đâu và khi nào (sau mỗi lần Argo CD sync trên lab?), công cụ gì.
- **Bộ test tuân thủ của simulator so với connector**: dựng từ ví dụ trong tài liệu Shopee, chạy ở CI của repo nào, và có dùng làm contract test cho adapter của connector không.
- Test nào là điều kiện để một increment G1 đạt Definition of Done ([Charter mục 5](../../../project-charter.md#5-mô-hình-phát-triển-sdlc)).

## Comments
- 2026-11-13: Từ ticket [17 channel-connector ở G1](17-connector-g1.md#answer), các test cần đưa vào chiến lược:
  - hai instance cùng gọi `claim_due_syncs` thì không nhận trùng việc;
  - mất lease thì không ghi được checkpoint;
  - kill pod ở 60% kéo bù thì chạy tiếp, không thiếu và không trùng đơn (AC F2.4a);
  - ciphertext chép sang Shop khác thì giải mã thất bại (associated data);
  - xoay khóa hai bước không làm hỏng token đang lưu.

## Answer

Người dùng chốt ngày 2026-11-13, sau hai vòng grilling (Q1–Q10). Không viết ADR: mọi quyết định ở đây là thêm hoặc bớt test, đổi lại không tốn nhiều công. Lệch khỏi C14 và Charter (không dùng Pact) được ghi ở [arc42 mục 8.12](../../../architecture/08-crosscutting-concepts.md#812-vòng-phát-triển-và-test).

**Đã kiểm (2026-11-13):** trình duyệt tích hợp của Claude desktop **đọc được** open.shopee.com, trái với ghi chép ở ticket 17. Ví dụ: trang [API calls](https://open.shopee.com/developer-guide/16) ("Last Updated: 2025-11-21") có base string mẫu cho Shop API, Merchant API và Public API. Ví dụ `sign` trên trang không dùng làm test vector được, vì trang không đưa `partner_key`.

### Contract giữa service (Q1, Q2)

- **Không dùng Pact ở G0–G1.** Ở G1 chỉ có một lệnh REST giữa service (catalog → inventory, F3.3c). Contract là OpenAPI trong `contracts`:
  - CI của `contracts` chặn thay đổi phá vỡ bằng `oasdiff breaking`, đặt cạnh bước kiểm `BACKWARD` của Avro;
  - mỗi service có REST có một test kiểm request và response thật so với spec (ví dụ `swagger-request-validator` gắn vào MockMvc).
- Đây là lệch khỏi C14 và Charter mục 5 có chủ đích. Xem lại Pact khi xuất hiện REST giữa service mà consumer phụ thuộc vào hành vi schema không diễn tả được. Loại Pact Broker vì phải thêm một pod, trong khi lab chỉ còn khoảng 520 MiB.
- **Event**: kiểm tương thích schema, cộng integration test của mỗi producer và consumer dùng **serde Avro thật** với Testcontainers Kafka và Apicurio. Schema nạp từ artifact `contracts` bằng đúng lệnh đăng ký (ticket 13), không dùng mock serializer. Không làm golden example cho từng event, vì event đã mang trạng thái đầy đủ.

### Simulator và adapter của connector (Q3, Q4)

- **Bộ test tuân thủ** nằm trong repo `simulators/marketplace-sim` và chạy trong `./gradlew check` của repo đó. Tên test mang mã SIM (ví dụ `SIM06_rejectsTimestampSkewOver5Min`).
- **Fixture là bản chép nguyên văn ví dụ chính thức** (base string, payload request/response mẫu, mã lỗi), đặt trong `src/test/resources/shopee-docs/`. Mỗi file ghi URL nguồn, ngày tra và dòng "Last Updated" của trang. Chỗ tài liệu không có ví dụ, hoặc chưa xác minh được, thì test gắn mã AS-xx tương ứng. Chữ ký: base string kiểm bằng ví dụ của tài liệu; HMAC kiểm bằng một vector tự tính, có ghi rõ là tự tính.
- **Adapter Shopee của connector không lấy simulator làm contract test.** Connector tự test bằng WireMock, với stub dựng từ **bản chép riêng** của ví dụ chính thức (cùng quy tắc nguồn và ngày như trên), không phụ thuộc repo simulator. Hai bản chép là cố ý, để giữ tính độc lập ticket 12 muốn: simulator hiểu sai thì connector không "đúng theo".
- Connector và simulator chạy thật với nhau chỉ trong e2e trên lab.
- Đã loại: Testcontainers chạy image simulator trong CI của connector (image chỉ có `linux/amd64`, và hai bên sẽ cùng sai); fixture dùng chung trong `contracts` (thêm artifact có version cho dữ liệu tĩnh, đi ngược ticket 12).

### e2e (Q5, Q7, Q8)

- **Repo riêng `e2e`** ở cấp thư mục gốc (giống `load-tests` của C14), viết bằng **Playwright (TypeScript)**:
  - bước qua trình duyệt đi qua BFF, đăng nhập thật bằng Keycloak;
  - bước gọi API dùng client sinh từ OpenAPI admin API của simulator (npm package `contracts`).
  - Đã loại Cypress (luồng OAuth phải mở trang ủy quyền của simulator ở origin khác) và Selenium.
- **Chạy trên GitHub-hosted runner**, vào lab qua Tailscale, nên không tốn RAM của lab.
- **Kích hoạt**:
  - job `update-gitops` gửi `repository_dispatch` sang `e2e`, kèm tên app và SHA;
  - workflow e2e tự chờ bằng `argocd app wait <app> --sync --health --timeout 10m`, dùng tài khoản Argo CD chỉ đọc (project role read-only, token ở secret của repo `e2e`);
  - `concurrency: { group: e2e-lab, cancel-in-progress: false }`;
  - thêm lịch chạy hằng đêm và `workflow_dispatch`.
  - Không bật lại Argo CD Notifications (ticket 04 đã tắt).
- **Khi đỏ**: không tự rollback (canary tự rollback là G7). Workflow đỏ, báo cáo Playwright (trace, video) upload làm artifact. Người sửa thì fix forward hoặc revert commit `gitops`.
- **Dữ liệu**:
  - mỗi lần chạy tự tạo Account mới (`e2e+<run-id>@…`, đăng ký và xác minh qua API của Mailpit, nên kiểm luôn F1.1a), Workspace, Shop mới trên simulator, và Listing, đơn có tiền tố `run-id`;
  - không có tài khoản cố định hay mật khẩu dài hạn trong secret;
  - **dọn ở cuối lần chạy, kể cả khi đỏ**: gọi admin API của simulator "hết hạn ngay" cho token của Shop. Connector chuyển Shop sang `Disconnected` và dừng poll (ticket 17), qua đó kiểm luôn nhánh lỗi của F2.2a;
  - Account và Workspace để tích tụ cho tới khi có F1.1e (G4).
- Chờ nhất quán cuối cùng bằng `expect.poll`, không dùng `sleep` ([arc42 mục 4](../../../architecture/04-solution-strategy.md)).

### Không có tải và chaos ở G1 (Q6)

- Theo ma trận truy vết, N1–N5 đo từ G2, N16 từ G4, N6 từ G5. G1 không dùng k6, Toxiproxy hay Chaos Mesh.
- **AC F2.4a "kill pod ở 60%" kiểm ở tầng integration**: worker kéo bù chạy với WireMock. Khi worker đã ack 60% số đoạn thì dừng đột ngột (đóng context, không dọn dẹp). Đợi lease hết hạn, một worker thứ hai nhận việc. Kiểm tập đơn phát ra Kafka đúng bằng tập đơn trên sàn: không thiếu, và đơn trùng thì cùng `orderVersion`. Kill pod thật trên lab để sang G4 cùng N16.

### Bảng phân tầng (Q9)

Nguyên tắc: mỗi test đặt ở tầng thấp nhất chứng minh được điều nó cần chứng minh. e2e chỉ giữ những thứ bắt buộc phải có cụm thật.

| Test | Tầng | Repo |
|---|---|---|
| Luật ArchUnit | unit | mọi service (từ `service-kit`) |
| N11 tầng 1: catalog RLS, policy, FK ghép, quyền role | integration (Testcontainers PG) | mọi service, test-fixtures của `service-kit` |
| N11 tầng 2: hành vi qua PgBouncer `transaction` | integration | như trên |
| N11 tầng 3: ID của Workspace khác trả 404; event sai Workspace không đổi dữ liệu | integration (MockMvc + Kafka) | từng service |
| N11 qua toàn hệ thống: Account B mở URL Workspace của A thì nhận 404 | e2e | `e2e` |
| Request/response REST khớp OpenAPI | integration | service có REST |
| Serde Avro thật với Apicurio | integration | producer và consumer |
| BR-29: jqwik sinh chuỗi thao tác (khai báo tồn, giữ, nhả, hủy, ghép/bỏ ghép) qua application service trên **PG thật**; bất biến là số dư = tổng sổ cái theo từng StockItem; CI chạy 100 lần thử, có seed | integration | inventory |
| Race thứ tự khóa (StockItem rồi Order): N luồng song song không có deadlock, không lệch sổ | integration | inventory |
| Hai instance cùng gọi `claim_due_syncs` thì không nhận trùng | integration | connector |
| Mất lease thì không ghi được checkpoint | integration | connector |
| Dừng ở 60% kéo bù thì chạy tiếp, không thiếu, không trùng (F2.4a) | integration | connector |
| Ciphertext chép sang Shop khác thì giải mã thất bại (associated data) | unit (Tink, keyset test) | connector |
| Xoay khóa hai bước: token cũ vẫn đọc được, lần ghi mới dùng `key_id` mới | integration | connector |
| Adapter Shopee với WireMock dựng từ ví dụ tài liệu | integration | connector |
| Bộ tuân thủ SIM-01..08; test chặn route trùng giữa hai dialect | unit + integration | `marketplace-sim` |
| Refresh song song: hai request cùng lúc với access token hết hạn thì token endpoint chỉ bị gọi một lần (`FOR UPDATE`) | integration (vitest + testcontainers-node PG, token endpoint giả) | `seller-web` |
| CSRF `Sec-Fetch-Site`; `returnTo` chỉ nhận đường dẫn tương đối | unit | `seller-web` |
| Đăng ký và xác minh (F1.1a); đăng nhập, đăng xuất, backchannel logout (F1.1b) | e2e | `e2e` |
| Hành trình G1: kết nối Shop qua trang ủy quyền của sim (F2.1a) → kéo Listing → ghép → khai báo tồn → sim tạo đơn → đơn hiện trong danh sách, tồn bị giữ, Short order khi thiếu | e2e | `e2e` |

So với ghi chép rải rác trước đó:
- **Refresh song song chuyển từ e2e xuống integration**, vì ở e2e muốn trúng đúng khoảnh khắc token hết hạn thì phụ thuộc may rủi.
- **jqwik chạy trên PG thật**, vì lỗi đáng sợ của BR-29 nằm ở SQL và transaction, không nằm ở công thức.

### Definition of Done về test cho một increment G1 (Q10)

1. Mỗi AC của F/BR trong increment có ít nhất một test tự động, tên chứa mã (ví dụ `F2_4a_resumesAfterCrashWithoutGapOrDuplicate`).
2. `./gradlew check` (hoặc `npm test`) xanh ở mọi repo bị đụng. CI của `contracts` xanh (`BACKWARD` cộng `oasdiff`).
3. Đã deploy lên lab qua GitOps, và lần chạy e2e đầu tiên sau deploy đó xanh.
4. Metric và trace kiểm tay trên Grafana; link dashboard và một trace ID mẫu dán vào cột Test của ma trận truy vết. G1 chưa assert trace tự động, vì N12 xuyên Kafka bắt đầu từ G2.
5. Cột **Test** của ma trận ghi tên test hoặc đường dẫn file; cột **Trạng thái** chuyển sang "Xong".
- Không đặt ngưỡng coverage: coverage đo số dòng chứ không đo AC.

### Chuyển cho spec

- Spec G0: thêm `oasdiff breaking` vào CI của `contracts`; tạo repo `e2e` (Playwright, workflow `repository_dispatch` + hằng đêm + chạy tay, tài khoản Argo CD chỉ đọc); job `update-gitops` gửi `repository_dispatch`.
- Spec G1: dùng trình duyệt tích hợp xác minh lại các điểm ticket 17 còn ghi "chưa xác minh" (`get_order_list`, `get_item_list`) và chép fixture tài liệu cho simulator và connector; admin API của simulator phải có "hết hạn ngay" cho token của Shop (đã có ở ticket 12), dùng cho bước dọn của e2e.
