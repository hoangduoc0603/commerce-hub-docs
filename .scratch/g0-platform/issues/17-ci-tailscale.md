# 17: Khung reusable workflow, build và push lên GHCR

Status: resolved
Blocked by: 01
Repos: platform, docs
Spec: [G0](../spec.md)

## Mô tả

Dựng bộ khung reusable workflow trong `platform`: release SemVer bất biến, ghim SHA, `permissions` tối thiểu. Kèm một reusable workflow build và push lên GHCR (`ghcr.io`) bằng `GITHUB_TOKEN` (`packages: write`), dùng lại ở ticket 21 (chart) và 23 (image). _(Sửa 2026-11-16, review: ticket 23 gọi lồng `container-image.yml` sau khi thêm input ở bước 9 của nó; ticket 21 cần `helm push` nên viết workflow `chart` riêng, chỉ dùng lại khung: quyền theo job, login GHCR bằng `GITHUB_TOKEN`, ghim SHA, phát hành bất biến.)_ CI không vào lab: Argo CD và kubelet kéo artifact từ GHCR. Registry HTTP `10.20.0.5:5000` trên `gw` tắt. Theo [ADR-0017](../../../adr/0017-images-and-charts-on-ghcr.md) và mục "Quyền và credential", "Reusable workflow" của [ci-cd.md](../../../standards/ci-cd.md).

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

- [x] Một workflow thử trong `platform` gọi reusable workflow, build một image thử và push lên `ghcr.io` bằng `GITHUB_TOKEN`; repo không có secret registry nào.
- [x] Job push chỉ chạy khi push vào nhánh mặc định; job chạy cho PR (kể cả từ fork) không có `packages: write`. _(Thử bằng PR từ nhánh cùng repo, điều kiện khó hơn; không thử được PR từ fork thật vì chỉ có một tài khoản.)_
- [x] Package GHCR của repo public có tự public không: ghi kết quả vào [ci-cd.md](../../../standards/ci-cd.md) (điểm **chưa xác minh**). Nếu không, bật public một lần cho mỗi package và ghi bước đó vào runbook. Một node của cụm `pull` được image thử mà không cần credential.
- [x] Lệnh kiểm ghim SHA trong bảng bằng chứng của [ci-cd.md](../../../standards/ci-cd.md) trả 0 dòng; `platform` có release đầu tiên, bật immutable releases.
- [x] Registry HTTP trên `gw` đã tắt; runbook homelab ghi lại.

## Lộ trình

Chốt 2026-11-16. Q1: `container-image.yml` dùng chung cho mọi Dockerfile, `java-service.yml` (ticket 23) gọi lồng nó. Q2: chưa dùng `actions.lock`; mọi action đang dùng là action Node không kéo action khác, nên ghim SHA đã phủ hết; ghi lý do vào ci-cd.md. Q3: thêm ruleset khóa tag `v*` cho `platform` bằng `repo-bootstrap.sh --release-tags`.

- [x] 1. `container-image.yml` (`workflow_call`; input `image`, `context`; job `build` cho mọi sự kiện trừ push vào nhánh mặc định, `contents: read`; job `publish` chỉ cho push vào nhánh mặc định, `packages: write`; output `digest`), `ghcr-smoke.yml` và Dockerfile thử `FROM scratch`. Kiểm: `actionlint` sạch; lệnh grep ghim SHA của ci-cd.md trả 0 dòng.
- [x] 2. PR từ một nhánh trong repo. Kiểm: `build` xanh, `publish` skipped; "Set up job" mục GITHUB_TOKEN Permissions chỉ có `Contents: read`, `Metadata: read`. Không thử được PR từ fork thật (một tài khoản); PR cùng repo là điều kiện khó hơn.
- [x] 3. Merge vào `main`. Kiểm: `publish` xanh; digest trong output khớp `docker buildx imagetools inspect ghcr.io/hoangduoc0603/commerce-hub-platform-smoke:<sha>`; `gh secret list` rỗng.
- [x] 4. Visibility: `docker logout ghcr.io` rồi pull; nếu private thì bật public (Package settings → Change visibility), ghi bước vào README `platform`; kiểm package nối với repo `platform`. Kiểm: `crictl pull …@<digest>` trên `k8s-w1` không credential; kết quả ghi vào ci-cd.md.
- [x] 5. Bật immutable releases, `repo-bootstrap.sh platform --release-tags`, release `v0.1.0`; README `platform` ghi quyền bên gọi phải cấp và cách ghim. Kiểm: `gh api repos/…/immutable-releases` trả `enabled: true`; release `v0.1.0` immutable.
- [x] 6. Tắt registry trên `gw`, gỡ `/etc/containerd/certs.d/10.20.0.5:5000` trên 3 node, sửa runbook mục 6, 7.1, 9. Kiểm: `curl http://10.20.0.5:5000/v2/` bị từ chối; không pod nào dùng image `10.20.0.5`.
- [x] 7. Kết ticket: checklist ci-cd.md, tiêu chí nghiệm thu, traceability, `## Bài học`.

