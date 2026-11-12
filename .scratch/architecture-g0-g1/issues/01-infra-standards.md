# 01 Checklist chuẩn production cho hạ tầng G0

Type: research
Status: resolved
Blocked by:
Map: [Kiến trúc G0–G1](../map.md)

## Question

Chuẩn production (có nguồn chính thức, ngày tra) cho các artifact hạ tầng của Giai đoạn 0 là gì? Chín chủ đề, mỗi chủ đề một file trong [`docs/standards/`](../../../standards/): `container-image`, `helm-chart`, `zero-downtime`, `gitops-argocd`, `ci-cd`, `db-migration`, `kafka`, `observability`, `keycloak`. Mỗi file nêu rõ lựa chọn nào nên thành ADR và điểm nào **chưa xác minh**.

## Answer

Xong 2026-11-12: đủ 9 file trong [`docs/standards/`](../../../standards/), mỗi mục checklist có nguồn chính thức. Đây là **đầu vào**, chưa phải quyết định: lựa chọn nào khó đảo ngược thì chốt ở ticket tương ứng.

Đề xuất mà agent đánh dấu "nên viết ADR", và ticket sẽ chốt:
- Nơi chạy migration (Job hook `PreSync`), phân quyền DB owner/migrator/app + `FORCE ROW LEVEL SECURITY` → ticket 06, 11 ([db-migration.md](../../../standards/db-migration.md))
- Secret trong GitOps: Sealed Secrets → ticket 11 hoặc spec G0 ([gitops-argocd.md](../../../standards/gitops-argocd.md))
- CI vào registry lab: GitHub-hosted runner + `tailscale/github-action` → ticket 15 ([ci-cd.md](../../../standards/ci-cd.md))
- Schema Registry: Apicurio 3.3 + serializer Confluent, `TopicRecordNameStrategy`, `BACKWARD_TRANSITIVE` (lệch với `BACKWARD` trong `contracts/README.md`) → ticket 09 ([kafka.md](../../../standards/kafka.md))
- Instrument bằng Micrometer + OTLP, không dùng OTel Java agent ([observability.md](../../../standards/observability.md))
- Một realm, Keycloak chỉ xác thực Account; Workspace/Member/vai trò ở `tenant`, Workspace truyền bằng header → ticket 05 ([keycloak.md](../../../standards/keycloak.md))
- Next.js theo mẫu BFF (confidential client, PKCE) → ticket 07
- Gradle, chart dùng chung tên `application` → ticket 11

Phát hiện ảnh hưởng ticket khác:
- Bảng RAM trong `platform/docs/homelab-hyperv.md` thiếu Keycloak (~1,5 GB) và LGTM (~3–4,5 GB), nên phần ~8–9 GB cho service bị ước dư 4,5–6 GB → ticket 04.
- Strimzi chưa hỗ trợ Kafka 4.4; ghim Strimzi 1.3.1 + Kafka 4.3.2. 3 node dual-role là lệch chuẩn khó tách về sau → ticket 04.

Các điểm **chưa xác minh** nằm trong từng file, cần thử thật khi dựng G0.
