# 11 Template service Spring Boot

Type: grilling
Status: open
Blocked by: 01, 02
Map: [Kiến trúc G0–G1](../map.md)

## Question

Một service mới bắt đầu từ đâu?
- Build tool: Gradle (đề xuất trong [container-image.md](../../../standards/container-image.md), [ci-cd.md](../../../standards/ci-cd.md)) hay Maven.
- Layout module hexagonal (domain / application / adapter), quy tắc phụ thuộc kiểm bằng gì (ArchUnit?).
- Cái gì vào `libs/` dùng chung (tenant context, observability, error model) và cái gì không; version và publish thế nào.
- Template là repo mẫu, generator, hay copy tay; chart dùng chung tên `spring-service` (platform README) hay `application` (helm-chart.md).

## Comments
- 2026-11-12: Từ ticket [04 Ngân sách tài nguyên home lab](04-resource-budget.md#answer): values lab cho mỗi service là `replicaCount: 1`, memory 512Mi (request = limit). Chart vẫn mặc định 2 ([ADR-0004](../../../adr/0004-single-instance-by-default-on-homelab.md)). Với 512Mi, `MaxRAMPercentage=75` nhiều khả năng quá cao (non-heap chỉ còn ~128Mi), nên template cần cho đổi được và spec G0 phải đo RSS.
- 2026-11-12: Từ ticket [08 Giao tiếp giữa service ở G1](08-g1-communication.md#answer): template cần một port publish duy nhất, gọi bên trong `@Transactional`. Bản G1 gửi Kafka ở `AFTER_COMMIT` (cố ý dual-write), bản G2 ghi dòng outbox ([ADR-0005](../../../adr/0005-kafka-from-g1-with-deliberate-dual-write.md)). Consumer idempotent bằng bảng inbox có từ G1. Retry và DLT theo [kafka.md](../../../standards/kafka.md) cần chốt ở ticket này.
- 2026-11-12: Từ ticket [12 Kiến trúc shopee-sim](12-shopee-sim.md#answer): `marketplace-sim` dùng chung template và chart với service, nhưng cần hai thứ mà chart phải cho bật được: một port thứ hai cho admin API, và Ingress có nhiều hostname trỏ về cùng một Service.
- 2026-11-13: Từ ticket [05 Mô hình danh tính và Workspace trong token](05-identity-model.md#answer): `libs/workspace-access` là thư viện dùng chung. Nó đọc topic Member vào bộ nhớ: tự gán mọi partition, không consumer group, đọc từ đầu khi khởi động; readiness chỉ `UP` khi đã tới end offset (không fail-open). Từ `sub` + `X-Workspace-Id` dựng `MemberContext`; không phải Member thì 404. Thư viện chỉ giữ enum Role, kiểu Scope, `MemberContext`; bảng quyền F1.2a mỗi service tự giữ. Gọi giữa service dùng client credentials kèm `X-Workspace-Id` ([ADR-0008](../../../adr/0008-keycloak-authn-only-members-replicated-via-kafka.md)).
