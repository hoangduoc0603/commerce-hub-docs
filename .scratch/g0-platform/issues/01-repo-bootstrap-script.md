# 01: Script tạo repo và vệ sinh repo public

Status: resolved
Blocked by: None (can start immediately)
Repos: platform, docs, gitops, contracts
Spec: [G0](../spec.md)

## Mô tả

Chủ repo tạo và cấu hình mọi repo của commerce-hub bằng một lệnh, thay cho bấm tay trên GitHub. Script dựa trên `gh` và áp cho repo đã có (`docs`, `platform`, `gitops`, `contracts`), sau đó dùng lại cho mọi repo mới ở G0 và G1. Nội dung theo [ADR-0006](../../../adr/0006-public-repos-on-personal-account.md) và mục "Repo public", "Nhánh và cập nhật phụ thuộc" của [ci-cd.md](../../../standards/ci-cd.md).

## Mục tiêu học

- Vệ sinh repo public: push protection, secret scanning, CodeQL, email noreply.
- Ruleset và branch protection trên tài khoản cá nhân: cái nào bật được, chặn được gì.

## Tiêu chí nghiệm thu

- [x] Chạy script trên một repo mới: repo public, có LICENSE MIT, `.gitignore` chặn kubeconfig, `.env`, auth key Tailscale.
- [x] Nhánh mặc định chỉ chặn force push và xóa; không bắt PR, không bắt status check.
- [x] Secret scanning, push protection, CodeQL default setup đều bật; Dependabot có `github-actions` và ecosystem của repo.
- [x] Không bật "Allow GitHub Actions to create and approve pull requests".
- [x] Ghi kết quả ba điểm **chưa xác minh** vào [ci-cd.md](../../../standards/ci-cd.md): ruleset trên tài khoản cá nhân; policy ghim SHA ở mức owner hay chỉ mức repo; `actions.lock` có trên gói Free không.
- [x] Commit thử bằng email thật bị chặn khi push ("Block command line pushes that expose my email"). _Sửa 2026-11-13: GH007 không chặn email chưa thêm vào tài khoản (xem Lộ trình bước 3). Tiêu chí thay bằng: `repo-audit.sh` FAIL khi history có author/committer không phải noreply._
- [x] Script chạy lại lần hai không đổi gì.

## Lộ trình

Seam kiểm cho cả ticket: `repo-audit.sh` đọc trạng thái repo qua API, in PASS/FAIL theo từng tiêu chí; `repo-bootstrap.sh` làm nó xanh. Script bash + `gh api` + `jq`, đặt trong `platform/scripts/github/`.

- [x] 1. Đăng nhập `gh`; email noreply qua `includeIf "gitdir:"` cho thư mục commerce-hub; bật "Keep my email private" và "Block command line pushes that expose my email". Kiểm: `gh auth status`; `git -C <repo> config --show-origin user.email` ra noreply ở cả 4 repo.
- [x] 2. Viết lại author/committer của `docs` và `platform` sang noreply (chưa push nên an toàn). Kiểm: `git log --format='%ae%n%ce' | sort -u` chỉ còn noreply.
  - 2026-11-13: viết lại trên bản clone bằng `filter-branch --env-filter`, kiểm tree và ngày giữ nguyên, rồi `reset --soft` repo thật sang commit mới (file sửa dở không bị đụng). Sao lưu: `commerce-hub-history-backup-2026-11-13/*.bundle`.
- [x] 3. Repo nháp **private** `ch-sandbox`: commit bằng email thật rồi push. Kiểm: push bị từ chối với `GH007`.
  - Kết quả 2026-11-13: **không** bị chặn. GH007 chỉ xét author của commit mới nhất và chỉ email đã thêm vào tài khoản; email công ty không có trong tài khoản nên đi qua. Repo nháp private đã xóa. Lớp chính chuyển sang `includeIf` (bước 1) + `repo-audit.sh` quét history. Ghi ở `ci-cd.md` mục Repo public.
