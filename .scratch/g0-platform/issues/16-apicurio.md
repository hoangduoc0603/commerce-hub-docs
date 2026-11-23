# 16: Apicurio Registry trong cụm

Status: wontfix
Lý do bỏ: 2026-11-24, [ADR-0019](../../../adr/0019-no-contracts-repo.md): event ở G1 là JSON, không có schema registry nên không dựng Apicurio.
~~Hoãn tới: G1 (quyết định 2026-11-15, spec G0 mục "Sửa phạm vi 2026-11-15")
Lý do: G0 không có producer hay consumer nào; làm khi service G1 đầu tiên phát event (nguyên tắc "hạ tầng làm khi code cần tới", mục "Thứ tự làm" của spec).~~
Blocked by: 08, 15
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

Apicurio Registry 3 chạy qua operator trong cụm, nơi lưu theo lựa chọn trong [kafka.md](../../../standards/kafka.md) (nếu là PostgreSQL thì thêm database trên `pg-main`). Không client nào được auto-register: schema chỉ vào registry qua lệnh đăng ký của `contracts` (ticket 20). Limit theo bảng ticket 04 của map.

## Mục tiêu học

- Schema Registry đứng ở đâu trong luồng Avro, và vì sao chặn auto-register.

## Tiêu chí nghiệm thu

- [ ] Registry `Ready`; API trả danh sách artifact rỗng từ một pod trong cụm.
- [ ] Rule tương thích mặc định là `BACKWARD_TRANSITIVE`.
- [ ] Thử tắt UI qua `spec.ui`; ghi kết quả (điểm chưa xác minh) và RAM thật.
- [ ] Registry không có route trên `edge`.
