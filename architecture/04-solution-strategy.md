# 4. Chiến lược giải pháp

## 4.1 Các quyết định nền

| Quyết định | Tóm tắt | Nguồn |
|---|---|---|
| Phân rã | Microservice theo bounded context của B1 ngay từ G1, mỗi service một repo trong `services/`. Không đi qua modular monolith (mục 4.2) | Ticket [02](../.scratch/architecture-g0-g1/issues/02-deployment-units.md#answer), [ADR-0001](../adr/0001-polyrepo.md) |
| Giao tiếp | Mọi luồng giữa service đi qua Kafka. Chỉ có một lệnh REST nội bộ: catalog gọi inventory khai báo tồn ban đầu (F3.3c). Không có REST đọc đồng bộ giữa service; mỗi service giữ bản sao dữ liệu nó cần | [ADR-0005](../adr/0005-kafka-from-g1-with-deliberate-dual-write.md), ticket [08](../.scratch/architecture-g0-g1/issues/08-g1-communication.md#answer) |
| Phía phát event | order, catalog, inventory, workspace cố ý dual-write sau commit qua một port publish. G2 đổi port sang outbox, không đổi chỗ gọi | [ADR-0005](../adr/0005-kafka-from-g1-with-deliberate-dual-write.md) |
| Dạng event | Mỗi event mang trạng thái đầy đủ của một aggregate kèm version. Consumer bỏ bản cũ. Không có inbox ở G1 | Ticket [09](../.scratch/architecture-g0-g1/issues/09-g1-contracts.md#answer), [11](../.scratch/architecture-g0-g1/issues/11-service-template.md#answer) |
| Ranh giới sàn | Chỉ `channel-connector` biết khái niệm của sàn (ACL). Contract mang `marketplace` dạng chuỗi mở và các mã sàn dạng chuỗi opaque | Ticket [09](../.scratch/architecture-g0-g1/issues/09-g1-contracts.md#answer) |
| ID | Thực thể có gốc ở sàn dùng UUIDv5 tất định do connector tính; thực thể sinh bên trong dùng UUIDv7 | [ADR-0009](../adr/0009-deterministic-ids-for-marketplace-entities.md) |
| Danh tính | Keycloak một realm, chỉ xác thực. Member, Role, Scope ở `workspace`, nhân bản tới từng service qua topic compacted. Workspace đi bằng header `X-Workspace-Id` | [ADR-0008](../adr/0008-keycloak-authn-only-members-replicated-via-kafka.md) |
| Cô lập dữ liệu | Shared schema, code ghi rõ `workspace_id`, RLS `FORCE` là thứ bảo đảm | [ADR-0010](../adr/0010-workspace-isolation-shared-schema-with-mandatory-rls.md) |
| Frontend | Next.js là BFF mỏng, giữ token ở server. Chỉ `seller-web` và Keycloak ra ngoài cụm; gateway là ClusterIP | [ADR-0011](../adr/0011-nextjs-bff-with-server-side-session.md) |
| Dữ liệu | Một cluster PostgreSQL `pg-main` dùng chung, mỗi service một database và bộ role riêng | [ADR-0003](../adr/0003-shared-postgres-cluster.md) |
| Tồn kho | Bảng số dư cộng sổ cái trong cùng transaction, sổ cái thắng khi lệch. Khóa bi quan theo thứ tự cố định | [ADR-0007](../adr/0007-stock-balance-plus-ledger-in-one-transaction.md) |
| Code service | Spring MVC trên virtual thread, hexagonal một module. `JdbcClient` cho service có thao tác khó, JPA cho service CRUD, một hook RLS chung | Ticket [11](../.scratch/architecture-g0-g1/issues/11-service-template.md#answer), [ADR-0012](../adr/0012-two-persistence-stacks-one-rls-hook.md) |
| Triển khai | GitOps bằng Argo CD, một chart `app` cho mọi workload, 1 instance mặc định ở lab | [ADR-0004](../adr/0004-single-instance-by-default-on-homelab.md), ticket [11](../.scratch/architecture-g0-g1/issues/11-service-template.md#answer) |

## 4.2 Vì sao bỏ modular monolith

[C1](../requirements-and-techniques.md#c1-kiến-trúc-và-phân-rã) và [B1](../requirements-and-techniques.md#b1-bounded-context-và-service) từng đề xuất "modular monolith trước, tách sau": giai đoạn đầu gộp `workspace` vào gateway và Keycloak, gộp reporting vào order, chỉ tách khi có số đo chứng minh cần. Ngày 2026-11-12, người dùng chọn **tách service theo B1 ngay từ G1** (ticket [02](../.scratch/architecture-g0-g1/issues/02-deployment-units.md#answer)). Lý do:

1. **Mục tiêu của dự án là luyện microservice ở chất lượng production** ([Charter](../project-charter.md#1-vì-sao-có-dự-án-này)). Modular monolith hoãn đúng những bài toán cần luyện: contract có version giữa các repo, deploy độc lập, đổi xuyên service theo expand/contract, trace xuyên process, nhất quán cuối cùng qua event.
2. **Khớp polyrepo ([ADR-0001](../adr/0001-polyrepo.md)).** Repo là đơn vị phát hành. Modular monolith sẽ buộc nhiều bounded context vào một repo và một nhịp phát hành, trái với cách chia repo đã chốt.
3. **Ranh giới đã có lý do nghiệp vụ, không cần số đo để chọn.** Ranh giới B1 đi theo aggregate và theo yêu cầu vận hành khác nhau: inventory ghi nhiều và cần nhất quán chặt, catalog đọc nhiều; connector chậm và phụ thuộc sàn. Mỗi yêu cầu G1 trong ma trận truy vết đã có một service sở hữu.
4. **`workspace` không gộp được vào gateway hay Keycloak.** Ticket [05](../.scratch/architecture-g0-g1/issues/05-identity-model.md#answer) chốt Keycloak chỉ xác thực, Member nằm ở `workspace` và được nhân bản qua Kafka để thu hồi quyền có hiệu lực trong 5 giây (BR-07). Gateway chỉ kiểm JWT.

Cái giá đã chấp nhận:

- **RAM.** 6 service × 512 Mi JVM, cộng simulator và frontend, là khoảng 4,6 GiB trên cụm 24 GiB. Vừa được nhờ chạy 1 instance ([ADR-0004](../adr/0004-single-instance-by-default-on-homelab.md)). JVM 512 Mi là rủi ro lớn nhất, phải đo ở G0.
- **Nhất quán cuối cùng.** Ví dụ: ngay sau khi tạo Workspace, service khác có thể chưa thấy Member. Màn hình đầu của Workspace mới đọc từ `workspace`, test e2e poll chờ thay vì `sleep` ([ADR-0008](../adr/0008-keycloak-authn-only-members-replicated-via-kafka.md)).
- **Lặp cấu hình ở nhiều repo.** Bù bằng template `services/hello`, chart `app` và reusable workflow. Chưa có thư viện dùng chung: code chung được chép khi sinh service từ template, chấp nhận trôi lệch tới khi có service thứ hai cần đúng cùng một đoạn code ([ADR-0018](../adr/0018-self-contained-services-no-shared-library-yet.md)) ([mục 8.11](08-crosscutting-concepts.md#811-build-artifact-và-triển-khai)).
- **Không còn "tách khi có số đo".** Thay vào đó, mỗi giai đoạn vẫn phải có bản ghi thí nghiệm. Nếu số đo cho thấy một ranh giới sai, gộp lại là một quyết định mới có ADR.

## 4.3 Cách đạt mục tiêu chất lượng

| Mục tiêu ([mục 1.2](01-introduction-and-goals.md#12-mục-tiêu-chất-lượng)) | Cách đạt |
|---|---|
| 1. Cô lập Workspace | RLS `FORCE` trên mọi bảng, không role đăng nhập được nào có `BYPASSRLS`. Workspace đặt bằng `set_config(..., true)` ở đầu mỗi transaction, từ một hook chung cho cả JPA và `JdbcClient`. Không phải Member thì trả 404. Test N11 ba tầng ([8.2](08-crosscutting-concepts.md#82-cô-lập-workspace)) |
| 2. Đúng đắn của tồn kho | Số dư, Reservation và sổ cái trong một transaction. Khóa `FOR UPDATE` theo thứ tự StockItem rồi Order. Event mang trạng thái đích của Order kèm `orderVersion`, nên redelivery bị bỏ qua. Job BR-29 kiểm bất biến trên một snapshot ([8.8](08-crosscutting-concepts.md#88-persistence-và-migration)) |
| 3. Tiến hóa sang G2 | Port publish duy nhất, đổi bean từ `AFTER_COMMIT` sang outbox. Event mang trạng thái đầy đủ kèm version, nên Debezium hay webhook thêm vào không đổi consumer. Schema `BACKWARD_TRANSITIVE` ([8.5](08-crosscutting-concepts.md#85-event-và-kafka)) |
| 4. Mở rộng sàn | ACL trong `channel-connector`; dữ liệu giữa service không có field mang tên sàn (kiểm bằng review kiến trúc theo N13; CI của `contracts` bỏ từ 2026-11-24, [ADR-0019](../adr/0019-no-contracts-repo.md)); simulator chia core và dialect ([8.6](08-crosscutting-concepts.md#86-canonical-model-id-tiền-và-thời-gian)) |
| 5. Truy vết và đo được | OTLP từ mọi service, `traceparent` qua HTTP và header Kafka, sampling 100% ở lab. Business metric tính từ DB, không đếm trong bộ nhớ ([8.10](08-crosscutting-concepts.md#810-observability)) |