- [x] 4. Chuyển sandbox sang public, thử ba điểm chưa xác minh (ruleset trên tài khoản cá nhân; policy ghim SHA mức owner hay repo; `actions.lock` trên gói Free), ghi kết quả kèm nguồn và ngày tra vào `ci-cd.md`. Kiểm: `gh api repos/{owner}/ch-sandbox/rulesets`; diff `ci-cd.md`.
  - 2026-11-13: ruleset tạo được trên Free; không có policy ghim SHA cấp owner (404), bật ở cấp repo; `actions.lock` chạy được trên Free (có lockfile xanh, bỏ lockfile đỏ). Ghi ở `ci-cd.md`. Sandbox tạo mới dạng public thay vì đổi repo private cũ (repo cũ có commit lộ email, đã xóa).
- [x] 5. Chốt layout `platform/scripts/github/`, viết `repo-audit.sh` cho các tiêu chí settings (đỏ trước). Kiểm: chạy trên sandbox ra exit ≠ 0 và danh sách FAIL.
- [x] 6. `repo-bootstrap.sh` phần 1: tạo repo public nếu chưa có, secret scanning + push protection, Dependabot alerts, token mặc định read-only, tắt cho Actions tạo/duyệt PR, ghim SHA; đọc → so → ghi. Kiểm: audit xanh các mục này; chạy lần hai in `0 thay đổi`.
- [x] 7. `repo-bootstrap.sh` phần 2: ruleset chặn force push và xóa nhánh (upsert theo tên), CodeQL default setup (xử lý repo không có ngôn ngữ hỗ trợ). Kiểm: audit xanh; `git push --force` vào `main` của sandbox bị từ chối.
  - 2026-11-13: audit xanh trên sandbox; sửa tay ruleset (thêm `pull_request`) và quyền token thì audit FAIL 4 mục, bootstrap sửa 2 thay đổi, audit xanh lại. Chủ repo thử `git push --force` vào `main` của sandbox: bị ruleset từ chối.
- [x] 8. Scaffold: `LICENSE` MIT, khối `.gitignore` chung (kubeconfig, `.env`, auth key Tailscale), `.github/dependabot.yml` theo ecosystem truyền vào; chèn không ghi đè. Kiểm: `git check-ignore -v` với tên file mẫu; chạy lần hai không có diff.
- [x] 9. Áp cho `docs`, `platform`, `gitops`, `contracts`, push lần đầu; xóa sandbox. Kiểm: audit xanh cả 4 repo; chạy lần hai `0 thay đổi`.
  - 2026-11-13: `docs`, `platform`, `gitops`, `contracts` đã public; bootstrap lần hai `0 thay đổi`, audit `Tất cả PASS` cả 4 repo; commit trên GitHub chỉ có email noreply. Sandbox đã xóa.

## Review

`code-review` (high) trên `platform/scripts/github` ra 8 điểm, đã sửa cả 8: chạy lại không truyền `--ecosystems` làm mất ecosystem cũ; audit thoát im lặng khi API lỗi; PUT gửi `allowed_actions: null` khi Actions tắt; không kiểm `origin` trỏ đúng repo; quét history bỏ sót tagger của annotated tag; lỗi API bị coi là "chưa có ruleset"; danh sách ecosystem không bỏ khoảng trắng; tính `ecosystems_json` hai lần.

## Bài học

- Lớp chặn của GitHub hẹp hơn tên gọi. "Block command line pushes that expose my email" chỉ xét commit mới nhất và chỉ email đã thêm vào tài khoản; thử thật thì email công ty đi qua. Lớp chặn thật nằm ở máy (`includeIf`) và ở bước quét history trước lần push đầu.
- Docs nói thiếu thì thử, đừng suy. Trang rulesets chỉ nhắc Team/Enterprise nhưng ruleset chạy trên Free; `actions.lock` không ghi GA nhưng chứng minh được bằng đối chứng (có lockfile xanh, bỏ lockfile đỏ "must be pinned to a full-length commit SHA").
- Idempotent là đọc → so → chỉ ghi khi lệch, không phải gọi PUT lại. So sánh JSON phải chuẩn hóa thứ tự key (`jq -S`), và đếm thay đổi không được chạy trong subshell của pipe.
- Câu chuyện phỏng vấn: "15 repo public trên tài khoản cá nhân, cần vệ sinh đồng nhất. Một script `gh api` idempotent cùng một audit PASS/FAIL. Thử sửa tay ruleset thêm `pull_request` thì audit FAIL 4 mục, bootstrap sửa đúng 2 thay đổi, chạy lại `0 thay đổi`. Trên đường đi phát hiện GH007 không chặn email ngoài tài khoản, phải viết lại history 22 commit trước khi push."

