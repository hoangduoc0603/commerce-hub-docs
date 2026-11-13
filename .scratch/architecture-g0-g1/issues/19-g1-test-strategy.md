# 19 Chiến lược test G1 và bộ test tuân thủ của simulator

Type: grilling
Status: open
Blocked by: 17
Map: [Kiến trúc G0–G1](../map.md)

## Question

Những gì đã chốt rải rác: Testcontainers chạy cả trên Mac lẫn CI, PgBouncer dùng `ghcr.io/cloudnative-pg/pgbouncer`, luồng đầy đủ chỉ kiểm trên lab ([13](13-dev-loop.md#answer)); test N11 ba tầng ([06](06-workspace-isolation.md#answer)); property-based test cho bất biến sổ cái BR-29 và test race thứ tự khóa ([10](10-inventory-write-model.md#answer)); e2e đi qua BFF với đăng nhập thật, test refresh song song, test backchannel logout cho F1.1b ([07](07-frontend-access.md#answer)). Còn lại:

- Contract test giữa service: có dùng Pact cho REST ở G1 không (chỉ còn một lệnh REST nội bộ F3.3c theo [08](08-g1-communication.md#answer)), event thì kiểm bằng schema compatibility là đủ hay cần thêm.
- e2e chạy ở đâu và khi nào (sau mỗi lần Argo CD sync trên lab?), công cụ gì.
- **Bộ test tuân thủ của simulator so với connector**: dựng từ ví dụ trong tài liệu Shopee, chạy ở CI của repo nào, và có dùng làm contract test cho adapter của connector không.
- Test nào là điều kiện để một increment G1 đạt Definition of Done ([Charter mục 5](../../../project-charter.md#5-mô-hình-phát-triển-sdlc)).
