# 12 Kiến trúc shopee-sim cho SIM-01..08

Type: grilling
Status: open
Blocked by:
Map: [Kiến trúc G0–G1](../map.md)

## Question

shopee-sim ở G1 (SIM-01..08: OAuth, ký, đơn, API lấy đơn) được thiết kế thế nào để G2 thêm tiktok-sim không viết lại?
- Lõi dùng chung + "dialect" từng sàn (C17): một repo hai artifact, hay lib trong `libs/`.
- Trạng thái simulator (shop, token, đơn, tồn trên sàn) lưu ở đâu; có cần bền qua restart không.
- Admin API điều khiển kịch bản; cấu hình các giả định AS-xx (SRS chương 9) bằng gì.
- Simulator chạy trong cụm như service thường (Helm, GitOps) hay riêng.
