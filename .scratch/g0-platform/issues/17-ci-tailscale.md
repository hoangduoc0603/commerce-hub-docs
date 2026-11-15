# 17: Khung reusable workflow, build và push lên GHCR

Status: ready-for-human
Blocked by: 01
Repos: platform, docs
Spec: [G0](../spec.md)

## Mô tả

Dựng bộ khung reusable workflow trong `platform`: release SemVer bất biến, ghim SHA, `permissions` tối thiểu. Kèm một reusable workflow build và push lên GHCR (`ghcr.io`) bằng `GITHUB_TOKEN` (`packages: write`), dùng lại ở ticket 21 (chart) và 23 (image). CI không vào lab: Argo CD và kubelet kéo artifact từ GHCR. Registry HTTP `10.20.0.5:5000` trên `gw` tắt. Theo [ADR-0017](../../../adr/0017-images-and-charts-on-ghcr.md) và mục "Quyền và credential", "Reusable workflow" của [ci-cd.md](../../../standards/ci-cd.md).

## Mục tiêu học

- Token ngắn hạn của job (`GITHUB_TOKEN` với `permissions` tối thiểu) thay cho secret dài hạn.
- Reusable workflow có version: release bất biến, repo gọi ghim SHA.

## Thu hẹp 2026-11-15

Theo quyết định D6 (spec G0 mục "Sửa phạm vi 2026-11-15", [ADR-0017](../../../adr/0017-images-and-charts-on-ghcr.md)).

- Giữ: khung reusable workflow trong `platform` (SemVer bất biến, ghim SHA, `permissions` tối thiểu).
- Đổi: đích push là GHCR thay cho registry HTTP trên `gw`; CI push bằng `GITHUB_TOKEN`, không cần Tailscale.
- Hoãn tới G7: runner vào tailnet bằng `tailscale/github-action` với OIDC, node ephemeral, ACL theo tag. Sau thay đổi này chỉ e2e (ticket 31) còn cần, mà e2e đã sang G7.

Tiêu chí hoãn tới G7:

- Một workflow thử vào tailnet chỉ tới được đích ACL cho phép; gọi `10.20.0.10:6443` thất bại.
- Không có auth key Tailscale dài hạn trong secret của repo.
- Node của runner biến khỏi tailnet sau khi job xong.
- PR từ fork không vào được tailnet.

## Tiêu chí nghiệm thu

- [ ] Một workflow thử trong `platform` gọi reusable workflow, build một image thử và push lên `ghcr.io` bằng `GITHUB_TOKEN`; repo không có secret registry nào.
- [ ] Job push chỉ chạy khi push vào nhánh mặc định; job chạy cho PR (kể cả từ fork) không có `packages: write`.
- [ ] Package GHCR của repo public có tự public không: ghi kết quả vào [ci-cd.md](../../../standards/ci-cd.md) (điểm **chưa xác minh**). Nếu không, bật public một lần cho mỗi package và ghi bước đó vào runbook. Một node của cụm `pull` được image thử mà không cần credential.
- [ ] Lệnh kiểm ghim SHA trong bảng bằng chứng của [ci-cd.md](../../../standards/ci-cd.md) trả 0 dòng; `platform` có release đầu tiên, bật immutable releases.
- [ ] Registry HTTP trên `gw` đã tắt; runbook homelab ghi lại.
