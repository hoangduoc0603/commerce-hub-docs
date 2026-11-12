# 15 Repo public hay private

Type: grilling
Status: resolved
Blocked by:
Map: [Kiến trúc G0–G1](../map.md)

## Question

Các repo của commerce-hub khi đưa lên GitHub sẽ public hay private? Câu trả lời đổi lựa chọn runner, attestation, ruleset/branch protection và gói GitHub cần dùng (xem phần mâu thuẫn nguồn trong [ci-cd.md](../../../standards/ci-cd.md)).

## Answer

Chốt ngày 2026-11-12, qua grilling. Ghi lại ở [ADR-0006](../../../adr/0006-public-repos-on-personal-account.md).

- **Visibility:** mọi repo đều public.
- **Chủ sở hữu:** tài khoản GitHub cá nhân, gói Free, không lập organization.
- **Runner:** dùng GitHub-hosted runner, đi vào lab qua `tailscale/github-action` (OIDC, ephemeral, `tag:ci`, ACL hẹp). Đây là đề xuất ticket 01 chuyển sang. Repo public thì không được dùng self-hosted runner, nên chỉ còn lựa chọn này.
- **Bảo vệ nhánh:** ở mức tối thiểu. Chỉ chặn force push và xóa nhánh mặc định, không bắt PR, không bắt status check, không có CODEOWNERS. Bot `update-gitops` push thẳng, nên không cần bypass list. Đây là lệch chuẩn có chủ đích, đã ghi trong [`ci-cd.md`](../../../standards/ci-cd.md).
- **License:** MIT cho mọi repo.
- **Vệ sinh repo public:** commit bằng email noreply. Secret chỉ ở dạng SealedSecret. Kubeconfig, auth key Tailscale và `.env` nằm trong `.gitignore`. Bật secret scanning, push protection và CodeQL. Workflow chạy cho PR từ fork không nhận secret và không vào tailnet.

Docs GitHub, tra ngày 2026-11-12, dùng làm căn cứ:
- Runner chuẩn miễn phí cho repo public ([billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)).
- Repo private trên gói Free có 12 USD compute mỗi tháng và không có protected branches ([plans](https://docs.github.com/en/get-started/learning-about-github/githubs-plans)).
- Repo private muốn có CodeQL và push protection thì phải dùng gói Team trở lên kèm sản phẩm trả phí ([GHAS](https://docs.github.com/en/get-started/learning-about-github/about-github-advanced-security)).
- Ruleset cấp org chỉ có ở Enterprise ([rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)).

**Chưa xác minh**, sẽ bật thử trên repo đầu tiên ở G0:
- Tài khoản cá nhân bật được ruleset cho repo public hay phải dùng branch protection rule.
- Policy bắt ghim SHA có ở cấp tài khoản không.
- `push-to-registry` và `gh attestation verify oci://` có chạy được với registry HTTP 2.8 không.
