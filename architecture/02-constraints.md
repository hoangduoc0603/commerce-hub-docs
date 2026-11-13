# 2. Ràng buộc

## 2.1 Kỹ thuật

| Ràng buộc | Nội dung | Nguồn |
|---|---|---|
| Stack nền | Java 25, Spring Boot 4.1.x, Kafka 4.x, PostgreSQL 17+, Next.js + TypeScript | [Charter mục 4](../project-charter.md#4-ràng-buộc) |
| Bản đã ghim cho G0–G1 | Kubernetes 1.37 (kubeadm); Strimzi 1.3.1 + Kafka 4.3.2; Apicurio Registry 3.3; CloudNativePG 1.30.1 + PostgreSQL 18; Keycloak 26.8.2; Argo CD 3.6.1; Gateway API CRD v1.6.1 (standard) + Envoy Gateway v1.10.0; trust-manager v0.26.0; Next.js 16.4.x; Gradle 9 | Ticket [01](../.scratch/architecture-g0-g1/issues/01-infra-standards.md#answer), [03](../.scratch/architecture-g0-g1/issues/03-postgres-on-cluster.md#answer), [05](../.scratch/architecture-g0-g1/issues/05-identity-model.md#answer), [07](../.scratch/architecture-g0-g1/issues/07-frontend-access.md#answer), [11](../.scratch/architecture-g0-g1/issues/11-service-template.md#answer), [16](../.scratch/architecture-g0-g1/issues/16-cluster-entry.md#answer), [`standards/`](../standards/) |
| Đã chốt sẵn từ Phần C | Hexagonal + ACL ở `channel-connector`; database per service; REST + OpenAPI contract-first; service discovery bằng DNS của K8s; Kafka + Avro + Schema Registry; multi-tenancy shared schema có cột `workspace_id`; Next.js App Router + TanStack Query; simulator viết bằng Spring Boot | [Map, Notes](../.scratch/architecture-g0-g1/map.md#notes) |
| Không kết nối sàn thật | Adapter viết theo tài liệu chính thức của sàn nhưng chỉ chạy với simulator. Thông tin sàn chưa kiểm được thì thành giả định AS-xx, simulator cấu hình được | [SRS 2.4](../requirements/srs.md#24-ràng-buộc), [chương 9](../requirements/srs.md#9-giả-định-và-câu-hỏi-mở) |
| Không cloud trả phí | Mọi thứ chạy trên home lab hoặc dịch vụ miễn phí cho repo public (GitHub Actions, GitHub Packages) | Charter, [ADR-0006](../adr/0006-public-repos-on-personal-account.md) |

## 2.2 Hạ tầng

| Ràng buộc | Nội dung | Nguồn |
|---|---|---|
| Một máy home lab | i9-10900, 32 GB RAM, không nâng được. Hyper-V chạy 3 node K8s (8 GiB mỗi node, 24 GiB tổng) và VM `gw` (Tailscale, registry image, RustFS cho backup, dnsmasq cho `lab.internal`, Mailpit) | [homelab](../../platform/docs/homelab-hyperv.md), [ADR-0004](../adr/0004-single-instance-by-default-on-homelab.md) |
| Một instance mặc định | Mọi service, simulator, frontend, `pg-main` và Keycloak chạy 1 instance ở lab. Chart vẫn mặc định 2 replica; chỉ values lab đặt 1. Tăng khi làm thí nghiệm (N15, failover) rồi revert | [ADR-0004](../adr/0004-single-instance-by-default-on-homelab.md) |
| Ngân sách RAM | Hạ tầng khoảng 18,7 GiB, ứng dụng G1 khoảng 4,6 GiB, cửa vào cụm (Envoy Gateway, trust-manager) khoảng 480 MiB, còn dư khoảng 520 MiB ([ADR-0013](../adr/0013-gateway-api-envoy-gateway-shared-edge.md)). Service JVM 512 Mi, Kafka 1 Gi/broker. Phải đo lại ở G0 | Ticket [04](../.scratch/architecture-g0-g1/issues/04-resource-budget.md#answer) |
| Một môi trường | Lab là môi trường duy nhất ngoài MacBook. Không có staging. Mac không ghi vào hạ tầng lab | [ADR-0004](../adr/0004-single-instance-by-default-on-homelab.md), ticket [13](../.scratch/architecture-g0-g1/issues/13-dev-loop.md#answer) |
| Máy dev | MacBook M1 Pro 16 GB (arm64). Image service chỉ build `linux/amd64`, nên không chạy service trong compose trên Mac | Ticket [13](../.scratch/architecture-g0-g1/issues/13-dev-loop.md#answer) |

## 2.3 Tổ chức

| Ràng buộc | Nội dung | Nguồn |
|---|---|---|
| Một người làm, ngoài giờ | Tránh vận hành thứ không cần. Mọi lựa chọn cân thêm chi phí vận hành | Charter |
| Polyrepo | Mỗi repo là một đơn vị phát hành. Repo chỉ nối nhau qua contract, artifact có version và runtime | [ADR-0001](../adr/0001-polyrepo.md) |
| Repo public | Tài khoản GitHub cá nhân, gói Free, MIT. CI chạy trên GitHub-hosted runner, vào lab qua Tailscale. Nhánh chỉ chặn force push và xóa | [ADR-0006](../adr/0006-public-repos-on-personal-account.md) |
| SDLC lặp tăng dần | Increment theo giai đoạn C18. Xong khi đạt Definition of Done, kể cả cập nhật ma trận truy vết | [Charter mục 5](../project-charter.md#5-mô-hình-phát-triển-sdlc) |

## 2.4 Quy ước

- Tài liệu viết tiếng Việt; định danh code và thuật ngữ GLOSSARY giữ tiếng Anh. Không dùng "tenant" trong định danh code ([GLOSSARY](../GLOSSARY.md)).
- Artifact hạ tầng và cross-cutting theo checklist trong [`docs/standards/`](../standards/). Chỗ cố ý lệch chuẩn ghi lý do tại chỗ hoặc bằng ADR.
- Mã yêu cầu ghi trong commit, tên test và ADR để truy vết được.
- Thị trường Việt Nam: giao diện tiếng Việt, hiển thị giờ Asia/Ho_Chi_Minh và tiền VND. Dữ liệu lưu UTC, tiền có trường tiền tệ ([mục 8.6](08-crosscutting-concepts.md#86-canonical-model-id-tiền-và-thời-gian)).
