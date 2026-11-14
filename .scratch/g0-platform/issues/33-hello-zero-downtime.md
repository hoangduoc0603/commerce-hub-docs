# 33: Rollout `hello` không lỗi dưới tải

Status: ready-for-human
Blocked by: 27, 29
Repos: gitops, platform, load-tests, docs
Spec: [G0](../spec.md)

## Mô tả

Chứng minh cấu hình zero-downtime của chart `app` bằng số đo. `hello` tạm chạy 2 replica (theo ADR-0004, revert sau thí nghiệm). k6 chạy `constant-arrival-rate` 50 req/s trong 5 phút qua `https://hello.lab.internal` (đúng đường production, tin root CA, có token client credentials) trong lúc đổi image qua GitOps, `rollout restart`, drain node, và deploy có migration. Chạy thêm một lần đối chứng âm (bỏ preStop, `maxUnavailable: 25%`). Theo [zero-downtime.md](../../../standards/zero-downtime.md).

## Mục tiêu học

- Vòng đời pod khi rollout: gỡ endpoint, preStop, graceful shutdown, và cách đo để chỉnh thay vì đoán.

## Tiêu chí nghiệm thu

- [ ] k6 trên macOS đọc được root trong Keychain, không đặt `insecureSkipTLSVerify` (điểm chưa xác minh).
- [ ] Bốn tình huống: `http_req_failed` = 0, `checks` = 100%.
- [ ] Đối chứng âm có request lỗi; nếu không có thì tăng tải và ghi lại.
- [ ] Số đo phụ: độ trễ gỡ endpoint, thời gian shutdown thật, thời gian tới Ready; không pod nào exit 137. Chỉnh preStop và `startupProbe` theo số đo.
- [ ] Kịch bản k6 nằm trong repo `load-tests`; bản ghi `docs/experiments/` theo tên của chuẩn.
- [ ] `hello` trở lại 1 replica bằng một commit revert.
