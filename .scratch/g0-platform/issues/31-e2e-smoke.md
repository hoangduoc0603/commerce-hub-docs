# 31: Smoke e2e sau mỗi deploy

Status: ready-for-human
Hoãn tới: G7 (quyết định 2026-11-15, spec G0 mục "Sửa phạm vi 2026-11-15")
Lý do: smoke e2e cần repo `e2e`, runner vào tailnet (`tag:e2e`) và token Grafana, đều là hạ tầng; ở G0 các hành vi này được kiểm tay ở ticket 29, 30 và cổng ticket 34.
Blocked by: 12, 29, 30
Repos: e2e, platform, gitops, docs
Spec: [G0](../spec.md)

## Mô tả

Repo `e2e` (tạo bằng script ticket 01), Playwright TypeScript, chạy trên GitHub-hosted runner vào tailnet bằng `tag:e2e` (ACL chỉ tới `10.20.0.200:443` và DNS `10.20.0.5:53`), tin root CA của lab qua store của OS. Kích hoạt bằng `repository_dispatch` do `update-gitops` gửi, lịch hằng đêm và chạy tay; `concurrency` `e2e-lab` không hủy. Bước đầu chờ `argocd app wait <app> --sync --health --timeout 10m` bằng token chỉ đọc. Smoke đọc Tempo và Prometheus qua API proxy datasource của Grafana bằng service account Viewer. Theo ticket 19 của map.

## Mục tiêu học

- Kiểm sau deploy trên môi trường thật, và chờ nhất quán cuối cùng bằng poll thay cho `sleep`.

## Tiêu chí nghiệm thu

- [ ] Không token và token sai `aud` trả 401 Problem Details có `traceId`.
- [ ] Token client credentials: tạo lời chào (201), đọc lại (200), ID lạ (404), tên quá dài (400 có `errors[]`).
- [ ] Test tự sinh `traceparent`; `expect.poll` tới khi Tempo có trace đó với span HTTP server và span DB của `hello`.
- [ ] Dashboard "Service overview" tồn tại theo UID; Prometheus có `http_server_requests_seconds_count` của `hello`.
- [ ] Một merge vào `hello` tự kích hoạt e2e qua `repository_dispatch` và xanh.
- [ ] Làm hỏng cố ý (ví dụ đổi `aud` mong đợi) thì e2e đỏ và có báo cáo Playwright làm artifact.
- [ ] Đọc package npm của `contracts` từ CI của `e2e` bằng `GITHUB_TOKEN`; ghi kết quả (điểm chưa xác minh).
