# 17: CI vào lab qua Tailscale OIDC

Status: ready-for-human
Blocked by: 01, 02
Repos: platform, docs
Spec: [G0](../spec.md)

## Mô tả

Runner GitHub-hosted vào tailnet bằng `tailscale/github-action` với workload identity federation (OIDC), node ephemeral, tag `tag:ci`. ACL chỉ cho `tag:ci` tới `10.20.0.5:5000`. Ticket này cũng dựng bộ khung reusable workflow trong `platform`: release SemVer bất biến, ghim SHA, `permissions` tối thiểu. Theo mục "Runner", "Quyền và credential", "Reusable workflow" của [ci-cd.md](../../../standards/ci-cd.md).

## Mục tiêu học

- OIDC từ GitHub Actions thay cho secret dài hạn.
- ACL theo tag của Tailscale.

## Tiêu chí nghiệm thu

- [ ] Một workflow thử trong `platform` gọi `curl http://10.20.0.5:5000/v2/` từ runner thành công; gọi `10.20.0.10:6443` thất bại.
- [ ] Không có auth key Tailscale dài hạn trong secret của repo.
- [ ] Node của runner biến khỏi tailnet sau khi job xong.
- [ ] PR từ fork không vào được tailnet.
- [ ] Lệnh kiểm ghim SHA trong bảng bằng chứng của [ci-cd.md](../../../standards/ci-cd.md) trả 0 dòng; `platform` có release đầu tiên, bật immutable releases.
