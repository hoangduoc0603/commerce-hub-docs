# 9. Quyết định kiến trúc

## 9.1 ADR

Mỗi ADR ghi một quyết định khó đảo ngược, có trade-off thật. Toàn văn ở [`adr/`](../adr/).

| ADR | Quyết định | Mục tiêu chất lượng chính |
|---|---|---|
| [0001](../adr/0001-polyrepo.md) | Polyrepo, mỗi repo là một đơn vị phát hành; repo chỉ nối nhau qua contract, artifact có version và runtime | Ranh giới service được ép bằng cấu trúc |
| [0002](../adr/0002-reserve-stock-on-first-sight.md) | Giữ tồn ngay khi thấy đơn, kể cả đơn chưa thanh toán; chỉ nhả khi sàn báo hủy | Đúng đắn của tồn kho (N5) |
| [0003](../adr/0003-shared-postgres-cluster.md) | Một cluster PostgreSQL `pg-main` dùng chung, mỗi service một database và bộ role riêng | Vừa tài nguyên |
| [0004](../adr/0004-single-instance-by-default-on-homelab.md) | Lab chạy 1 instance mặc định, giữ số lượng thành phần hạ tầng, giảm cỡ; scale khi làm thí nghiệm | Vừa tài nguyên |
| [0005](../adr/0005-kafka-from-g1-with-deliberate-dual-write.md) | Kafka giữa service ngay từ G1, cố ý dual-write sau commit qua một port publish cho tới G2; không có inbox ở G1 (sửa đổi 2026-11-13) | Tiến hóa sang G2 |
| [0006](../adr/0006-public-repos-on-personal-account.md) | Mọi repo public trên tài khoản cá nhân, CI trên GitHub-hosted runner vào lab qua Tailscale | Chi phí, bảo mật chuỗi cung ứng |
| [0007](../adr/0007-stock-balance-plus-ledger-in-one-transaction.md) | Bảng số dư cộng sổ cái trong cùng transaction, sổ cái thắng; khóa bi quan theo thứ tự cố định | Đúng đắn của tồn kho |
| [0008](../adr/0008-keycloak-authn-only-members-replicated-via-kafka.md) | Keycloak một realm, chỉ xác thực; Member nhân bản tới từng service qua topic compacted; Workspace đi bằng header | Cô lập Workspace, thu hồi quyền trong 5 giây |
| [0009](../adr/0009-deterministic-ids-for-marketplace-entities.md) | UUIDv5 tất định cho thực thể có gốc ở sàn, UUIDv7 cho thực thể nội bộ | Idempotency, không gọi chéo |
| [0010](../adr/0010-workspace-isolation-shared-schema-with-mandatory-rls.md) | Shared schema, RLS `FORCE` bắt buộc, bốn role mỗi database, không `BYPASSRLS` ở role đăng nhập được | Cô lập Workspace |
| [0011](../adr/0011-nextjs-bff-with-server-side-session.md) | Next.js làm BFF mỏng, phiên ở Postgres; chỉ `seller-web` và Keycloak ra ngoài cụm | Bảo mật dữ liệu (N11) |
| [0012](../adr/0012-two-persistence-stacks-one-rls-hook.md) | `JdbcClient` cho service có thao tác khó, JPA cho service CRUD, một hook RLS chung | Đúng đắn, cô lập Workspace |

## 9.2 Quyết định không có ADR

Các quyết định sau đổi lại được mà không tốn nhiều công, nên chỉ ghi ở ticket của [map kiến trúc G0–G1](../.scratch/architecture-g0-g1/map.md#decisions-so-far):

| Quyết định | Vì sao không cần ADR | Ticket |
|---|---|---|
| Tách service theo B1 ngay từ G1, bỏ modular monolith ([mục 4.2](04-solution-strategy.md#42-vì-sao-bỏ-modular-monolith)) | Đi ngược C1 nhưng khớp ADR-0001 | [02](../.scratch/architecture-g0-g1/issues/02-deployment-units.md#answer) |
| Ngân sách RAM và cỡ từng thành phần | Số liệu, quyết định nằm ở ADR-0004 | [04](../.scratch/architecture-g0-g1/issues/04-resource-budget.md#answer) |
| Danh mục event, topic, API; envelope; tiền và thời gian; ranh giới N13 | Contract tiến hóa theo `BACKWARD_TRANSITIVE`; ID tất định là phần khó đảo ngược và có ADR-0009 | [09](../.scratch/architecture-g0-g1/issues/09-g1-contracts.md#answer) |
| Template service, `service-kit`, chart `app`, retry/DLT, quy ước REST, GitHub Packages | Đổi qua version của artifact; đổi registry chỉ là sửa URL | [11](../.scratch/architecture-g0-g1/issues/11-service-template.md#answer) |
| Một pod `marketplace-sim` cho cả hai sàn, core và dialect | Image đã là một; tách ra chỉ cần thêm Deployment | [12](../.scratch/architecture-g0-g1/issues/12-shopee-sim.md#answer) |
| Vòng dev: compose trên Mac, Testcontainers, `ct install` trên kind | Không ảnh hưởng runtime của lab | [13](../.scratch/architecture-g0-g1/issues/13-dev-loop.md#answer) |
| Instrument bằng Micrometer + OTLP, không OTel agent | Đổi dependency và cấu hình | [01](../.scratch/architecture-g0-g1/issues/01-infra-standards.md#answer), [observability.md](../standards/observability.md) |

## 9.3 Còn mở ở G0–G1

Theo [map](../.scratch/architecture-g0-g1/map.md): cửa vào cụm ([ticket 16](../.scratch/architecture-g0-g1/issues/16-cluster-entry.md)), chi tiết gateway, chiến lược test G1, polling đơn và mã hóa token ở `channel-connector`, bộ test tuân thủ của simulator. Ba câu hỏi mở ở [SRS chương 9](../requirements/srs.md#9-giả-định-và-câu-hỏi-mở) thuộc G3–G5.
