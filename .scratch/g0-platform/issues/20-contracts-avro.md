# 20: `contracts`: kiểm tương thích Avro và lệnh đăng ký schema

Status: ready-for-human
Blocked by: 19
Repos: contracts, platform, docs
Spec: [G0](../spec.md)

## Mô tả

Nhánh Avro của pipeline `contracts`: chọn plugin sinh code Avro, kiểm `BACKWARD_TRANSITIVE` với Apicurio chạy trong Testcontainers, và một lệnh đăng ký schema dùng chung cho CI, Apicurio trên Mac và trên lab. G0 chưa có schema nghiệp vụ; pipeline được chứng minh bằng một schema thử trong PR không merge. Theo [kafka.md](../../../standards/kafka.md), ticket 13 của map.

## Mục tiêu học

- Tương thích schema `BACKWARD_TRANSITIVE`: thứ tự nâng consumer và producer, field mới có default.

## Tiêu chí nghiệm thu

- [ ] Plugin sinh code Avro chọn theo tiêu chí còn bảo trì, chạy với Gradle 9 và Avro 1.12; ghi lựa chọn kèm nguồn.
- [ ] PR thử: thêm schema rồi một commit xóa field không có default thì CI đỏ ở bước kiểm tương thích.
- [ ] Lệnh đăng ký schema có tên cố định, trỏ được vào `localhost` và vào registry trong cụm; không profile nào bật `auto.register.schemas`.
- [ ] PR thử đã đóng, không merge.
