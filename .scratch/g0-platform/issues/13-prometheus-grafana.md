# 13: Prometheus và Grafana dạng code

Status: ready-for-human
Blocked by: 06
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

kube-prometheus-stack chạy Prometheus 1 bản (retention 15 ngày, `ServerSideApply`), Alertmanager, kube-state-metrics, node-exporter; Grafana mở qua `https://grafana.lab.internal`, đăng nhập bằng tài khoản admin cục bộ (mật khẩu là `SealedSecret`). Datasource và dashboard là code trong `gitops`. Mọi thành phần trong namespace `observability`, limit theo bảng ticket 04 của map. Theo [observability.md](../../../standards/observability.md).

## Mục tiêu học

- Prometheus Operator: `ServiceMonitor`, recording rule, và ngân sách cardinality.

## Thu hẹp 2026-11-15

Theo quyết định D4 (spec G0 mục "Sửa phạm vi 2026-11-15"). Quan sát vẫn giữ đủ như thiết kế; chỉ phần đăng nhập đổi.

- Giữ: Prometheus, Alertmanager, kube-state-metrics, node-exporter, Grafana với datasource và dashboard dạng code, không route cho Prometheus và Alertmanager.
- Đổi: Grafana dùng tài khoản admin cục bộ, mật khẩu là `SealedSecret`. Bỏ phụ thuộc ticket 11.
- Hoãn tới G7: SSO Grafana qua client `grafana` của realm, map group admin của realm sang quyền Admin của Grafana.

Tiêu chí hoãn tới G7:

- Đăng nhập Grafana bằng Keycloak; group admin của realm thành Admin của Grafana.

## Tiêu chí nghiệm thu

- [ ] Đăng nhập Grafana bằng admin cục bộ; mật khẩu lấy từ `SealedSecret`, không nằm dạng rõ trong `gitops`.
- [ ] Dashboard mặc định của cụm có dữ liệu cho cả 3 node.
- [ ] Sửa một dashboard trên UI rồi sync lại thì bị ghi đè bằng bản trong Git.
- [ ] `prometheus_tsdb_head_series` ghi vào bản ghi thí nghiệm G0 làm mốc.
- [ ] Prometheus và Alertmanager không có route trên `edge` (chỉ `port-forward`).

## Chuyển từ G0-10

- Keycloak đã bật `metrics-enabled`, `event-metrics-user-enabled`, `http-metrics-histograms-enabled` trên cổng 9000 của Service `keycloak-service` (namespace `keycloak`). Ngày 2026-11-27 `/metrics` có 1 649 series, gồm `keycloak_user_events_total{error,event,realm}` và 414 bucket `http_server_requests_seconds` ([bản ghi G0-10](../../../experiments/2026-11-g0-10-keycloak.md)). Tính vào ngân sách cardinality.
- Việc còn lại thuộc ticket này: (1) ServiceMonitor cho Keycloak. Operator tự tạo khi có CRD ServiceMonitor ≥ v0.72.0 (`spec.serviceMonitor` của CR); kiểm lại sau khi cài Prometheus Operator. (2) Giới hạn cổng 9000 chỉ cho namespace `observability`: đặt `spec.networkPolicy.management` trong `gitops/infra/keycloak/keycloak.yaml`. Hiện cổng này mở cho mọi pod. Probe của kubelet chạy trên 9000, nên sau khi đổi phải kiểm `keycloak-0` vẫn Ready. Checklist NetworkPolicy của `keycloak.md` để chưa tick tới khi xong.

## Lộ trình

Duyệt 2026-11-27. Phiên bản (tra 2026-11-27 bằng `helm pull`): chart `kube-prometheus-stack` 94.1.0 (OCI `ghcr.io/prometheus-community/charts`, digest `sha256:ad187276d823edb8f3655a3e538f311b9fe76d9fba008e8f0fa195dce18242e0`), Prometheus Operator v0.95.2, Prometheus v3.16.0, Alertmanager v0.35.1, Grafana 13.3.2 (subchart `grafana-community` 14.6.1). Quyết định khi lập lộ trình:

