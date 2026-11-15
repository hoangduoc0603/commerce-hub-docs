---
status: accepted
date: 2026-11-15
---

# ADR-0018: Service tự chứa, chưa có thư viện dùng chung

Từ Giai đoạn 0, mỗi service Spring Boot là **một project bình thường do Spring Initializr sinh ra** (generator Spring Boot của IntelliJ hoặc start.spring.io). Project giữ nguyên mặc định của Initializr: plugin `org.springframework.boot` và `io.spring.dependency-management`, `mavenCentral()` trong `build.gradle`, toolchain Java. Mọi thư viện và cấu hình được khai thẳng trong repo của service. Chỗ nào lệch mặc định thì ghi lý do ngay tại dòng đó ([`spring-service.md`](../standards/spring-service.md)).

Dự án **chưa có thư viện dùng chung**. `libs/service-kit` (ticket G0-18: convention plugin `commercehub.spring-service`, luật ArchUnit, bảng tag image cho Testcontainers, publish lên GitHub Packages) thôi dùng. Repo `commerce-hub-service-kit` được archive, giữ lại làm lịch sử. Phần đã định đặt trong kit đổi chỗ như sau:

- **Problem Details, entry point 401, UUIDv7** (G0-26, 28, 29): viết thẳng trong `services/hello`. Service G1 nhận chúng bằng cách sinh từ template `hello`.
- **Hook RLS và `ScopedValue` của Workspace** ([ADR-0012](0012-two-persistence-stacks-one-rls-hook.md), G0-25): sang Giai đoạn 1, viết trong service đầu tiên có bảng theo Workspace, cùng lúc với case thật (N11 vốn thuộc Giai đoạn 1 trong ma trận truy vết). Ở G0, `hello` chỉ có bảng toàn cục, không có RLS.
- **Layout hexagonal** (`domain`, `application`, `adapter.in.*`, `adapter.out.*`): giữ làm **quy ước**, không có ArchUnit. Chủ repo tự đặt file đúng lớp.
- **Tag image cho Testcontainers**: mỗi service ghim trong test của nó, kèm comment trỏ tới version trong `gitops`.

Lý do: dự án là dự án học, chủ repo mới làm quen với Spring Boot và muốn tự tay cấu hình từng thứ. Một thư viện chung chỉ có lợi khi có ít nhất hai nơi dùng nó, trong khi G0 chỉ có một service. Convention plugin, plugin marker, PAT `read:packages`, `exclusiveContent`, composite build và publish bất biến là chi phí không ai hưởng, đồng thời che mất chính phần cấu hình mà chủ repo muốn học.

## Phương án đã cân nhắc

- **Giữ `service-kit` đầy đủ** (convention plugin cộng thư viện code). Đây là hướng cũ của ticket 11 trong map kiến trúc. Bị loại vì những lý do vừa nêu.
- **Bỏ convention plugin, giữ `service-kit` làm thư viện code thường.** Service vẫn phải đọc GitHub Packages bằng PAT, và kit vẫn phải phát hành theo tag. Bị loại vì ở G0 chưa có đoạn code nào thật sự dùng chung giữa hai service.
- **Giữ ArchUnit, khai thẳng trong `hello`.** Bị loại theo lựa chọn của chủ repo: thêm một thư viện và một lớp test để giữ một quy ước mà chủ repo muốn tự giữ. Có thể thêm lại sau.

## Hệ quả

- Code chung giữa các service được **chép** khi sinh service từ template. Bản chép trôi lệch dần: sửa Problem Details ở `hello` không tự sang service G1. Chấp nhận khi số service còn ít.
- Không có gì tự động chặn code đặt sai lớp. N13 ("thêm sàn mới không sửa lõi") dựa vào review.
- Spec G0 bỏ story 58, 59, 65; chuyển story 60, 61, 62 sang G1; đổi story 63, 64, 75, 76. Ticket G0-25 hoãn tới G1. Chi tiết ở mục "Sửa phạm vi 2026-11-15" của [spec G0](../.scratch/g0-platform/spec.md).
- Reusable workflow `java-library.yml` trong `platform` bị xóa. `contracts` (ticket G0-19) tự viết bước publish Maven của nó. Phần version, publish, bất biến trong [`java-library.md`](../standards/java-library.md) vẫn áp dụng cho `contracts`.
- [ADR-0008](0008-keycloak-authn-only-members-replicated-via-kafka.md) (bản sao Member trong bộ nhớ), [ADR-0010](0010-workspace-isolation-shared-schema-with-mandatory-rls.md) (`ScopedValue`) và [ADR-0012](0012-two-persistence-stacks-one-rls-hook.md) (hook RLS) giữ nguyên quyết định. Chỉ chỗ đặt code đổi từ "thư viện chung" sang "trong service".
- **Xét lại khi** một service thứ hai cần đúng cùng một đoạn code có logic thật. Ứng viên rõ nhất ở G1: hook RLS, filter kiểm Member và bản sao Member, interceptor consumer Kafka. Khi đó viết ADR mới, chọn giữa chép hay tách thư viện. Bài học của G0-18 ([bản ghi mục 8](../experiments/2026-11-g0.md#8-service-kit-010-convention-plugin-luật-kiến-trúc-publish-bất-biến-từ-tag), [`java-library.md`](../standards/java-library.md)) dùng lại được khi đó.
