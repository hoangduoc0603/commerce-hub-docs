# Chuẩn: CI/CD với GitHub Actions

- Ngày tra: 2026-11-12
- Phiên bản áp dụng: GitHub Actions (SaaS, docs tra ngày trên), Gradle 9.9.1 + `gradle/actions/setup-gradle@v6`, Java 25, Spring Boot 4.1.2, Testcontainers 2.0.5 (do Spring Boot quản lý), `actions/attest@v4`, `actions/create-github-app-token@v3`, `tailscale/github-action@v4`, SLSA v1.2. Trivy và Dockerfile theo [`container-image.md`](container-image.md).
- Phạm vi: reusable workflow trong `platform/.github/workflows/`, workflow gọi nó trong mọi repo service/simulator/frontend/lib, CI của `contracts` và `gitops`, cấu hình Dependabot, ruleset nhánh, runner.

## Checklist

### Reusable workflow cho polyrepo
- [ ] `platform/.github/workflows/` có workflow `on: workflow_call` theo loại repo: `java-service.yml`, `node-app.yml`, `contracts.yml`, `update-gitops.yml`; input có kiểu và mô tả. Repo service chỉ có workflow mỏng gọi chúng. [Reuse workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations)
- [ ] Repo gọi tham chiếu `uses: <owner>/platform/.github/workflows/java-service.yml@<SHA đầy đủ>`, có comment tên release. Re-run dùng lại đúng SHA của lần chạy đầu; tag thì dời được. [Reuse workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations), [Secure use – pin](https://docs.github.com/en/actions/reference/security/secure-use)
- [ ] `platform` phát hành bằng release có tag SemVer và bật **immutable releases**: tag khóa vào commit, không xóa hay dùng lại tên được. [Immutable releases](https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/immutable-releases)
- [ ] Nếu `platform` là private: bật Access policy cho phép repo khác gọi workflow. Không bật thì repo gọi không thấy workflow. [Reuse workflows – access](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations)
- [ ] Truyền secret tường minh (`secrets: { NAME: ... }`), không dùng `secrets: inherit`. Workflow chung chỉ nhận secret nó cần. `env` cấp workflow của bên gọi **không** truyền sang, dùng `inputs`. [Reuse workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations)

### Chuỗi cung ứng của chính CI
- [ ] Mọi `uses:` action bên thứ ba ghim SHA 40 ký tự (kèm comment version), SHA lấy từ repo gốc, không từ fork. Tháng 3/2026 kẻ tấn công dời 76/77 tag của `aquasecurity/trivy-action` sang commit độc hại; ai ghim SHA cũ thì không bị. [Secure use](https://docs.github.com/en/actions/reference/security/secure-use), [GHSA-69fq-xp46-6x23](https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23)
- [ ] Bật policy "Require actions to be pinned to a full-length commit SHA" và allowlist action ở cấp owner. Chặn từ gốc thay vì dựa vào review. [Workflow dependency lockfiles](https://docs.github.com/en/actions/concepts/security/workflow-dependency-lockfiles)
- [ ] Khi dùng được, khóa phụ thuộc workflow bằng `.github/workflows/actions.lock` (`gh actions-lock`); docs gọi đây là biện pháp mạnh nhất, thay cho ghim SHA và phủ cả phụ thuộc bắc cầu. **Chưa xác minh**: tính năng đã GA chưa và có trên gói Free không. [Workflow dependency lockfiles](https://docs.github.com/en/actions/concepts/security/workflow-dependency-lockfiles)
- [ ] `CODEOWNERS` có `/.github/workflows/` ở mọi repo; đổi workflow phải có người duyệt. [Secure use – CODEOWNERS](https://docs.github.com/en/actions/reference/security/secure-use)

### Quyền và credential
- [ ] Mặc định `GITHUB_TOKEN` của repo/owner là read-only; mỗi workflow khai `permissions: { contents: read }` ở đầu, job cần thêm thì nâng riêng job đó. Khai một scope thì các scope còn lại thành `none`. [Workflow syntax – permissions](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions), [Secure use](https://docs.github.com/en/actions/reference/security/secure-use)
- [ ] Workflow được gọi không xin quyền rộng hơn bên gọi (chỉ hạ được, không nâng được). Mỗi reusable workflow ghi trong README quyền tối thiểu bên gọi phải cấp. [Reuse workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations)
- [ ] Không chèn `${{ github.event.* }}` (tiêu đề PR, tên nhánh…) thẳng vào `run:`; gán qua `env:` rồi dùng biến shell. Chặn script injection. [Secure use – script injection](https://docs.github.com/en/actions/reference/security/secure-use)
- [ ] Không dùng `pull_request_target`; không checkout code từ fork trong workflow có secret. [Secure use](https://docs.github.com/en/actions/reference/security/secure-use)
- [ ] Dùng OIDC (`id-token: write`) thay secret dài hạn ở mọi chỗ bên kia hỗ trợ: Tailscale (workload identity federation) và attestation. Token OIDC sống trong một job. [OpenID Connect](https://docs.github.com/en/actions/concepts/security/openid-connect), [Tailscale GitHub Action](https://tailscale.com/kb/1276/tailscale-github-action)
- [ ] Ghi vào repo `gitops` bằng **GitHub App** chỉ cài trên `gitops` (quyền `contents: write`), token sinh mỗi lần chạy bằng `actions/create-github-app-token`. Không dùng PAT. `GITHUB_TOKEN` chỉ có quyền trên repo chứa workflow. [GitHub App trong workflow](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/making-authenticated-api-requests-with-a-github-app-in-a-github-actions-workflow), [GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token)

### Build, cache, test
- [ ] Java: `actions/setup-java` (Temurin 25) + `gradle/actions/setup-gradle@v6`; cache chỉ ghi trên push vào nhánh mặc định, nhánh khác `cache-read-only: true`. Setup-gradle cũng kiểm `gradle-wrapper.jar`. [Gradle – GitHub Actions](https://docs.gradle.org/current/userguide/github-actions.html)
- [ ] Không cache thư mục có credential (`~/.docker/config.json`, `~/.gradle/gradle.properties` có token). Cache dùng chung theo nhánh, giới hạn 10 GB/repo, entry quá 7 ngày không dùng bị xóa. [Dependency caching reference](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching)
- [ ] `./gradlew check` chạy unit test và integration test Testcontainers (PostgreSQL, Kafka) trên runner có Docker; image container ghim cùng major/minor với production. [Spring Boot – Testcontainers](https://docs.spring.io/spring-boot/reference/testing/testcontainers.html)
- [ ] Báo cáo test (JUnit XML) upload làm artifact khi job lỗi; mỗi job có `timeout-minutes` (mặc định của GitHub là 360 phút, quá dài). **Chưa xác minh**: con số 360 chưa đọc được trực tiếp trong lần tra này. [Workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)
- [ ] Repo Java bật `gradle/actions/dependency-submission@v6` trên nhánh mặc định để Dependabot alerts thấy phụ thuộc Gradle (job cần `contents: write`). [Gradle – GitHub Actions](https://docs.gradle.org/current/userguide/github-actions.html)

### Contract và thư viện
- [ ] `contracts` CI: lint → kiểm tương thích `BACKWARD` với Schema Registry → sinh code → publish Maven/npm **chỉ từ tag** `vX.Y.Z`. Đổi phá vỡ phải tăng MAJOR. [SemVer 2.0.0](https://semver.org/spec/v2.0.0.html) (chi tiết Schema Registry ở [`kafka.md`](kafka.md))
- [ ] Version đã publish không bao giờ ghi đè; sửa thì ra bản mới. SemVer: nội dung một version đã phát hành không được sửa. [SemVer 2.0.0 – mục 3](https://semver.org/spec/v2.0.0.html)

### Image, SBOM, provenance
- [ ] Build image **một lần** trên runner amd64, tag = git SHA đầy đủ, ghi lại digest; không `latest`. Môi trường sau dùng lại đúng digest, không build lại. [Kubernetes – Images](https://kubernetes.io/docs/concepts/containers/images/) (Dockerfile, SBOM BuildKit, Trivy chặn HIGH/CRITICAL có bản vá: [`container-image.md`](container-image.md))
- [ ] Đẩy lên registry lab qua BuildKit với `[registry."10.20.0.5:5000"] http = true`; không bật đồng thời `insecure`. Docs BuildKit ghi rõ không bật hai cờ cùng nhau. [BuildKit – buildkitd.toml](https://docs.docker.com/build/buildkit/toml-configuration/)
- [ ] Image build từ nhánh mặc định có attestation provenance (`actions/attest`, quyền `id-token: write`, `attestations: write`, `contents: read`; `subject-name` không kèm tag, `subject-digest` = digest). Attestation đạt SLSA Build L2; build trong reusable workflow dùng chung có thể đạt L3. [Artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations), [Use artifact attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations), [SLSA v1.2 – Build levels](https://slsa.dev/spec/v1.2/build-track-basics)
- [ ] Attestation được **kiểm**: `gh attestation verify oci://<image>@<digest> -R <owner>/<repo>` chạy trong job deploy trước khi sửa `gitops`. Không kiểm thì attestation không có tác dụng. [Artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations)

### Deploy qua GitOps
- [ ] Job `update-gitops` chỉ chạy trên push vào nhánh mặc định sau khi build, scan, verify xanh; sửa `envs/<env>/<svc>/values.yaml` (`image.digest`, `image.tag`), commit message có tên service, SHA nguồn và link run. Không gọi `kubectl`/`argocd`. Quy ước của [`gitops-argocd.md`](gitops-argocd.md).
- [ ] `concurrency: { group: gitops-<env>, cancel-in-progress: false }` cho job này, kèm vòng `git pull --rebase` + thử lại khi push bị từ chối. Nhiều service đẩy cùng lúc vào một repo. [Workflow syntax – concurrency](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#concurrency)
- [ ] Workflow PR dùng `concurrency: { group: ${{ github.workflow }}-${{ github.ref }}, cancel-in-progress: true }` để hủy lần chạy cũ khi push mới. [Workflow syntax – concurrency](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#concurrency)

### Nhánh và cập nhật phụ thuộc
- [ ] Ruleset/branch protection cho nhánh mặc định của mọi repo: bắt PR, bắt status check của CI, chặn force push và xóa nhánh, linear history; `gitops` bắt thêm review của CODEOWNERS cho `apps/`. [About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches), [About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
- [ ] Bot `update-gitops` (GitHub App) nằm trong bypass list của ruleset `gitops`, chỉ cho đường `envs/**`. **Chưa xác minh**: ruleset có giới hạn bypass theo đường dẫn được không; nếu không, App mở PR và auto-merge.
- [ ] Không bật "Allow GitHub Actions to create and approve pull requests". [Secure use](https://docs.github.com/en/actions/reference/security/secure-use)
- [ ] `.github/dependabot.yml` ở mọi repo với ecosystem `github-actions` (directory `/`), `gradle` hoặc `npm`, `docker`; `gitops` thêm `helm`. Dùng `groups` gộp bản minor/patch, giữ cooldown mặc định 3 ngày (không áp cho security update). [Dependabot options](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference)
- [ ] Biết giới hạn: Dependabot **không** tạo alert bảo mật cho action ghim SHA, chỉ có version update. [Secure use – Dependabot](https://docs.github.com/en/actions/reference/security/secure-use)

### Runner
- [ ] Repo public **không** dùng self-hosted runner. Bất kỳ ai cũng mở PR được và chiếm runner. [Secure use – self-hosted runners](https://docs.github.com/en/actions/reference/security/secure-use)
- [ ] Mặc định chạy trên GitHub-hosted runner (VM mới cho mỗi job). Bước cần vào lab (push image) dùng `tailscale/github-action` với workload identity federation, tag `tag:ci`, node ephemeral; ACL Tailscale chỉ cho `tag:ci` tới `10.20.0.5:5000`. [Tailscale GitHub Action](https://tailscale.com/kb/1276/tailscale-github-action), [Tailscale ACL](https://tailscale.com/kb/1018/acls)
- [ ] Nếu sau này thêm self-hosted runner trong lab: chỉ cho repo private, dùng Actions Runner Controller với runner ephemeral (JIT), runner group riêng, namespace riêng, không gắn credential cụm. [Actions Runner Controller](https://docs.github.com/en/actions/concepts/runners/actions-runner-controller), [Secure use](https://docs.github.com/en/actions/reference/security/secure-use)

## Lựa chọn và phương án đã loại

| Quyết định | Chọn | Loại | Lý do | Nguồn |
|---|---|---|---|---|
| Runner và đường vào registry lab (**nên viết ADR**) | GitHub-hosted runner + Tailscale action (OIDC, ephemeral, ACL hẹp) | (b) Self-hosted ARC trong cụm; (c) đẩy GHCR rồi cụm kéo từ GHCR | (b) docs cấm cho repo public; Testcontainers/build image cần Docker-in-Docker đặc quyền; ăn RAM của cụm 32 GB. (c) đi ngược quyết định registry nội bộ, cụm phải ra internet và giữ pull secret. Chọn GitHub-hosted thì mỗi job là VM sạch, amd64 native; giá phải trả là push image đi qua tailnet (có thể chậm nếu phải đi relay) | [Secure use](https://docs.github.com/en/actions/reference/security/secure-use), [ARC](https://docs.github.com/en/actions/concepts/runners/actions-runner-controller), [Tailscale GitHub Action](https://tailscale.com/kb/1276/tailscale-github-action) |
| Credential ghi `gitops` | GitHub App token ngắn hạn | PAT; deploy key SSH | PAT gắn người và sống lâu; deploy key không giới hạn được theo job | [GitHub App trong workflow](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/making-authenticated-api-requests-with-a-github-app-in-a-github-actions-workflow) |
| Ghim action | SHA đầy đủ (+ lockfile khi có) | Tag `@vN` | Tag dời được, đã bị khai thác thật năm 2026 | [Secure use](https://docs.github.com/en/actions/reference/security/secure-use), [GHSA-69fq-xp46-6x23](https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23) |
| Cập nhật phụ thuộc | Dependabot | Renovate | Có sẵn trong GitHub, không phải cài App hay chạy thêm gì; hỗ trợ đủ ecosystem cần. Đổi sang Renovate nếu cần preset dùng chung cho nhiều repo | [Dependabot options](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference), [Renovate](https://docs.renovatebot.com/) |
| Tag image | git SHA + digest | SemVer cho image service | Service deploy liên tục, SHA truy ngược commit; SemVer dành cho lib/contract/chart | [Kubernetes – Images](https://kubernetes.io/docs/concepts/containers/images/), [SemVer](https://semver.org/spec/v2.0.0.html) |

## Lệch chuẩn có chủ đích ở home lab
- **Registry không auth, không TLS.** CI không cần credential registry; ai vào được tailnet với tag `tag:ci` là đẩy được image. Bù bằng ACL Tailscale hẹp và gitops chỉ nhận digest do CI ghi. Docker-registry 2.8 không chặn ghi đè tag, nên CI kiểm tag chưa tồn tại trước khi push.
- **Attestation có thể không dùng được.** Docs GitHub mâu thuẫn: một trang ghi repo private trên Free/Pro/Team chỉ dùng được attestation cho repo public, trang khác ghi có trên mọi gói hiện hành. **Chưa xác minh** cả việc `push-to-registry` và `gh attestation verify oci://` chạy được với registry HTTP 2.8. Nếu không được: lưu attestation trên GitHub (không push vào registry) và kiểm bằng digest, hoặc ghi rõ bỏ bước này.
- **Ruleset trên repo private** cần gói Team trở lên (repo public trên Free thì có). **Chưa xác minh**: các repo sẽ public hay private; quyết định này ảnh hưởng runner, attestation và ruleset.
- **Không ký image** (lý do ở [`container-image.md`](container-image.md)).

## Bằng chứng cần có

| Chứng minh | Lệnh / cách đo | Đạt khi |
|---|---|---|
| Ghim SHA | `grep -rnE 'uses: [^ ]+@' .github/workflows \| grep -vE '@[0-9a-f]{40}( \|$)' \| grep -v '^.*uses: \./'` | 0 dòng |
| Quyền tối thiểu | Mọi file workflow có khối `permissions:`; [OpenSSF Scorecard](https://github.com/ossf/scorecard) với repo public | Token-Permissions và Pinned-Dependencies đạt 10 |
| Cache có tác dụng | Thời gian job build lần lạnh và lần ấm (từ tab Actions) | Ghi hai số; lần ấm nhanh hơn rõ |
| Test thật | Log `./gradlew check` có Testcontainers khởi động PostgreSQL/Kafka | Không có test bị skip vì thiếu Docker |
| Image | Digest trong output job; `curl -s http://10.20.0.5:5000/v2/<svc>/tags/list` có SHA | Tag = SHA, digest khớp `gitops` |
| Lỗ hổng, SBOM | Theo bảng ở [`container-image.md`](container-image.md) | Như ở đó |
| Provenance | `gh attestation verify oci://10.20.0.5:5000/<svc>@<digest> -R <owner>/<svc>` | Verify thành công (hoặc ghi lý do bỏ) |
| Lead time | Thời điểm merge → image trong registry → commit `gitops` → Argo CD `Healthy` | Ghi từng khoảng (phút) |
| Không đua ghi gitops | Merge 3 service cùng lúc | 3 commit tuần tự, không job lỗi |
| Fork không chạm secret | PR thử từ fork (nếu repo public) | Không job nào nhận secret hoặc chạy trên runner lab |

Kết quả ghi vào `docs/experiments/`.

## Nguồn
- GitHub Docs: [Reuse workflows](https://docs.github.com/en/actions/reference/workflows-and-actions/reusing-workflow-configurations), [Secure use](https://docs.github.com/en/actions/reference/security/secure-use), [Workflow dependency lockfiles](https://docs.github.com/en/actions/concepts/security/workflow-dependency-lockfiles), [Workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax), [GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token), [OpenID Connect](https://docs.github.com/en/actions/concepts/security/openid-connect), [Dependency caching](https://docs.github.com/en/actions/reference/workflows-and-actions/dependency-caching), [Artifact attestations](https://docs.github.com/en/actions/concepts/security/artifact-attestations), [Use artifact attestations](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations), [Immutable releases](https://docs.github.com/en/code-security/supply-chain-security/understanding-your-software-supply-chain/immutable-releases), [About protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches), [About rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets), [Dependabot options](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/dependabot-options-reference), [Actions Runner Controller](https://docs.github.com/en/actions/concepts/runners/actions-runner-controller), [GitHub App trong workflow](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/making-authenticated-api-requests-with-a-github-app-in-a-github-actions-workflow)
- [Gradle – GitHub Actions (9.9.1)](https://docs.gradle.org/current/userguide/github-actions.html), [Spring Boot – Testcontainers](https://docs.spring.io/spring-boot/reference/testing/testcontainers.html)
- [SLSA v1.2 – Build track](https://slsa.dev/spec/v1.2/build-track-basics), [SemVer 2.0.0](https://semver.org/spec/v2.0.0.html)
- [Tailscale GitHub Action](https://tailscale.com/kb/1276/tailscale-github-action), [Tailscale ACL](https://tailscale.com/kb/1018/acls)
- [BuildKit – buildkitd.toml](https://docs.docker.com/build/buildkit/toml-configuration/), [Kubernetes – Images](https://kubernetes.io/docs/concepts/containers/images/)
- [Trivy advisory GHSA-69fq-xp46-6x23](https://github.com/aquasecurity/trivy/security/advisories/GHSA-69fq-xp46-6x23)