- **Q1 metric control plane**: kubeadm cho etcd (`--listen-metrics-urls=http://127.0.0.1:2381`), kube-scheduler, kube-controller-manager và kube-proxy (`metricsBindAddress: ""` = `127.0.0.1:10249`) nghe ở localhost (kiểm trên cụm 2026-11-27). Tắt `kubeEtcd`, `kubeScheduler`, `kubeControllerManager`, `kubeProxy` trong values, ghi lệch tại chỗ, **Hoãn tới G7** (mở ra phải sửa static pod manifest trên node, ngoài GitOps). Loại: để mặc định (4 target down, alert `*Down` bắn liên tục).
- **Q2 CRD**: vendor 10 CRD `monitoring.coreos.com` của prometheus-operator v0.95.2 vào `infra/kube-prometheus-stack/upstream/`, gắn `Prune=false,Delete=false`, `crds.enabled: false`, như cert-manager và sealed-secrets. Loại: chart tự cài (xóa nhầm app là xóa CRD, kéo theo CR Prometheus và StatefulSet).
- **Q3 webhook `PrometheusRule`**: `prometheusOperator.admissionWebhooks.certManager.enabled: true`, cert-manager cấp chứng chỉ. Loại: Job Helm hook mặc định (Argo CD chạy lại mỗi lần sync, như `startupapicheck`); tắt webhook (mất kiểm rule sai cú pháp).
- **Q4 alert ngân sách series**: giữ, kèm runbook `docs/runbooks/series-budget.md` (observability.md: mỗi alert có `runbook_url`).

- [x] 1. Namespace `observability` (PSA `privileged` vì node-exporter, nhãn route), CRD vendor, `sourceRepos` của project `platform`, Application chart chỉ bật Prometheus Operator, `ServerSideApply=true`, wave 6. Kiểm: 10 CRD `Established`, app `Synced/Healthy`, pod operator `Ready`.
  - Làm 2026-11-27, gitops `c8f1fcc` (chủ repo viết namespace, kustomization, vendor CRD; Claude viết Application, `sourceRepos` khi được giao cả bước 1–5). App `Synced/Healthy`, 10 CRD có `Prune=false,Delete=false`, webhook chặn rule sai (`kubectl apply --dry-run=server`: "could not parse expression: … unclosed left parenthesis"). Sự cố: áp 10 CRD (~4,4 MB) làm cainjector của cert-manager bị SIGKILL (exit 137), sau đó chạy 58/64 Mi, vì mặc định nó cache mọi CRD để tìm annotation `inject-ca-from`; `caBundle` của webhook chỉ được điền sau khi cainjector khởi động lại. Cụm không có CRD hay APIService nào cần inject: tắt hai loại đó (`--enable-customresourcedefinitions-injectable=false`, `--enable-apiservices-injectable=false`, gitops `bd9c86d`), cainjector còn 16 Mi.
- [x] 2. CR Prometheus: 1 bản, `retention: 15d` kèm `retentionSize`, PVC `local-path`, limit 1Gi, `exemplar-storage`, chọn mọi ServiceMonitor (`*SelectorNilUsesHelmValues: false`); ServiceMonitor kubelet, apiserver, CoreDNS; tắt 4 thành phần control plane (Q1). Kiểm: `port-forward` 9090, `up == 0` rỗng.
  - Làm 2026-11-27, gitops `80498f9` (Claude làm khi được giao). 15 target `up` (apiserver 1, kubelet 9 = 3 node × cAdvisor/probes/metrics, CoreDNS 2, operator 1, Prometheus 2), `up == 0` rỗng; PVC 10Gi `local-path` `Bound`; app `Synced/Healthy`. Ngay sau khi bật: `prometheus_tsdb_head_series` ≈ 70 000, phần lớn từ apiserver (~55 000, xem bước 8). Chart tạo Secret `kubernetes.io/service-account-token` cho Prometheus (ServiceMonitor kubelet, apiserver đọc qua `authorization.credentials`): mặc định chart, giữ (mức tối thiểu).
