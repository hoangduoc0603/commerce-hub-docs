# 34: Đo 24 giờ, cổng ADR-0004 và đóng G0

Status: ready-for-human
Blocked by: 09, 16, 20, 31, 32, 33
Repos: docs, gitops
Spec: [G0](../spec.md)

## Mô tả

Đóng G0 bằng số đo và tài liệu. Đo `kubectl top` toàn cụm sau 24 giờ chạy tải nền (hạ tầng G0 cộng `hello`), so với bảng của [ADR-0004](../../../adr/0004-single-instance-by-default-on-homelab.md) và phần dự kiến cho G1; đo RSS của `hello` ở `MaxRAMPercentage=60`. Thiếu quá 1 GiB so với ngân sách G1 thì sửa ADR-0004 trước khi viết spec G1. Viết bản ghi thí nghiệm tổng của G0 (giả thuyết, cách đo, số đo, kết luận), arc42 mục 7, runbook còn thiếu, và cập nhật `docs/standards/`. Ghi rằng Deployment `hello` sẽ gỡ khỏi `gitops` khi service G1 đầu tiên lên lab.

## Mục tiêu học

- Lập kế hoạch dung lượng bằng số đo thật, và khi nào số đo buộc phải sửa một quyết định.

## Tiêu chí nghiệm thu

- [ ] `kubectl top pod -A` sau 24 giờ, theo nhóm của bảng ngân sách; không pod nào OOMKilled.
- [ ] RSS đỉnh của `hello` dưới 90% limit (NMT summary); chốt `MaxRAMPercentage` cho G1.
- [ ] Quyết định giữ hay sửa ADR-0004, có số đo đi kèm.
- [ ] Mọi điểm **chưa xác minh** thuộc G0 trong spec đã có kết quả trong `docs/standards/` (đã xác minh, hoặc lệch chuẩn có lý do).
- [ ] arc42 mục 7 (deployment view) và mục 9 cập nhật; runbook bootstrap, khóa sealing, thêm service, admin realm đầy đủ.
- [ ] Bản ghi thí nghiệm G0 trong `docs/experiments/` link tới các bản ghi theo chủ đề.
- [ ] Dòng "Phase hiện tại" trong CLAUDE.md và ma trận truy vết phản ánh G0 xong.
