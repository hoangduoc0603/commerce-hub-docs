---
status: accepted
date: 2026-11-12
---

# ADR-0006: Mọi repo public trên tài khoản GitHub cá nhân, CI vào lab qua Tailscale

Mọi repo của commerce-hub (`docs`, `contracts`, `platform`, `gitops`, các repo trong `services/`, `simulators/`, `frontend/`, `libs/`) đều **public**, nằm dưới tài khoản GitHub cá nhân, gói Free, license MIT. CI chạy trên **GitHub-hosted runner**. Bước nào cần vào lab, ví dụ push image lên `10.20.0.5:5000`, thì đi qua `tailscale/github-action`: xác thực bằng OIDC, node ephemeral, tag `tag:ci`, và ACL chỉ mở tới registry (**sửa 2026-11-15:** image và chart chuyển lên GHCR, CI không vào lab nữa, xem [ADR-0017](0017-images-and-charts-on-ghcr.md)). Nhánh mặc định chỉ được bảo vệ ở mức tối thiểu: chặn force push và xóa nhánh. Không bắt PR, không bắt status check, không có CODEOWNERS. Chi tiết nằm ở ticket [15 Repo public hay private](../.scratch/architecture-g0-g1/issues/15-repo-visibility.md) và [`ci-cd.md`](../standards/ci-cd.md).

## Phương án đã cân nhắc

- **Tất cả private, gói Free.** Bị loại. Ở gói này, repo private không có protected branches/ruleset, CodeQL hay push protection, và GitHub không ghi rõ attestation có dùng được không. CI chỉ có 12 USD/tháng (khoảng 2.000 phút Linux) chia cho khoảng 15 repo, mỗi repo đều chạy Testcontainers. Muốn giữ checklist thì phải trả tiền, trong khi dự án dùng simulator và không có dữ liệu thật để giấu.
- **Trộn: code public, `gitops` private.** Bị loại. `gitops` chỉ chứa IP RFC1918, tên namespace và SealedSecret đã mã hóa, lộ ra thì rủi ro thấp. Để private thì nó lại mất bảo vệ nhánh, mà `gitops` là repo cần bảo vệ nhất.
- **GitHub organization Free.** Bị loại. Thứ org có thêm là giới hạn ai được push và cài App một lần cho cả org, nhưng người làm một mình không cần cả hai. Ruleset cấp org thì chỉ có ở Enterprise, nên dùng org cũng không bớt được việc cấu hình từng repo.
- **Self-hosted runner (ARC) trong cụm.** Bị loại. GitHub khuyên không dùng self-hosted runner cho repo public, vì ai cũng mở PR được và chiếm runner. Thêm nữa, nó cần Docker-in-Docker đặc quyền và ăn vào ngân sách RAM 32 GB ([ADR-0004](0004-single-instance-by-default-on-homelab.md)).
- **Đẩy image lên GHCR rồi cụm kéo về.** Bị loại. Cách này đi ngược quyết định dùng registry nội bộ, bắt cụm ra internet và phải giữ pull secret. **Đã đảo ngược 2026-11-15 bởi [ADR-0017](0017-images-and-charts-on-ghcr.md):** cụm vốn đã kéo image từ internet, và package public không cần pull secret.
- **Bảo vệ nhánh đầy đủ theo checklist.** Bị loại khi còn một người làm. Bắt PR thì không có ai duyệt thật, và bot `update-gitops` cần bypass list theo đường dẫn mà chưa xác minh được ruleset có hỗ trợ.

## Hệ quả

- CI không tốn tiền. CodeQL, secret scanning và push protection miễn phí. Attestation đi qua Sigstore Public Good Instance. Reusable workflow trong `platform` gọi được từ mọi repo mà không cần Access policy.
- Mọi thứ commit lên đều công khai vĩnh viễn, kể cả history. Vì vậy phải commit bằng email noreply, secret chỉ ở dạng SealedSecret, kubeconfig, auth key Tailscale và `.env` nằm trong `.gitignore`. Workflow chạy cho PR từ fork không nhận secret và không vào tailnet.
- CI chạy *sau* khi code đã vào nhánh mặc định, nên lỗi chỉ được phát hiện chứ không bị chặn trước. Check Branch-Protection và Code-Review của OpenSSF Scorecard sẽ cho điểm thấp.
- ~~Push image đi qua tailnet.~~ Không còn đúng từ 2026-11-15 (ADR-0017).
- Khi có người thứ hai, hoặc khi chuyển một repo sang private, phải xem lại ADR này: bật lại checklist nhánh đầy đủ, CODEOWNERS, và Access policy cho `platform`.
- Chưa xác minh, sẽ bật thử ở G0: tài khoản cá nhân bật được ruleset cho repo public hay phải dùng branch protection rule; policy bắt ghim SHA có ở cấp tài khoản hay chỉ ở từng repo. Đã thử ở ticket G0-01 (2026-11-13): ruleset bật được; policy ghim SHA chỉ có ở từng repo. Kết quả ghi ở [`ci-cd.md`](../standards/ci-cd.md).

## Đặt tên repo (bổ sung 2026-11-13)

Mọi repo trên GitHub có prefix `commerce-hub-` (`commerce-hub-docs`, `commerce-hub-platform`, `commerce-hub-hello`…), để không lẫn với dự án khác trên cùng tài khoản cá nhân. Thư mục local giữ tên ngắn (`platform/`, `services/hello/`); `repo-bootstrap.sh` tự thêm prefix. Phương án tạo organization Free riêng được cân nhắc lại và vẫn bị loại. Org cho không gian tên riêng, policy Actions cấp owner (không phải bật từng repo) và cài GitHub App một lần. Nhưng script đã bật policy cho từng repo, nên những lợi ích này không đáng thêm một tài khoản phải quản lý. Đổi lại, tên tham chiếu dài hơn, ví dụ `uses: <owner>/commerce-hub-platform/.github/workflows/…`.