- [x] 3. kube-state-metrics, node-exporter. Kiểm: `count(node_uname_info)` = 3; `kube_pod_info` có pod mọi namespace.
  - Làm 2026-11-27, gitops `5ac11e2` (Claude làm khi được giao). `count(node_uname_info)` = 3; `kube_pod_info` có pod của 13 namespace; 19 target `up`. Bẫy digest: ba subchart ghép digest ba kiểu (`prometheusOperator`/Prometheus: `sha` chỉ phần hex; kube-state-metrics: `sha` gồm `sha256:`; node-exporter: `digest` gồm `sha256:`, `sha` làm render lỗi) và kube-prometheus-stack đặt node-exporter `distroless: true`, nên digest phải lấy từ tag `v1.13.1-distroless`.
- [x] 4. Alertmanager, default rules, PrometheusRule tự viết (recording rule series theo job, alert ngân sách series kèm runbook). Kiểm: recording rule có dữ liệu; Alertmanager chỉ có `Watchdog` firing.
  - Làm 2026-11-27, gitops `fd76a64`, docs `b6f465f` (runbook `runbooks/series-budget.md`) (Claude làm khi được giao). 223 rule đều `ok`; recording rule `job:scrape_samples_post_metric_relabeling:sum` có dữ liệu (apiserver 55 284, kubelet 13 979, kube-state-metrics 4 532, node-exporter 3 148…); chỉ `Watchdog` firing, Alertmanager nhận được (`/api/v2/alerts`). Nhóm rule của etcd, scheduler, controller-manager, kube-proxy tự tắt theo Q1. Chưa có alert 5 000 series mỗi pod service: chờ ServiceMonitor của `hello` (ticket 30). Chart ghi thêm trường `spec.sha` (deprecated) vào CR Alertmanager khi đặt `image.sha`: operator báo `DeprecatedFieldsInUse`, vô hại.
- [x] 5. Grafana: SealedSecret `grafana-admin` (`admin.existingSecret`), limit, HTTPRoute `grafana.lab.internal`. Kiểm: `/login` 200 qua `edge`, đăng nhập được, dashboard node có 3 node, `scripts/check-no-plain-secrets.sh` pass.
  - Làm 2026-11-27, gitops `2cda7f0`, `9bea5ed`, `0ae754d`, `281dedc`, `8793563` (Claude làm khi được giao). Đã kiểm trước khi mất kết nối tới lab: `https://grafana.lab.internal/login` 200 kèm HSTS; đăng nhập API bằng `admin` và mật khẩu đọc từ Secret `grafana-admin` → `isGrafanaAdmin: true`, sai mật khẩu → 401; datasource Prometheus (mặc định) và Alertmanager; 25 dashboard (23 sau khi bỏ AIX, macOS); biến node của "Node Exporter / Nodes" (qua proxy datasource của Grafana) trả 3 node `k8s-cp`, `k8s-w1`, `k8s-w2`; `scripts/check-no-plain-secrets.sh` OK; app `Synced/Healthy`, pod Grafana cuối cùng 0 restart.
  - Sự cố 1, RAM: ngân sách ticket 04 (224 + 2 × 48 Mi) làm cả ba container OOMKilled lúc khởi động. Đo với limit tạm 512/128 Mi: đỉnh Grafana 298 Mi, mỗi sidecar 78 Mi lúc ổn định; sidecar 96 Mi vẫn OOMKilled trong 2 s đầu. Chốt 384 + 2 × 128 = 640 Mi (+320 Mi so với ngân sách), ghi cho ticket 34.
  - Sự cố 2, quyền: mặc định kube-prometheus-stack cho sidecar Grafana đọc ConfigMap và Secret ở mọi namespace, kèm ClusterRole `get/list/watch` secrets toàn cụm (pod Grafana đọc được mọi Secret của cụm). Thu hẹp: `rbac.namespaced: true`, sidecar chỉ `configmap`, dashboard chỉ tìm trong `observability`.
  - Sự cố 3, root bị ghim: app `Degraded` (Grafana CrashLoop) giữ sync của `root-lab` ở revision cũ, commit nâng limit không được áp (đúng mục "Sync waves" của gitops-argocd.md). Gỡ bằng `argocd app terminate-op root-lab --core` (cần context kubeconfig ở namespace `argocd`, không thì lỗi `configmap "argocd-cm" not found`). Values Helm nằm trong object Application, nên phải refresh `root-lab`, refresh app con không đủ.
  - Kiểm lần cuối 2026-11-28 02:39 UTC, sau khi lab khởi động lại (mất kết nối từ 17:25 UTC): pod Grafana qua một lần khởi động lạnh với 384/128 Mi, restart duy nhất là do reboot (`Unknown/255`), không OOM. `kubectl auth can-i list secrets -A --as=system:serviceaccount:observability:kube-prometheus-stack-grafana` → `no` (cả namespace `keycloak`), `list configmaps -n observability` → `yes`; ClusterRole cũ đã bị gỡ. Đăng nhập lại được, sai mật khẩu 401, 23 dashboard (không còn AIX, macOS), 3 node. `prometheus.lab.internal`, `alertmanager.lab.internal` trả 404 (không route; HTTPRoute duy nhất trong `observability` là `grafana`). Dữ liệu Prometheus trước reboot (16:39–17:19 UTC) còn nguyên trên PVC; khoảng trống chỉ là lúc lab tắt.
