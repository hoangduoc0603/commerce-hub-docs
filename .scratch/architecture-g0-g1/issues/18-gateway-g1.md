# 18 Gateway ở G1: MVC hay WebFlux, rate limit theo Workspace

Type: grilling
Status: resolved
Blocked by:
Map: [Kiến trúc G0–G1](../map.md)

## Question

Đã chốt: gateway chỉ kiểm JWT và định tuyến, không kiểm Member ([05](05-identity-model.md#answer)); là ClusterIP, chỉ nhận traffic từ `seller-web`, không CORS, SSE ở G2 đi qua nó ([07](07-frontend-access.md#answer)); template dùng Spring MVC chạy virtual thread ([11](11-service-template.md#answer)). Còn lại:

- Spring Cloud Gateway bản Server MVC hay Server WebFlux. Bản MVC khớp template; cần kiểm nó có giữ được kết nối SSE dài ở G2 (timeout, buffering) không.
- Rate limit theo Workspace có làm ở G1 không. Nếu có thì đếm ở đâu (Redis chưa có trong ngân sách RAM của ticket [04](04-resource-budget.md#answer)).
- Header `X-Workspace-Id` đi qua gateway nguyên vẹn hay gateway chuẩn hóa/kiểm định dạng.

## Answer

Chốt ngày 2026-11-13 (người dùng), một vòng grilling (Q1–Q6). Không có ADR: gateway không giữ trạng thái, không có logic nghiệp vụ, nên đổi bản MVC sang WebFlux vẫn rẻ.

Tra cứu (2026-11-13, subagent đọc docs và source):
- Boot 4.1 dùng train **2025.1.x**, từ 2025.1.2 trở lên, Gateway 5.0.x ([spring.io/projects/spring-cloud](https://spring.io/projects/spring-cloud)). Artifact là `spring-cloud-starter-gateway-server-webmvc`, prefix property `spring.cloud.gateway.server.webmvc.*` ([release notes 2025.0](https://github.com/spring-cloud/spring-cloud-release/wiki/Spring-Cloud-2025.0-Release-Notes)).
- Server MVC **stream** `text/event-stream`: gọi `flush()` sau mỗi chunk, buffer 16 KiB ([`AbstractProxyExchange` 5.0.x](https://github.com/spring-cloud/spring-cloud-gateway/blob/5.0.x/spring-cloud-gateway-server-webmvc/src/main/java/org/springframework/cloud/gateway/server/mvc/common/AbstractProxyExchange.java)). [#3999](https://github.com/spring-cloud/spring-cloud-gateway/issues/3999) (rò kết nối khi client SSE ngắt) đã sửa ở 5.0.3. [#4357](https://github.com/spring-cloud/spring-cloud-gateway/issues/4357) (upstream cắt giữa stream thì log ERROR và dispatch `/error`) còn mở.
- Server MVC **không có timeout theo route** ([#3127](https://github.com/spring-cloud/spring-cloud-gateway/issues/3127) còn mở). Chỉ có timeout chung `spring.http.clients.connect-timeout` / `read-timeout` của `RestClient` do Boot cấu hình. Với client JDK, `readTimeout` tính **tổng thời gian** request, hết giờ thì đóng body dù dữ liệu vẫn đang chảy ([`JdkClientHttpRequest` 7.0.x](https://github.com/spring-projects/spring-framework/blob/7.0.x/spring-web/src/main/java/org/springframework/http/client/JdkClientHttpRequest.java), suy từ source). Jetty và Apache có phải idle timeout không: **chưa xác minh**.
- Rate limit ở Server MVC là `Bucket4jFilterFunctions.rateLimit`, key resolver chỉ khai bằng Java DSL. Tài liệu chỉ có ví dụ Caffeine (tính riêng từng pod) ([ratelimiter](https://docs.spring.io/spring-cloud-gateway/reference/spring-cloud-gateway-server-webmvc/filters/ratelimiter.html)). Local rate limit của Envoy Gateway v1.10 có `Distinct` theo giá trị, không cần Redis ([local-rate-limit](https://gateway.envoyproxy.io/v1.10/tasks/traffic/local-rate-limit/)), nhưng `edge` đứng trước `seller-web`, không đứng trước gateway.

### Quyết định

1. **Spring Cloud Gateway Server MVC** (Q6), train 2025.1.x mới nhất tương thích Boot 4.1 lúc viết spec, chạy virtual thread. Repo `services/gateway` sinh từ template `hello`, bỏ persistence, Kafka và hook RLS. Vẫn dùng `service-kit` (Problem Details, OTel, actuator trên management port) và chart `app`. Loại WebFlux: G1 không có SSE. WebFlux kéo theo mô hình reactive cho một service duy nhất, không dùng lại được `service-kit` viết cho MVC, và không thêm case kỹ thuật nào G1 cần. Rủi ro SSE để G2 đo (xem Out of scope của map).
2. **Không có rate limit ở G1** (Q1). Rate limit theo Workspace ở gateway chuyển sang G3, làm cùng Redis (ticket 04 không có Redis ở G0–G1). Khi làm, **khóa đếm phải có `sub`** (`(sub)` hoặc `(sub, workspaceId)`), không dùng `X-Workspace-Id` thô. Lý do: gateway không kiểm Member, nên một Account bất kỳ gửi ID Workspace của người khác là đốt được hạn mức của Workspace đó.
3. **`X-Workspace-Id` chuyển nguyên, gateway không kiểm** (Q2). `libs/workspace-access` là nơi kiểm duy nhất. Header thiếu, sai định dạng hoặc lặp nhiều lần thì service trả **404** như trường hợp không phải Member (BR-04). Endpoint cấp Account (`GET /me`, tạo Workspace) không cần header này.
4. **Mọi route qua gateway bắt buộc JWT, không ngoại lệ** (Q3). `Authorization` chuyển nguyên xuống service, service kiểm lại (ADR-0008). Actuator nằm trên management port, không định tuyến. OAuth callback của sàn (F2.1a) về một **trang** của `seller-web` (không nằm dưới `/api`, nên không vướng luật `Sec-Fetch-Site`). Trang đó gửi `code` và `state` xuống `channel-connector` bằng `POST` qua BFF, kèm Bearer như mọi request khác.
5. **Đường dẫn theo tài nguyên, có tiền tố `/v1`** (Q4). BFF chuyển `/api/v1/<path>` thành `/v1/<path>`. Gateway giữ bảng khoảng 10 tiền tố tài nguyên → service (`/v1/me`, `/v1/workspaces/**` → `workspace`; `/v1/shops/**` → `channel-connector`; `/v1/master-skus/**`, `/v1/listings/**` → `catalog`; `/v1/stock-items/**` → `inventory`; `/v1/orders/**` → `order`…). Bảng cuối cùng do spec viết theo OpenAPI. URL không lộ ranh giới service. Bảng route nằm trong values của chart ở `gitops`, URL backend dùng DNS của K8s. Path không khớp route nào thì trả 404.
6. **Timeout chung, không retry, không circuit breaker** (Q5): `spring.http.clients.connect-timeout=2s`, `read-timeout=10s` cho mọi route. Không retry vì lệnh ghi không idempotent có thể chạy hai lần, và BFF cũng không retry. Circuit breaker và Resilience4j để G3 (C18). Gateway trả mã gì khi quá timeout: **chưa xác minh**. Spec phải có test khẳng định **504 Problem Details**; gateway trả mã khác thì thêm handler để đổi.

### Đã cập nhật

- Map: Decisions so far; Out of scope thêm rate limit theo Workspace (G3) và thí nghiệm SSE qua gateway MVC (G2).
- [Phần B1, C](../../../requirements-and-techniques.md): dòng gateway không còn rate limit hay Redis ở G1.
- arc42: mục 3 (callback OAuth), mục 5 (container `gateway`), mục 8.3 (gateway), mục 8.7 (đường dẫn `/v1`, timeout).
- Comment ở ticket 07, 11, 17.

## Comments
