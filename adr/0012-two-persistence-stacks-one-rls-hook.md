---
status: accepted
date: 2026-11-13
---

# ADR-0012: Hai công nghệ persistence theo loại service, một hook RLS chung

Service có thao tác khó dùng **`JdbcClient` với SQL viết tay**: inventory (khóa `FOR UPDATE` theo thứ tự, số dư và sổ cái), order (upsert có điều kiện version ở ba luồng), channel-connector (token, checkpoint). Service CRUD dùng **Spring Data JPA/Hibernate**: workspace, catalog, marketplace-sim. Riêng catalog viết upsert có version guard của `ChannelListingSynced` bằng `@Query(nativeQuery = true)`.

Cả hai đường đặt Workspace cho RLS ([ADR-0010](0010-workspace-isolation-shared-schema-with-mandatory-rls.md)) ở **cùng một điểm**: một `TransactionExecutionListener` (Spring Framework 6.1+) trong `libs/service-kit` module `workspace-access`. Ở `afterBegin`, listener lấy connection đang gắn với transaction qua `DataSourceUtils`, rồi chạy `set_config('app.workspace_id', ?, true)`. Listener chạy cho cả `DataSourceTransactionManager` lẫn `JpaTransactionManager`, vì `JpaTransactionManager` gắn JDBC connection vào `DataSource` ngay lúc begin.

Service JPA bắt buộc ba điều sau, và test của `service-kit` kiểm chúng:
- `spring.jpa.open-in-view=false`;
- không bật second-level cache, vì cache dùng chung giữa các Workspace mà RLS không che được;
- `spring.jpa.hibernate.ddl-auto=validate`, vì Flyway sở hữu schema.

Bối cảnh ở ticket [11 Template service Spring Boot](../.scratch/architecture-g0-g1/issues/11-service-template.md).

## Phương án đã cân nhắc

- **`JdbcClient` cho mọi service.** Đường cô lập Workspace đơn giản nhất. Bị loại vì mục tiêu học: dự án muốn hiểu cả ORM, và workspace/catalog/marketplace-sim chủ yếu là CRUD.
- **JPA cho mọi service.** Bị loại vì JPA che SQL và khóa. Thứ tự `FOR UPDATE` của ticket 10 và upsert `WHERE version < :v` là các case kỹ thuật cần thấy rõ trong code. `@Version` cũng bị ticket 10 loại vì retry dồn dập khi flash sale.
- **jOOQ.** Bị loại vì phải sinh code từ schema lúc build (Flyway + Testcontainers ngay trong bước build), trong khi phần học được về SQL đã có ở `JdbcClient`.
- **Mỗi công nghệ một hook** (lớp con `DataSourceTransactionManager`, `MultiTenantConnectionProvider` của Hibernate). Bị loại vì hai đường cô lập thì gấp đôi chỗ sai. Hơn nữa, `MultiTenantConnectionProvider` lấy connection *trước* khi Hibernate tắt autocommit, nên `set_config(..., true)` rơi vào một transaction ngầm rồi mất.

## Hệ quả

- Có hai cách viết tầng persistence. Người đọc code phải biết service đang thuộc loại nào. Template `services/hello` minh họa cả hai.
- Với service JPA, ArchUnit cho phép annotation `jakarta.persistence.*` nằm trong `domain`, để khỏi nhân đôi class. Spring và adapter vẫn bị cấm trong `domain`.
- **Chưa xác minh**: với Hibernate 7 trong Spring Boot 4.1, connection đã gắn với `DataSource` lúc `afterBegin` hay chưa. Test hành vi N11 chạy qua PgBouncer `transaction` (ticket 06) phải chạy với **cả** một service JPA lẫn một service `JdbcClient`. Nếu không đạt thì JPA cần một lớp con `JpaTransactionManager`, và ADR này phải sửa.
- Đổi công nghệ của một service về sau nghĩa là viết lại adapter persistence của service đó. Domain và hook giữ nguyên.