- [x] 6. Dashboard "Cardinality" dạng ConfigMap (`grafana_dashboard: "1"`). Kiểm: sửa trên UI không lưu được hoặc bị ghi đè; sửa JSON trong Git thì Grafana tự nạp.
  - Làm 2026-11-28, gitops `7692edd`, `ce53d2c` (Claude làm khi được giao). Dashboard `Cardinality` (uid `cardinality`, 8 panel: head series so với 200 000, % ngân sách, series mang nhãn bị cấm, churn, series theo job và namespace từ recording rule bước 4, top 10 metric) là file `infra/kube-prometheus-stack/dashboards/cardinality.json`, `configMapGenerator` gắn nhãn `grafana_dashboard: "1"`. Mọi query đã chạy thử qua proxy datasource trước khi push (lúc đó: 86 576 series = 43% ngân sách, 0 series mang nhãn bị cấm, khoảng 155 series mới mỗi phút).
  - Kiểm tiêu chí 3, mạnh hơn câu chữ "sửa rồi sync thì bị ghi đè": (1) dashboard nạp sau push, `meta.provisioned: true`, nguồn `cardinality.json`; (2) lưu thay đổi bằng đúng API nút Save gọi (`POST /api/dashboards/db`) → HTTP 400 `Cannot save provisioned dashboard`, kể cả `overwrite: true`, tiêu đề panel giữ nguyên; (3) sửa JSON trong Git (thêm link runbook) → Grafana nạp bản mới sau 13 s tính từ push (version 1 → 2), không restart pod; (4) "Save as" ra bản sao (lưu được, nằm trong SQLite) → xóa pod Grafana → pod mới không còn bản sao, chỉ còn `Cardinality`. UI không có đường nào làm lệch bản trong Git một cách lâu dài.
  - `disableNameSuffixHash: true` có chủ đích: với hậu tố hash, đổi JSON thì Argo CD tạo ConfigMap tên mới rồi mới prune cái cũ; hai ConfigMap cùng key `cardinality.json` nên sự kiện DELETED của cái cũ làm sidecar xóa file vừa ghi (suy từ cách sidecar ghi theo tên key, **chưa thử** trên lab). Commit `ce53d2c` định dạng lại JSON (indent 2 như Export của Grafana) nên diff lớn hơn thay đổi thật.
- [ ] 7. Keycloak: ServiceMonitor do Operator tạo, `networkPolicy.management` chỉ từ `observability`. Kiểm: target Keycloak `up`; pod ở `default` gọi 9000 timeout; `keycloak-0` `Ready`.
- [ ] 8. Đo mốc: `prometheus_tsdb_head_series`, `topk(10, count by (__name__)(...))`, `count({workspace_id!=""})`, `kubectl top pods -n observability` so với ngân sách ticket 04. Kiểm: mục mới trong `docs/experiments/2026-11-g0.md`.
