# 18 Gateway ở G1: MVC hay WebFlux, rate limit theo Workspace

Type: grilling
Status: open
Blocked by:
Map: [Kiến trúc G0–G1](../map.md)

## Question

Đã chốt: gateway chỉ kiểm JWT và định tuyến, không kiểm Member ([05](05-identity-model.md#answer)); là ClusterIP, chỉ nhận traffic từ `seller-web`, không CORS, SSE ở G2 đi qua nó ([07](07-frontend-access.md#answer)); template dùng Spring MVC chạy virtual thread ([11](11-service-template.md#answer)). Còn lại:

- Spring Cloud Gateway bản Server MVC hay Server WebFlux. Bản MVC khớp template; cần kiểm nó có giữ được kết nối SSE dài ở G2 (timeout, buffering) không.
- Rate limit theo Workspace có làm ở G1 không. Nếu có thì đếm ở đâu (Redis chưa có trong ngân sách RAM của ticket [04](04-resource-budget.md#answer)).
- Header `X-Workspace-Id` đi qua gateway nguyên vẹn hay gateway chuẩn hóa/kiểm định dạng.