## Kết quả

### Bước 1–2 (2026-11-16)

Commit `4895259` trên nhánh `g0-17-container-image` của `platform`, [PR #1](https://github.com/hoangduoc0603/commerce-hub-platform/pull/1).

| Số đo | Kết quả |
|---|---|
| `actionlint` 1.7.12 (kèm shellcheck 0.11.0) | Sạch, exit 0 |
| Lệnh grep ghim SHA của ci-cd.md | 0 dòng |
| `repo-audit.sh platform --local .` | Tất cả PASS |
| Run `43903185743` (`pull_request`) | `image / build` success (26 s), `image / publish` skipped |
| "Set up job" của `image / build`, nhóm GITHUB_TOKEN Permissions | `Contents: read`, `Metadata: read`; không có `Packages` dù bên gọi cấp `packages: write` |
| CodeQL default setup | Từ nay quét cả workflow (`Analyze (actions)`), 0 alert mở trên PR |

Log build có cảnh báo "No output specified with docker-container driver": đúng ý đồ, job `build` chỉ kiểm build được, không giữ image.

### Bước 3 (2026-11-16)

Fast-forward `main` của `platform` lên `4895259` (giữ đúng SHA đã chạy ở PR; PR #1 tự thành Merged). Run `43904657336` (`push`).

| Số đo | Kết quả |
|---|---|
| Job | `image / publish` success, `image / build` skipped |
| "Set up job" của `image / publish` | `Contents: read`, `Metadata: read`, `Packages: write` (đối chứng của bước 2) |
| Log `docker/login-action` | `Login Succeeded!` lúc đầu, `Removing login credentials for ghcr.io` ở post job |
| Digest trong log BuildKit (`pushing manifest`) | `sha256:288dd03b529ea57e63f6cf1679f04ac37b6ca96b98c1dd948a8e8dcef3b126c5` |
| `docker buildx imagetools inspect ghcr.io/hoangduoc0603/commerce-hub-platform-smoke:4895259…` từ Mac chưa đăng nhập ghcr.io | `MediaType: application/vnd.oci.image.manifest.v1+json` (một manifest, không index), digest trùng dòng trên |
| `curl` lấy token ẩn danh từ `https://ghcr.io/token?scope=repository:…:pull` rồi GET manifest | `HTTP/2 200`, `docker-content-digest` trùng |
| `gh secret list`, `gh secret list --app dependabot`, `gh variable list` | Cả ba rỗng |

Kết quả sớm cho bước 4: package mới **tự public** và **tự nối với repo `platform`** (trang `github.com/users/…/packages/container/package/…` chuyển hướng sang `github.com/hoangduoc0603/commerce-hub-platform/pkgs/container/commerce-hub-platform-smoke`, nhãn Public). Khớp câu của trang "Publishing and installing a package with GitHub Actions" ("inherits the visibility and permissions model of the repository"), trái với câu "but not the visibility" của trang access control. Còn lại cho bước 4: pull từ node của cụm và ghi vào ci-cd.md.

### Bước 4 (2026-11-16)

| Số đo | Kết quả |
|---|---|
| `k8s-w1`: `/etc/containerd/certs.d/`, grep `ghcr\|auths\|credential` trong `config.toml`, credential provider trong `/etc/kubernetes/` | Chỉ có `10.20.0.5:5000`; không cấu hình nào cho ghcr.io |
| `k8s-w1`: `crictl pull ghcr.io/hoangduoc0603/commerce-hub-platform-smoke@sha256:288dd03b…` (trước đó chưa có image) | `Image is up to date for sha256:bf27bae4…` (image ID, tức digest của config) |
| `k8s-w1`: `crictl inspecti … \| grep -A2 repoDigests` | `…@sha256:288dd03b…`, trùng manifest digest CI ghi |
| Pod `ghcr-smoke` trên `k8s-w2`, không `imagePullSecrets` (SA `default` cũng không có) | Event `Pulled`: "Successfully pulled image … in 6.728s … Image size: 1149 bytes"; sau đó `CreateContainerError` "no command specified", đúng dự đoán với image `FROM scratch` |
| Dọn | Xóa pod; `crictl rmi` trên `k8s-w1`, `k8s-w2`; còn 0 image thử |

Ghi kết quả: ci-cd.md mục "Image, SBOM, provenance" (đã xác minh, kèm chỗ hai trang docs mâu thuẫn), ADR-0017 mục Hệ quả (chart kiểm lại ở G0-21), spec G0 danh sách điểm chưa xác minh. Không cần bước bật public bằng tay, nên runbook không thêm gì.

### Bước 5 (2026-11-16)

| Số đo | Kết quả |
|---|---|
| README `platform` (commit `84bd94d`) | Mục Reusable workflow: bảng workflow, mẫu bên gọi kèm quyền phải cấp, output, cách phát hành SemVer |
| `gh api -X PUT repos/…/immutable-releases` | `HTTP/2.0 204`; `GET` trả `{"enabled":true,"enforced_by_owner":false}` |
| `repo-bootstrap.sh platform --release-tags --dry-run` | Chỉ một thay đổi: tạo ruleset `release-tags-immutable` |
| `repo-bootstrap.sh platform --release-tags`, rồi `repo-audit.sh platform --release-tags` | 1 thay đổi; audit tất cả PASS, có 5 dòng PASS cho ruleset tag (áp `refs/tags/v*`, cấm dời và xóa, không ai bypass) |
| `gh release create v0.1.0 --target main` | [Release v0.1.0](https://github.com/hoangduoc0603/commerce-hub-platform/releases/tag/v0.1.0); `immutable: true`, `draft: false` |
| SHA của `v0.1.0` | `84bd94d3139e967b4120fbbe3ea6deef3fc0b8f8`; README ghim SHA này ở commit `73d5e6e` (sau release, vì commit không chứa được SHA của chính nó) |
| Dời tag: `git push --force origin 4895259…:refs/tags/v0.1.0` (chủ repo chạy) | `! [remote rejected] … (push declined due to repository rule violations)`, `GH013 … Cannot update this protected ref`: ruleset `release-tags-immutable` chặn trước |
| Xóa tag: `git push origin :refs/tags/v0.1.0` (chủ repo chạy) | `! [remote rejected] v0.1.0 (push declined due to repository rule violations)`, `GH013 … Cannot delete this tag`. Sau hai lần thử, `v0.1.0` vẫn trỏ `84bd94d…`, release vẫn `immutable: true` |

### Bước 6 (2026-11-16)

| Số đo | Kết quả |
|---|---|
| Ai còn dùng `10.20.0.5:5000` | 0/43 pod, 0 workload template; image trên 3 node: 0. Chỉ còn template ApplicationSet `services` (`repoURL: 10.20.0.5:5000/charts`), chưa sinh app nào; đổi ở G0-21/24 |
| Nội dung registry trước khi tắt | Chỉ repo `alpine` không còn tag, 92 KB |
| `ssh gw 'sudo systemctl disable --now docker-registry'` | `inactive`, `disabled`; `ss -ltn` không còn `:5000`; RAM `gw`: 288 → 304 MiB used (khác biệt nằm trong nhiễu) |
| `curl http://10.20.0.5:5000/v2/` từ Mac | Exit 7 (không kết nối được) |
| Gỡ `/etc/containerd/certs.d/10.20.0.5:5000` trên 3 node | Chủ repo chạy (lệnh `rm` qua ssh bị chặn quyền trong session của Claude): `k8s-cp`, `k8s-w1`, `k8s-w2` đều còn 0 entry trong `certs.d`. Sau đó `crictl pull` image thử trên `k8s-cp` vẫn được |
| Runbook `homelab-hyperv.md` (commit `2502139` của `platform`) | Mục 0 (sơ đồ, bảng lý do, bảng RAM), mục 6 viết lại "Image ở GHCR" kèm lệnh tắt registry cũ, script 7.1 bỏ `hosts.toml`, 8.9, mục 9 đổi sang CI → GHCR → cụm, 10.1, bảng xử lý sự cố |

Gói `docker-registry` và `/var/lib/docker-registry` vẫn còn trên `gw` (chỉ tắt, chưa gỡ). Docker Desktop trên Mac có thể còn `insecure-registries: ["10.20.0.5:5000"]`: vô hại, chủ repo tự gỡ trong Settings → Docker Engine nếu muốn.

### Bước 7 (2026-11-16)

- Review hai trục (`c9bbafb...2502139` của `platform`). Standards: không có vi phạm về quyền, ghim SHA, injection; một lệch chuẩn gần cứng là chưa kiểm tag tồn tại trước khi push (ci-cd.md, "Lệch chuẩn có chủ đích") cùng các smell `id: ref` dễ nhầm với `github.ref` và hai job lặp bước. Spec: đủ 5 tiêu chí; `container-image.yml` chưa dùng nguyên được cho G0-23 (jar, `build-args`, cache, Trivy trước push) và G0-21 (cần `helm push`).
- Chốt với chủ repo: sửa nhỏ ở đây, phần lớn sang G0-23. Commit `c4b5d70` thêm bước "Kiểm tag chưa tồn tại", đổi `id: ref` thành `id: name`, comment giữ hai job đồng bộ; release `v0.1.1` (immutable). README ghim `v0.1.1` ở `5f2654c`. Re-run job `publish` của run `43911676204` fail đúng ý, tag vẫn trỏ `sha256:78d22a08…`.
- Việc chuyển sang G0-23 ghi ở bước 9 của [ticket 23](23-hello-image.md); Mô tả của ticket này sửa câu về G0-21.
- `ci-cd.md`: tick mục immutable releases; ghi lý do chưa dùng `actions.lock` (Q2). Các mục khác của checklist áp cho mọi repo và mọi workflow, giữ chưa tick tới khi repo service đầu tiên dùng.
- Bằng chứng: [bản ghi G0, mục 9](../../../experiments/2026-11-g0.md#9-reusable-workflow-container-image-ghcr-bằng-github_token-quyền-theo-job-release-bất-biến).
- `platform`: `4895259` (workflow, image thử), `84bd94d` (README, `v0.1.0`), `73d5e6e` (README ghim `v0.1.0`; thiếu dòng `Co-Authored-By`, ruleset chặn force push nên để nguyên), `2502139` (runbook), `c4b5d70` (review, `v0.1.1`), `5f2654c` (README ghim `v0.1.1`).
- `docs`: chưa commit (xem đề xuất commit).
- Ma trận truy vết: không có dòng tương ứng (ticket hạ tầng, như G0-03..08).
- Chuyển cho ticket sau:
  - G0-23 bước 9: gọi `container-image.yml@c4b5d70…` (v0.1.1) hoặc bản `v0.2.0` sau khi thêm input; bên gọi cấp `contents: read`, `packages: write`.
  - G0-21: workflow `chart` riêng, cùng khung; kiểm lại package chart tự public và nối repo `platform` (ADR-0017).
  - G0-21/24: đổi `repoURL: 10.20.0.5:5000/charts` trong ApplicationSet `services` của `gitops` sang GHCR.
  - Còn trên `gw`: gói `docker-registry` và `/var/lib/docker-registry` (đã tắt, chưa gỡ).

## Bài học

- Quyền của `GITHUB_TOKEN` đọc thẳng được trong log "Set up job"; đặt log của PR cạnh log của push vào `main` là bằng chứng đủ cho "PR không có quyền ghi", không phải suy từ YAML. Muốn quyền khác nhau theo sự kiện thì phải là hai job, vì `permissions` không có điều kiện.
- Hai trang docs của GitHub nói ngược nhau về visibility của package; chỉ thử thật mới chốt được (tự public khi tạo từ workflow của repo public).
- Chỗ vấp: viết workflow dùng chung trước khi có bên gọi thật nên thiếu những gì `hello` cần (jar, `build-args`, cache, Trivy trước push); review theo spec của ticket kế tiếp mới lộ ra. Và build `FROM scratch` cùng nội dung vẫn ra hai digest khác nhau, nên tag theo SHA cần lớp chặn ghi đè.
- Câu chuyện kể được: "Tôi dựng reusable workflow build image cho mọi repo, push lên GHCR chỉ bằng token ngắn hạn của job, không secret nào. Log chứng minh job chạy cho PR chỉ có quyền đọc, còn job push mới có `packages: write`. Workflow phát hành bằng release bất biến và bên gọi ghim SHA; thử dời hay xóa tag đều bị GitHub từ chối (GH013). Re-run không đẩy đè được image, vì cùng nội dung mà hai lần build cho hai digest khác nhau."
