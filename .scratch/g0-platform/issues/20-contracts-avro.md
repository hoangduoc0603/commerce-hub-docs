# 20: `contracts`: kiểm tương thích Avro và lệnh đăng ký schema

Status: wontfix
Lý do bỏ: 2026-11-24, [ADR-0019](../../../adr/0019-no-contracts-repo.md): không còn repo `contracts`, event ở G1 là JSON, không kiểm tương thích.
~~Hoãn tới: G1 (quyết định 2026-11-15, spec G0 mục "Sửa phạm vi 2026-11-15")
Lý do: G0 không có producer hay consumer nào; làm khi service G1 đầu tiên phát event (nguyên tắc "hạ tầng làm khi code cần tới", mục "Thứ tự làm" của spec).~~
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
