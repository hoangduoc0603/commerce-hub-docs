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
