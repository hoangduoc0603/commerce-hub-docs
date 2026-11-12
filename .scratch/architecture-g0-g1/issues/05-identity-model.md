# 05 Mô hình danh tính và Workspace trong token

Type: grilling
Status: open
Blocked by: 01, 02
Map: [Kiến trúc G0–G1](../map.md)

## Question

Keycloak, gateway và service `tenant` chia việc thế nào cho F1.1a–c, F1.2a–b?
- Một realm + Organizations hay realm theo Workspace ([keycloak.md](../../../standards/keycloak.md)).
- Workspace hiện hành nằm ở đâu: claim trong token, header do FE gửi rồi gateway kiểm với `tenant`, hay token đổi khi chuyển Workspace (F1.1c).
- Vai trò và phạm vi theo Shop/Warehouse (F1.2a–b) lưu ở Keycloak hay ở `tenant`.
- Email xác minh F1.1a ở G1 do Keycloak gửi hay đợi notification (G2).
