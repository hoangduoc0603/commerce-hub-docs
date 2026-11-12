# Map: Kiến trúc Giai đoạn 0–1

Type: wayfinder:map
Ngày mở: 2026-11-12

## Destination

Đủ quyết định để `/to-spec` viết được spec cho **Giai đoạn 0** (nền tảng, service "hello" có trace) và **Giai đoạn 1** (lõi đồng bộ, theo [C18](../../requirements-and-techniques.md#c18-lộ-trình-gợi-ý)) mà không còn câu hỏi mở.

## Notes

- **Ngoại lệ "plan, don't do":** ticket được viết ADR (`docs/adr/`) và viết/cập nhật mục tương ứng trong `docs/architecture/` (arc42 + C4), vì đó là nơi lưu quyết định của Phase 3. **Không** viết file contract thật (`.avsc`, OpenAPI), chart hay code trong map: chúng đi qua `/to-spec` → `/to-tickets` → `/implement`.
- **Skill mỗi session dùng:** ticket `grilling` gọi `grilling` + `domain-modeling`. Ticket `research` gọi `research`, ghi kết quả ở `docs/research/YYYY-MM-<chủ-đề>.md` hoặc `docs/standards/` (theo CLAUDE.md, không dùng nhánh `research/*`).
- **Đọc trước:** [`GLOSSARY.md`](../../GLOSSARY.md), [SRS](../../requirements/srs.md) (mã F/BR/N/SIM liên quan), [ADR](../../adr/), [B1](../../requirements-and-techniques.md#b1-bounded-context-và-service), [`docs/standards/`](../../standards/).
- **Đã chốt sẵn từ Phần C, không mở ticket:** hexagonal + ACL ở channel-connector; database per service; REST + OpenAPI contract-first; service discovery bằng DNS của K8s; Kafka + Avro + Schema Registry; multi-tenancy shared schema có cột `tenant_id` (C8); Next.js App Router + TanStack Query; simulator viết bằng Spring Boot. Stack nền theo [Charter](../../project-charter.md): Java 25, Spring Boot 4.1.x, Kafka 4.x, PostgreSQL 17+, Kubernetes 1.37 (kubeadm, home lab).
- Đề xuất trong `docs/standards/` (ví dụ Gradle, CloudNativePG, Sealed Secrets, migration bằng hook `PreSync`) là **đầu vào** cho ticket, chưa phải quyết định cho tới khi ticket liên quan chốt.

## Decisions so far

- [01 Checklist chuẩn production cho hạ tầng G0](issues/01-infra-standards.md): đủ 9 file trong `docs/standards/`; các đề xuất "nên viết ADR" đã chia về ticket 04, 05, 06, 07, 09, 11, 15.
- [02 Đơn vị triển khai ở G0–G1](issues/02-deployment-units.md): tách service theo B1 (microservice thật), mỗi service một repo trong `services/`; G1 có gateway, tenant, channel-connector, catalog, inventory, order, cùng `marketplace-sim` (tên đổi ở ticket 12) và frontend.
- [03 PostgreSQL trên cụm home lab](issues/03-postgres-on-cluster.md): CloudNativePG 1.30.1 + PG 18, một cluster `pg-main` dùng chung (ADR-0003), 2 instance (ở lab còn 1, theo ticket 04), Barman Cloud lên RustFS trên `gw`, PgBouncer `transaction`.
- [04 Ngân sách tài nguyên home lab](issues/04-resource-budget.md): máy giữ 32 GB. Mặc định mỗi service và DB chạy 1 instance, chỉ scale khi làm thí nghiệm. Giữ số lượng thành phần hạ tầng, giảm cỡ (Kafka 1 Gi/broker, JVM 512 Mi). Còn dư khoảng 1 GiB; phải đo ở G0 (ADR-0004).
- [05 Mô hình danh tính và Workspace trong token](issues/05-identity-model.md): một realm, Keycloak chỉ xác thực. Member, Role, Scope ở `tenant`, phát lên topic compacted. Mỗi service tự kiểm bằng bản sao trong bộ nhớ, gateway chỉ kiểm JWT. Workspace đi bằng header `X-Workspace-Id`; không phải Member hoặc ngoài Scope thì trả 404. Email do Keycloak gửi ở G1. SRS 1.2: F1.1a xác minh bằng link, BR-02 theo cách đếm của Keycloak (ADR-0008).
- [08 Giao tiếp giữa service ở G1](issues/08-g1-communication.md): mọi luồng đi qua Kafka. Chỉ có một lệnh REST nội bộ là khai báo tồn ban đầu (F3.3c). order, catalog, inventory cố ý dual-write sau commit qua một port publish, và G2 đổi port này sang outbox. connector không bao giờ cần outbox. order giữ bản sao Mapping, còn inventory sở hữu Short order (ADR-0005).
- [10 Mô hình ghi của inventory ở G1](issues/10-inventory-write-model.md): bảng số dư cộng sổ cái ghi trong cùng một transaction, khi lệch thì sổ cái thắng. Khóa `FOR UPDATE` theo thứ tự (StockItem rồi Order). Event mang trạng thái đích của Order kèm `orderVersion`, nên không cần inbox. SKU chưa khai báo không tính Oversell (sửa BR-19). Oversell được đếm từ sổ cái (ADR-0007).
- [12 Kiến trúc shopee-sim cho SIM-01..08](issues/12-shopee-sim.md): một repo và một pod `marketplace-sim` phục vụ cả hai sàn, chia dialect theo đường dẫn. Core giữ trạng thái, token, nút chỉnh và admin API. Dialect giữ HTTP, chữ ký và máy trạng thái đơn. Lưu ở database `marketplace_sim` trên `pg-main`. Dùng giờ thật, thời hạn chỉnh bằng cấu hình. AS-xx có hai lớp: mặc định ở `gitops`, ghi đè qua admin API. Admin API có OpenAPI trong `contracts`, API Shopee thì không.
- [15 Repo public hay private](issues/15-repo-visibility.md): mọi repo public trên tài khoản cá nhân (Free, MIT), CI dùng GitHub-hosted runner vào lab qua Tailscale, nhánh chỉ chặn force push/xóa (ADR-0006).

## Not yet specified

- Chiến lược test của G1: có contract test (Pact) ngay chưa, e2e chạy ở đâu, Testcontainers dùng chung image nào. Có property-based test cho bất biến sổ cái BR-29 và test race thứ tự khóa (từ ticket 10).
- Polling đơn F5.2b ở G1: job chạy đơn instance hay chia theo shop, checkpoint lưu đâu. Thứ tự đã chốt ở ticket 08: gửi, chờ ack, rồi mới dời checkpoint.
- Quy ước chung cho ID, tiền, thời gian (UUIDv7?, `BigDecimal` + mã tiền tệ?, UTC).
- Pipeline publish contract (Maven/npm artifact từ repo `contracts`): phụ thuộc ticket 09 và 11. Ticket 15 đã chốt mọi repo public. **Chưa xác minh**: GitHub Packages có bắt token khi tải cả package public hay không. Nếu có thì mọi build sẽ cần credential đọc.
- Bộ test tuân thủ của simulator so với connector: dựng từ ví dụ trong tài liệu Shopee, chạy ở CI của repo nào, và có dùng làm contract test cho adapter của connector không (gắn với chiến lược test G1).
- Chi tiết gateway: Spring Cloud Gateway bản WebFlux hay MVC, rate limit theo Workspace ở G1 hay để sau. Ticket 05 đã chốt gateway chỉ kiểm JWT và định tuyến, không kiểm Member.

## Out of scope

- Ba câu hỏi mở ở [SRS chương 9](../../requirements/srs.md#9-giả-định-và-câu-hỏi-mở): số partition và SKU nóng (C13, Giai đoạn 5), single-flight làm mới token (C5.3, Giai đoạn 3), workflow engine cho saga (C4, Giai đoạn 4). Lý do: thuộc giai đoạn sau đích của map; quyết định khi có số đo.
- Thiết kế các service ra đời từ Giai đoạn 2 trở đi (webhook-ingress, notification, fulfillment, reporting), outbox + Debezium, DLT. Lý do: ngoài đích G0–G1.
- Cách G2 đo dual-write: failpoint giữa commit và gửi, bộ đếm Reservation thiếu (từ [08 Giao tiếp giữa service ở G1](issues/08-g1-communication.md)). Lý do: G1 chỉ cần để sẵn port publish; phép đo là việc của G2.
- Simulator ghi chung `pg-main` làm nhiễu phép đo N6 ở 500 đơn/s (từ [12 Kiến trúc shopee-sim cho SIM-01..08](issues/12-shopee-sim.md)). Lý do: chỉ lộ ra ở G5; xem lại khi có số đo.
