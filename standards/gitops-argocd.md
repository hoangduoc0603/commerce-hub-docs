# Chuẩn: GitOps với Argo CD

- Ngày tra: 2026-11-12
- Phiên bản áp dụng: Argo CD v3.6.1 (bản stable mới nhất trên trang release, phát hành 04/11; Argo CD 3.6 được test với Kubernetes 1.34–1.37), Kubernetes 1.37, Helm v4 (Argo CD từ 3.5 chỉ render bằng Helm v4), Sealed Secrets v0.41.2 (2026-10-26). Argo CD Image Updater v1.x chỉ được cân nhắc, không dùng.
- Phạm vi: repo `gitops` (`apps/`, `envs/<env>/<service>/`, thư mục bootstrap Argo CD đề xuất `bootstrap/argocd/`), mọi `Application`, `ApplicationSet`, `AppProject`, cấu hình `argocd-cm`/`argocd-rbac-cm`, `SealedSecret`. Chart dùng chung xem [`helm-chart.md`](helm-chart.md); pipeline đẩy image tag xem [`ci-cd.md`](ci-cd.md); migration chạy trong sync xem [`db-migration.md`](db-migration.md); rollout không downtime xem [`zero-downtime.md`](zero-downtime.md).

## Checklist

### Cài đặt và bootstrap
- [ ] Argo CD cài từ manifest **ghim tag `v3.6.1`**, không trỏ nhánh `stable` hay `HEAD`. Base từ xa trỏ HEAD có thể "đột ngột đổi nghĩa"; tag hoặc SHA mới bất biến. [Best Practices – immutability](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/), [Installation](https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/)
- [ ] `gitops/bootstrap/argocd/kustomization.yaml` dùng manifest Argo CD làm resource và patch cấu hình (`argocd-cm`, `argocd-rbac-cm`, `argocd-cmd-params-cm`). Docs đề xuất quản lý Argo CD bằng Kustomize overlay. [Declarative Setup – Manage Argo CD Using Argo CD](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#manage-argo-cd-using-argo-cd)
- [ ] Bootstrap đúng hai lệnh tay, ghi trong runbook: `kubectl apply --server-side -k bootstrap/argocd` rồi `kubectl apply -f apps/root-<env>.yaml`. Sau đó mọi thay đổi (kể cả nâng Argo CD) đi qua Git. [Cluster Bootstrapping](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [ ] `Application` tự quản lý Argo CD có sync option `ServerSideApply=true`. Docs ghi đây là **bắt buộc** khi Argo CD quản lý chính nó. [Declarative Setup](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#manage-argo-cd-using-argo-cd)
- [ ] Nâng Argo CD từng minor một và đọc trang upgrade tương ứng trước khi đổi tag (ví dụ 3.5→3.6 đổi tên biến OTel của repo-server, bật Server-Side Diff cho app dùng SSA). [Upgrading 3.5→3.6](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.5-3.6/)

### Cấu trúc Application: app-of-apps + ApplicationSet
- [ ] Mỗi môi trường có **một** root `Application` (app-of-apps) trỏ `apps/<env>/`. Thư mục này chứa `AppProject`, `Application` của hạ tầng (Argo CD, Sealed Secrets, Strimzi, CloudNativePG, LGTM, Keycloak) và một `ApplicationSet` cho service. [Cluster Bootstrapping – App of Apps](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [ ] Chỉ admin được push vào `apps/` và review trường `project`. Docs gọi app-of-apps là "an admin-only tool". [Cluster Bootstrapping](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [ ] Service sinh bằng `ApplicationSet` với Git directory generator quét `envs/<env>/*`; thêm service là thêm thư mục. Trường `project` **viết cứng**, không template hóa. Template hóa `project` cho phép người ghi vào nguồn generator đưa app vào project lỏng hơn. [ApplicationSet Security](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Security/)
- [ ] Application service dùng multiple sources: chart `spring-service` từ OCI registry + `ref: values` trỏ repo `gitops`, `valueFiles: [$values/envs/<env>/<svc>/values.yaml]`. `$values` chỉ dùng ở đầu đường dẫn; source có `ref` không được có `chart`. [Multiple Sources](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/)
- [ ] `targetRevision` của chart là version SemVer cụ thể, không dùng range. Chart đổi version phải là một commit trong `gitops`, rollback được. [Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)
- [ ] Repo secret cho registry chart HTTP của lab đặt `insecureOCIForceHttp: "true"`, **không** kèm `insecure: "true"` (skip TLS verify) và không kèm `enableOCI` trên repo `type=helm`. Helm v4 bỏ âm thầm `--plain-http` khi có cả hai cờ; `type=helm` + `enableOCI` + force-HTTP làm kéo chart thất bại. [Upgrading 3.4→3.5](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.4-3.5/)
- [ ] Child app có finalizer `resources-finalizer.argocd.argoproj.io`; tài nguyên giữ dữ liệu (PVC, CR `Cluster` của CloudNativePG, CR `Kafka`) có annotation `argocd.argoproj.io/sync-options: Delete=false`. Xóa nhầm app không được kéo theo dữ liệu. [Declarative Setup – finalizer](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/), [Sync Options – Delete=false](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/)

### AppProject: giới hạn nguồn và đích
- [ ] Project `default` bị khóa: `sourceRepos: []`, `destinations: []`. Mặc định nó cho mọi repo, mọi cluster, mọi Kind. [Projects – default project](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/)
- [ ] Project `platform` (hạ tầng): được tạo tài nguyên cluster-scoped cần thiết; chỉ admin dùng. Project nào có đích là namespace `argocd` thì tương đương quyền admin. [Declarative Setup – Projects](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#projects)
- [ ] Project `commerce` (service): `sourceRepos` chỉ gồm repo `gitops` và registry chart; `destinations` chỉ namespace của service; `clusterResourceWhitelist: []`; `namespaceResourceBlacklist` gồm `ResourceQuota`, `LimitRange`, `NetworkPolicy` (do `platform` quản lý). [Declarative Setup – Projects](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#projects)

### Sync policy
- [ ] App service: `syncPolicy.automated` với `prune: true`, `selfHeal: true`; `allowEmpty` để mặc định `false`. Prune và self-heal mặc định tắt; `allowEmpty: false` chặn lỡ làm rỗng app. [Automated Sync Policy](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/)
- [ ] `syncPolicy.retry` có `limit` hữu hạn (ví dụ 5) và backoff; không đặt `-1`. Automated sync không thử lại cùng commit đã thất bại nếu không có retry. [Automated Sync Policy – retry](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/)
- [ ] Sync options mặc định cho app service: `PruneLast=true`, `FailOnSharedResource=true`; không dùng `Replace=true`; không dùng `CreateNamespace=true` (namespace do project `platform` tạo, kèm quota và NetworkPolicy). [Sync Options](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/)
- [ ] Không đưa vào Git trường do controller khác quản lý: không có `spec.replicas` khi bật HPA/KEDA (xem [`helm-chart.md`](helm-chart.md)); khác biệt còn lại khai báo `ignoreDifferences` + `RespectIgnoreDifferences=true`. [Best Practices – leave room for imperativeness](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)

### Sync waves, hooks, health
- [ ] Thứ tự trong một app: wave `-1` cho `SealedSecret`, `ConfigMap`; migration là hook `PreSync` (chi tiết ở [`db-migration.md`](db-migration.md)); workload wave `0`; smoke test là hook `PostSync`. Wave nhỏ chạy trước; PreSync lỗi thì dừng sync. [Sync Phases and Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [ ] Mọi hook idempotent. Hook chạy ở **mọi** lần sync, kể cả self-heal. [Sync Phases and Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [ ] Hook Job dùng `hook-delete-policy: BeforeHookCreation` (giữ Job gần nhất để đọc log) và **không** đặt `ttlSecondsAfterFinished`. Kubernetes có thể xóa Job trước khi Argo CD đọc kết quả. [Sync Phases and Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [ ] Chart không trộn hook Helm và hook Argo CD: có một hook Argo CD thì mọi hook Helm bị bỏ qua. Dùng annotation Argo CD. [Helm – Helm Hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/)
- [ ] Root app sắp thứ tự hạ tầng trước service bằng sync wave trên child `Application`, và `argocd-cm` có health check Lua `resource.customizations.health.argoproj.io_Application`. Health của Application đã bị gỡ từ 1.8; thiếu nó thì wave không chờ app con Healthy. [Resource Health – Argo CD App](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/#argocd-app)
- [ ] CRD của operator dùng trong lab (Strimzi `Kafka`, CloudNativePG `Cluster`, `SealedSecret`) có health check (built-in hoặc Lua tự viết); kiểm bằng cách làm hỏng một CR và xem app chuyển `Degraded`. Argo CD chỉ đánh giá đúng health CRD khi có check riêng. [Resource Health – Custom Health Checks](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/) **Chưa xác minh**: danh sách check built-in cho các CRD này (3.6 mới thêm check cho `postgresql.cnpg.io/Database`). [Upgrading 3.5→3.6](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.5-3.6/)

### Cập nhật image
- [ ] Chỉ CI của service đổi image trong `gitops`, bằng một commit sửa `envs/<env>/<svc>/values.yaml` (digest + tag = git SHA). Argo CD tự kéo; CI không giữ token Argo CD, không gọi `kubectl`/`argocd`. Tách repo cấu hình giúp lịch sử deploy sạch và tránh vòng lặp build. [Best Practices – separate config repo](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/)

### Secret
- [ ] Không có `kind: Secret` dạng rõ trong Git; secret đi vào cụm qua `SealedSecret` (scope `strict` mặc định). Argo CD khuyên quản lý secret ở cụm đích, Argo CD không cần đọc secret. [Secret Management](https://argo-cd.readthedocs.io/en/stable/operator-manual/secret-management/), [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [ ] Không dùng plugin chèn secret lúc render manifest (argocd-vault-plugin, CMP giải mã SOPS). Argo CD cache manifest đã render dạng rõ trong Redis. [Secret Management](https://argo-cd.readthedocs.io/en/stable/operator-manual/secret-management/)
- [ ] Sao lưu khóa sealing ra ngoài cụm sau **mỗi** lần khóa gia hạn (mặc định 30 ngày): `kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml`. Bản backup chứa private key, cất trong password manager hoặc ổ mã hóa, không cất trong Git. Dựng lại cụm mà mất khóa thì mọi SealedSecret vô dụng. [Sealed Secrets – key renewal, backup](https://github.com/bitnami-labs/sealed-secrets)
- [ ] Xoay vòng giá trị secret thật (mật khẩu DB, token) theo lịch; gia hạn khóa sealing **không** thay việc này. [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets)
- [ ] Đổi secret phải kéo theo rollout: chart nhận annotation `secretRevision` trong values, commit đổi SealedSecret tăng giá trị đó cùng lúc. Checksum trong chart không thấy Secret ngoài chart (xem [`helm-chart.md`](helm-chart.md)). Đây là quy ước của dự án, không phải khuyến nghị từ docs.

### RBAC và truy cập
- [ ] SSO qua Keycloak bằng `oidc.config` (xem [`keycloak.md`](keycloak.md)), sau đó `admin.enabled: "false"` trong `argocd-cm`. Docs khuyên chỉ dùng `admin` lúc cấu hình ban đầu. [User Management](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/)
- [ ] `policy.default` để trống hoặc `role:readonly`; quyền `sync`, `override`, `exec` chỉ cấp cho group admin. Mọi user đăng nhập nhận ít nhất quyền mặc định và `deny` không chặn được nó. [RBAC](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)
- [ ] `applicationsets` create/update/delete chỉ admin. ApplicationSet tạo được app ở mọi project và đọc được Secret trong namespace Argo CD. [ApplicationSet Security](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Security/)
- [ ] `policy.csv` qua `argocd admin settings rbac validate` trong CI của `gitops`. Sai cú pháp RBAC thường im lặng. [RBAC – Validating and testing](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)
- [ ] Không tạo account `apiKey` cho CI. Mô hình pull không cần; nếu buộc phải có thì token có `--expires-in`. [User Management – local users](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/)

### Rollback
- [ ] Rollback = `git revert` commit đổi image trong `gitops`, rồi để automated sync áp. `argocd app rollback` không chạy được khi bật automated sync, và nếu tắt sync để rollback thì Git và cụm lệch nhau. [Automated Sync Policy](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/), [argocd app rollback](https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd_app_rollback/)
- [ ] Rollback code chỉ an toàn khi schema DB tương thích ngược với bản N-1 (expand/contract, [`db-migration.md`](db-migration.md)).
- [ ] Argo Rollouts (canary, tự rollback theo metric) thuộc giai đoạn 7; khi đó rollback tự động là `abort`, sau đó vẫn phải revert Git để Git khớp cụm. [Argo Rollouts](https://argo-rollouts.readthedocs.io/en/stable/)

## Lựa chọn và phương án đã loại

| Quyết định | Chọn | Loại | Lý do | Nguồn |
|---|---|---|---|---|
| Tổ chức Application | App-of-apps cho root/hạ tầng + ApplicationSet (Git directory) cho service, `project` viết cứng | Chỉ app-of-apps (chép YAML từng service); chỉ ApplicationSet (khó sắp thứ tự hạ tầng) | Hạ tầng ít, cần thứ tự rõ; service nhiều và giống nhau | [Cluster Bootstrapping](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/), [ApplicationSet](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/) |
| Cập nhật image tag | CI commit vào `gitops` | Argo CD Image Updater | Commit tường minh, gắn với lần CI xanh, audit được, không cần credential Git trong cụm. Image Updater "under active development", phải poll registry, write-back `argocd` không bền khi app tạo lại | [Image Updater](https://argocd-image-updater.readthedocs.io/en/stable/), [Update methods](https://argocd-image-updater.readthedocs.io/en/stable/basics/update-methods/) |
| Secret trong GitOps (**nên viết ADR**) | Sealed Secrets | External Secrets Operator; SOPS | ESO cần một kho secret ngoài (Vault/OpenBao…), thêm hệ thống phải vận hành trên cụm 32 GB. SOPS với Argo CD cần CMP giải mã lúc render, đúng kiểu Argo CD "strongly caution against". Sealed Secrets chỉ cần một controller; giá phải trả là backup khóa. Xem lại ở giai đoạn 7 (ESO + Vault) | [Secret Management](https://argo-cd.readthedocs.io/en/stable/operator-manual/secret-management/), [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets), [ESO](https://external-secrets.io/latest/introduction/overview/), [SOPS](https://getsops.io/docs/) |
| Kiểu cài Argo CD | `install.yaml` (non-HA) + Kustomize, tự quản lý | HA manifest; Helm chart cộng đồng | HA cần nhiều replica, cụm sát RAM; Kustomize là cách docs dùng cho self-management | [Installation](https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/) |
| Rollback | `git revert` | `argocd app rollback` | Tương thích automated sync, Git luôn là nguồn sự thật | [Automated Sync Policy](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/) |

## Lệch chuẩn có chủ đích ở home lab
- **Non-HA.** Docs khuyên HA cho production. Lab có 3 VM với 32 GB RAM; chấp nhận Argo CD gián đoạn khi node chứa nó khởi động lại (workload đang chạy không bị ảnh hưởng).
- **Registry chart HTTP không auth** (`insecureOCIForceHttp`). Chỉ truy cập được trong lab/tailnet; lý do xem [`helm-chart.md`](helm-chart.md).
- **Argo CD và workload cùng một cụm.** Docs gợi ý cụm riêng cho Argo CD để giảm rủi ro; lab chỉ có một cụm.
- **Sealed Secrets thay vì kho secret tập trung.** Không có audit truy cập secret và không xoay vòng tự động. Bù bằng lịch xoay vòng tay và backup khóa.

## Bằng chứng cần có

| Chứng minh | Lệnh | Đạt khi |
|---|---|---|
| Đúng phiên bản | `argocd version --short` | Server `v3.6.1` |
| Bootstrap tái lập | Cụm trắng → 2 lệnh bootstrap; đo thời gian tới khi `kubectl -n argocd get applications` toàn `Synced/Healthy` | Không có bước tay ngoài runbook; ghi số phút |
| Self-heal | `kubectl -n <ns> scale deploy <svc> --replicas=0`; đo thời gian tới khi Argo CD trả về | Tự khôi phục; ghi số giây |
| Prune | Xóa một resource khỏi Git | Resource biến khỏi cụm sau sync |
| Project chặn được | App trong `commerce` trỏ namespace `argocd` hoặc thêm `ClusterRole` | Sync bị từ chối |
| RBAC | `argocd admin settings rbac can role:readonly sync applications 'commerce/*' --policy-file policy.csv` | `No`; `validate` không lỗi |
| Không có secret rõ | `git -C gitops grep -l '^kind: Secret$'` | 0 file |
| Khôi phục khóa sealing | Dựng cụm mới, nạp backup khóa, sync | SealedSecret giải mã được |
| Rollback | `git revert` commit image; đo thời gian từ push tới `Healthy` ở bản cũ | Ghi số giây; 0 request lỗi khi chạy tải song song (cách đo ở [`zero-downtime.md`](zero-downtime.md)) |
| Chart qua HTTP | App multi-source kéo `spring-service` từ `10.20.0.5:5000` | `Synced`, không có lỗi `server gave HTTP response to HTTPS client` |

Kết quả ghi vào `docs/experiments/`.

## Nguồn
- Argo CD (stable = 3.6): [Releases](https://github.com/argoproj/argo-cd/releases), [Installation](https://argo-cd.readthedocs.io/en/stable/operator-manual/installation/), [Declarative Setup](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/), [Cluster Bootstrapping](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/), [ApplicationSet](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/), [ApplicationSet Security](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Security/), [Projects](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/), [Automated Sync Policy](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/), [Sync Options](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/), [Sync Phases and Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/), [Resource Health](https://argo-cd.readthedocs.io/en/stable/operator-manual/health/), [Helm](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/), [Multiple Sources](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/), [Secret Management](https://argo-cd.readthedocs.io/en/stable/operator-manual/secret-management/), [RBAC](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/), [User Management](https://argo-cd.readthedocs.io/en/stable/operator-manual/user-management/), [Best Practices](https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/), [argocd app rollback](https://argo-cd.readthedocs.io/en/stable/user-guide/commands/argocd_app_rollback/), [Upgrading 3.4→3.5](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.4-3.5/), [Upgrading 3.5→3.6](https://argo-cd.readthedocs.io/en/stable/operator-manual/upgrading/3.5-3.6/)
- [Argo CD Image Updater](https://argocd-image-updater.readthedocs.io/en/stable/), [Update methods](https://argocd-image-updater.readthedocs.io/en/stable/basics/update-methods/)
- [Argo Rollouts](https://argo-rollouts.readthedocs.io/en/stable/)
- [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets), [Releases](https://github.com/bitnami-labs/sealed-secrets/releases)
- [External Secrets Operator – Overview](https://external-secrets.io/latest/introduction/overview/), [SOPS](https://getsops.io/docs/)
