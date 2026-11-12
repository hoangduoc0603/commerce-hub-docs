# Resource mặc định của các thành phần hạ tầng (đầu vào cho ngân sách RAM home lab)

Tra cứu ngày 12/11/2026. Bối cảnh: cụm kubeadm Kubernetes 1.37, 3 VM × 8 GB RAM. Ghi chép này chỉ gom **giá trị `resources` mặc định** (request/limit CPU và memory) và khuyến nghị tối thiểu nếu tài liệu chính thức có nêu. Không tính ngân sách, không đề xuất cấu hình. Broker Kafka (~1,5 Gi × 3) và Keycloak server (request 1700Mi, limit 2Gi) đã chốt ở chỗ khác nên không tra lại.

Cách tra:

- Đọc manifest phát hành hoặc `values.yaml` của Helm chart **ở đúng git tag** qua `raw.githubusercontent.com`. Phiên bản và ngày phát hành lấy từ GitHub Releases API hoặc `index.yaml` của Helm repo.
- Chart có giá trị tính ra trong template (memcached của Loki, config-reloader của prometheus-operator) thì render bằng `helm template` (Helm v4.3.0) với giá trị mặc định để xem resource thực tế ghi vào Pod.
- Operator tự sinh Pod (Apicurio, CNPG Pooler, Strimzi Entity Operator, Calico, prometheus-operator) thì đọc mã nguồn ở tag để biết operator có tự điền resource hay không.

Nhãn: **[CT]** tài liệu hoặc mã nguồn chính thức · **[CXM]** chưa xác minh · **[SL]** suy luận của người viết, chưa có nguồn nói thẳng.

Quy ước trong bảng: "not set" nghĩa là manifest không có khối `resources` hoặc để `{}`. Khi đó scheduler tính container này là 0, và nếu cả Pod không có request/limit thì Pod thuộc QoS `BestEffort`.

## Tóm tắt

- **Phần lớn thành phần không đặt resource.** Các thành phần "not set": toàn bộ Argo CD, Sealed Secrets, cert-manager, MetalLB, local-path-provisioner, Calico (cài bằng operator), kube-prometheus-stack (Prometheus, operator, kube-state-metrics, node-exporter, Grafana), Loki (pod `loki`), Tempo, OTel Collector, Strimzi Entity Operator, Strimzi Drain Cleaner, PgBouncer của CNPG `Pooler`, plugin Barman Cloud và sidecar của nó. Ngân sách RAM cho các thành phần này phải lấy từ số đo, manifest không cho con số nào.
- **Các thành phần có đặt memory:**
  - Strimzi cluster operator: 384Mi/384Mi.
  - Keycloak Operator: 450Mi/450Mi.
  - Apicurio Registry: operator 100Mi/500Mi. Operator tự điền cho app 512Mi/1Gi và cho UI 256Mi/512Mi.
  - CNPG operator: 100Mi/200Mi.
  - metrics-server: request 200Mi.
  - CoreDNS: 70Mi/170Mi, 2 replica.
  - etcd: request 100Mi.
  - Alertmanager: request 200Mi, do prometheus-operator tự điền.
  - memcached của Loki: chunks-cache 9830Mi, results-cache 1229Mi.
- **Bẫy cần biết:**
  - Chart Loki 21.2.1 mặc định bật `chunksCache` với request **9830Mi**, lớn hơn RAM của một node 8 GB. Pod này sẽ không bao giờ được lập lịch nếu không giảm `allocatedMemory` hoặc tắt [CT, render chart].
  - Image operator của Strimzi tự thêm `-XX:MaxRAMPercentage=20` nếu không có cấu hình khác. Nếu Entity Operator không có memory limit, heap tối đa tính theo RAM của node [CT, `launch_java.sh`].
  - Prometheus 3.16 bật `--auto-gomemlimit` mặc định (tỉ lệ 0,9 của memory limit). Processor `memory_limiter` của OTel Collector tính theo phần trăm. Cả hai chỉ bám đúng khi container có memory limit. Không có limit thì chúng dựa vào RAM của node [CT cho flag; SL cho hệ quả].
- **Phiên bản thực tế khác giả định ban đầu ở 3 chỗ:**
  - Chart OTel Collector mới nhất (0.178.3) vẫn mặc định image collector **0.163.2**. Collector 0.165.0 đã phát hành ngày 07/11/2026 nhưng chưa có chart nào dùng làm `appVersion`.
  - Manifest Drain Cleaner nằm trong repo Strimzi 1.3.1 ghim image **1.6.1**, còn bản mới nhất của repo `strimzi/drain-cleaner` là **1.8.0**.
  - Repo Sealed Secrets đã chuyển từ `bitnami-labs/sealed-secrets` sang `bitnami/sealed-secrets`.

### Phiên bản đã tra

| Thành phần | Phiên bản | Ngày phát hành | Ghi chú |
|---|---|---|---|
| Strimzi | 1.3.1 | 04/11/2026 | Drain Cleaner riêng: 1.8.0 (19/10/2026) |
| Apicurio Registry | 3.3.4 | 03/11/2026 | |
| Keycloak / Keycloak Operator | 26.8.2 | 05/11/2026 | Manifest ở `keycloak/keycloak-k8s-resources@26.8.2` |
| CloudNativePG | 1.30.1 | 23/09/2026 | |
| Plugin Barman Cloud | v0.16.0 | 09/11/2026 | |
| cert-manager | **v1.21.3** | 23/10/2026 | Bản stable mới nhất theo số phiên bản. v1.20.5 ra sau (28/10) nhưng thuộc nhánh cũ |
| Argo CD | v3.6.1 | — | `manifests/install.yaml` |
| Sealed Secrets | v0.41.2 (chart `helm-v2.22.0`) | 26/10/2026 | |
| kube-prometheus-stack | **93.2.2** | 11/11/2026 | Prometheus v3.16.0, prometheus-operator v0.95.2, kube-state-metrics v2.20.0 (chart 9.0.1), node-exporter v1.12.1 (chart 5.1.0), Grafana 13.3.1 (chart `grafana-community/grafana` 14.4.1) |
| Loki | 3.7.9 (chart `grafana-community/loki` **21.2.1**) | 11/11/2026 | |
| Tempo | 3.1.1 (chart `grafana-community/tempo` **3.2.1**) | 21/10/2026 | |
| OTel Collector | chart **0.178.3**, image mặc định 0.163.2 | 10/11/2026 | Collector 0.165.0 đã có release nhưng chưa vào chart |
| Calico | v3.33.0 (tigera-operator v1.44.0) | 01/10/2026 | Các bản ra sau thuộc nhánh 3.32 (v3.32.4 ngày 11/11/2026) |
| MetalLB | v0.16.2 | — | `metallb-native.yaml` |
| metrics-server | v0.9.1 | — | `components.yaml` |
| local-path-provisioner | v0.0.37 | — | |
| kubeadm | **v1.37.2** | 28/10/2026 | CoreDNS v1.14.6, etcd 3.7.0-0 |

---

## 1. Strimzi 1.3.1

| Thành phần | Container | Request CPU / mem | Limit CPU / mem | Nguồn |
|---|---|---|---|---|
| Cluster operator (Deployment, 1 replica) | `strimzi-cluster-operator` | 200m / 384Mi | 1000m / 384Mi | `install/cluster-operator/060-Deployment-strimzi-cluster-operator.yaml` và `packaging/helm-charts/helm3/strimzi-kafka-operator/values.yaml` (`resources`) @1.3.1 [CT] |
| Entity Operator | `topic-operator` | not set | not set | `EntityTopicOperator.java`: `result.resources = topicOperatorSpec.getResources()`, không có giá trị mặc định [CT] |
| Entity Operator | `user-operator` | not set | not set | `EntityUserOperator.java`, tương tự [CT] |
| Drain Cleaner (manifest trong repo Strimzi 1.3.1, image 1.6.1) | `strimzi-drain-cleaner` | not set | not set | `install/drain-cleaner/kubernetes/060-Deployment.yaml` @1.3.1 [CT] |
| Drain Cleaner 1.8.0 (repo riêng) | `strimzi-drain-cleaner` | not set | not set | `packaging/install/kubernetes/060-Deployment.yaml` và Helm `values.yaml` (`resources: {}`) @`strimzi/drain-cleaner` 1.8.0 [CT] |

Ghi chú:

- Docs Strimzi chỉ cho **ví dụ** resource của Topic Operator là request 1 CPU / 512Mi, limit 1 CPU / 512Mi. Đây không phải mặc định. Ví dụ `kafka-persistent.yaml` để `topicOperator: {}` và `userOperator: {}` [CT, `documentation/modules/con-common-configuration-properties.adoc`].
- Docs Strimzi khuyên đặt request bằng limit để có QoS ổn định ("Setting equal requests and limits for resources guarantees quality of service") [CT, cùng file].
- Script khởi động mọi operator Java của Strimzi tự thêm `-XX:MinRAMPercentage=15 -XX:MaxRAMPercentage=20` nếu `JAVA_OPTS` chưa có, và đặt `MALLOC_ARENA_MAX=2` [CT, `docker-images/operator/scripts/launch_java.sh` @1.3.1]. Ta có thể đặt heap riêng qua `jvmOptions` của từng container.
- Giá trị Helm chart của Drain Cleaner 1.8.0 có đoạn comment ví dụ (100m / 128Mi cho cả request lẫn limit) và câu "We usually recommend not to specify default resources" [CT].

## 2. Apicurio Registry 3.3.4

| Thành phần | Container | Request CPU / mem | Limit CPU / mem | Nguồn |
|---|---|---|---|---|
| Operator (Deployment) | operator | 100m / 100Mi | 200m / 500Mi | `operator/install/apicurio-registry-operator-3.3.4.yaml` @3.3.4 [CT] |
| App (operator sinh, `ApicurioRegistry3`) | `apicurio-registry-app` | 500m / 512Mi | 1 / 1Gi | `ResourceFactory.getDefaultAppDeployment` @3.3.4. Chỉ áp khi container trong `podTemplateSpec` chưa có `resources` [CT] |
| UI (operator sinh) | `apicurio-registry-ui` | 100m / 256Mi | 200m / 512Mi | `ResourceFactory.getDefaultUIDeployment` [CT] |
| Console plugin (chỉ OpenShift) | console plugin | 100m / 256Mi | 500m / 512Mi | `ResourceFactory`. Mặc định tắt (`spec.consolePlugin.enabled: false`) [CT] |

Ghi chú:

- Deployment UI **không có activation condition** trong `ApicurioRegistry3Reconciler`, nên operator luôn tạo UI cùng app [CT]. Có thể tắt UI bằng `spec.ui.replicas: 0` hay không thì **[CXM]**.
- Không tìm thấy khuyến nghị memory tối thiểu cho app trong docs 3.3.4. Đã grep `docs/modules/ROOT/pages/getting-started/*` (deploying operator, docker, storage) và `operator/docs`. Chỉ thấy cảnh báo rằng H2 mặc định lưu dữ liệu trong RAM, và ví dụ `databaseMemoryRequest: 128Mi` / `databaseMemoryLimit: 512Mi` cho PostgreSQL trên OpenShift **[CXM: không có khuyến nghị]**.

## 3. Keycloak Operator 26.8.2

| Thành phần | Container | Request CPU / mem | Limit CPU / mem | Nguồn |
|---|---|---|---|---|
| Operator (Deployment) | `keycloak-operator` | 300m / 450Mi | 700m / 450Mi | `kubernetes/kubernetes.yml` @`keycloak/keycloak-k8s-resources` 26.8.2 [CT] |

Keycloak server (1700Mi / 2Gi) đã biết nên không tra lại.

## 4. CloudNativePG 1.30.1 và plugin Barman Cloud v0.16.0

| Thành phần | Container | Request CPU / mem | Limit CPU / mem | Nguồn |
|---|---|---|---|---|
| Operator `cnpg-controller-manager` (đối chiếu) | `manager` | 100m / 100Mi | 100m / 200Mi | `cnpg-1.30.1.yaml` (release asset) [CT] |
| `Pooler` (PgBouncer), `spec.instances` mặc định 1 | `pgbouncer` | not set | not set | `pkg/specs/pgbouncer/deployments.go` và `api/v1/pooler_funcs.go` `GetResourcesRequirements()`. Không có template thì trả `ResourceRequirements{}` rỗng [CT] |
| `Pooler` | init `bootstrap-controller` | lấy theo `spec.template.spec.resources` (mặc định rỗng) | như request | cùng file [CT] |
| Plugin Barman Cloud (Deployment) | `barman-cloud` | not set (`resources: {}`) | not set | `manifest.yaml` release v0.16.0 [CT] |
| Sidecar plugin trong mỗi instance PostgreSQL | `plugin-barman-cloud` | not set | not set | `internal/cnpgi/operator/lifecycle_resources.go`. Lấy từ `ObjectStore.spec.instanceSidecarConfiguration.resources`, không có giá trị mặc định [CT] |

Ghi chú:

- Docs CNPG chỉ có **ví dụ** resource cho PgBouncer: request 0.1 CPU / 100Mi, limit 0.5 CPU / 500Mi. Các ví dụ trong docs dùng `instances: 3` [CT, `docs/src/connection_pooling.md` @v1.30.1].
- Docs plugin chỉ cho khung `resources` với giá trị `"XXX"`/`"YYY"`, không có con số khuyến nghị [CT, `web/docs/usage.md` @v0.16.0].

## 5. cert-manager v1.21.3

| Thành phần | Container | Request CPU / mem | Limit CPU / mem | Nguồn |
|---|---|---|---|---|
| controller (1 replica) | `cert-manager-controller` | not set | not set | `deploy/charts/cert-manager/values.yaml` `resources: {}` @v1.21.3 [CT] |
| webhook (1 replica) | `cert-manager-webhook` | not set | not set | `webhook.resources: {}` [CT] |
| cainjector (1 replica, `enabled: true`) | `cert-manager-cainjector` | not set | not set | `cainjector.resources: {}` [CT] |
| startupapicheck (Job hook, `enabled: true`) | `cert-manager-startupapicheck` | not set | not set | `startupapicheck.resources: {}` [CT] |

Comment trong `values.yaml` có ví dụ `requests: cpu 10m, memory 32Mi` cho controller. Đây chỉ là ví dụ, không phải mặc định [CT].

## 6. Argo CD v3.6.1 (`manifests/install.yaml`, non-HA)

| Thành phần | Container | Request CPU / mem | Limit CPU / mem | Nguồn |
|---|---|---|---|---|
| `argocd-application-controller` (StatefulSet, 1) | `argocd-application-controller` | not set | not set | `manifests/install.yaml` @v3.6.1 [CT] |
| `argocd-repo-server` | `argocd-repo-server` (+ init `copyutil`) | not set | not set | như trên [CT] |
| `argocd-server` | `argocd-server` | not set | not set | như trên [CT] |
| `argocd-redis` | `redis` (`redis:8.10.1-alpine`, + init `secret-init`) | not set | not set | như trên [CT] |
| `argocd-dex-server` | `dex` (`dex:v2.46.0`, + init `copyutil`) | not set | not set | như trên [CT] |
| `argocd-applicationset-controller` | `argocd-applicationset-controller` | not set | not set | như trên [CT] |
| `argocd-notifications-controller` | `argocd-notifications-controller` | not set | not set | như trên [CT] |

`install.yaml` không có dòng `memory:` nào. Kiểm bằng grep: 0 kết quả.

Thành phần nào bỏ được:

- **Dex:** docs nói Argo CD dùng Dex để xác thực với OIDC provider ngoài, "however other tools can be used instead of Dex". Cấu hình SSO có hai cách: Dex đi kèm, hoặc nối thẳng "Existing OIDC provider", và Keycloak có trong danh sách [CT, `docs/developer-guide/architecture/components.md`, `docs/operator-manual/user-management/index.md`]. Nếu nối thẳng Keycloak thì không cần Dex. Ngoại lệ: token exchange cho CI cần Dex [CT, cùng file].
- **Bản cài Core** (`core-install.yaml`) chỉ có 4 workload: `argocd-application-controller`, `argocd-applicationset-controller`, `argocd-repo-server`, `argocd-redis`. Bản này mất API, RBAC của Argo CD, notification controller và xác thực OIDC [CT, `docs/operator-manual/core.md`, `manifests/core-install.yaml`]. Redis vẫn được giữ vì controller cần nó làm cache, dù về lý thuyết chạy được không có Redis [CT, `core.md`].
- **notifications-controller và applicationset-controller:** docs không có câu nào nói thẳng là xóa được khỏi `install.yaml`. Việc Core bỏ notification controller cho thấy nó không bắt buộc với GitOps engine **[SL]**. ApplicationSet controller vẫn có mặt cả trong Core **[CT]**.

## 7. Sealed Secrets v0.41.2

| Thành phần | Container | Request CPU / mem | Limit CPU / mem | Nguồn |
|---|---|---|---|---|
| `sealed-secrets-controller` (Deployment, 1) | `sealed-secrets-controller` | not set | not set | `controller.yaml` (release asset v0.41.2) [CT] |
| Như trên, qua Helm chart | | `requests: {}` | `limits: {}` | `helm/sealed-secrets/values.yaml` @v0.41.2 [CT] |

## 8. kube-prometheus-stack 93.2.2 (Prometheus 3.16.0)

Render bằng `helm template` với giá trị mặc định.

| Thành phần | Container | Request CPU / mem | Limit CPU / mem | Nguồn |
|---|---|---|---|---|
| Prometheus (CR `Prometheus`, 1 replica, retention 10d) | `prometheus` | not set | not set | `prometheus.prometheusSpec.resources: {}`. prometheus-operator không tự điền cho Prometheus (`pkg/prometheus/server/statefulset.go` @v0.95.2) [CT] |
| Prometheus và Alertmanager | `config-reloader` | not set | not set | Chart truyền `--config-reloader-{cpu,memory}-{request,limit}=0` khi `prometheusConfigReloader.resources` rỗng. Giá trị 0 nghĩa là không đặt. Mặc định riêng của operator là 10m / 50Mi nhưng bị chart ghi đè [CT, `templates/prometheus-operator/deployment.yaml`, `cmd/operator/main.go` @v0.95.2] |
| Alertmanager (CR, 1 replica) | `alertmanager` | memory **200Mi** (operator tự điền) | not set | `alertmanager.alertmanagerSpec.resources: {}`, nhưng `pkg/alertmanager/statefulset.go` đặt `requests.memory = 200Mi` nếu thiếu [CT] |
| prometheus-operator | `kube-prometheus-stack` | not set | not set | `prometheusOperator.resources: {}` [CT] |
| Admission webhook (2 Job hook một lần) | `create`, `patch` | not set | not set | `prometheusOperator.admissionWebhooks.patch.resources: {}` [CT] |
| kube-state-metrics v2.20.0 | `kube-state-metrics` | not set | not set | chart `kube-state-metrics-9.0.1` `resources: {}` [CT] |
| node-exporter v1.12.1 (DaemonSet) | `node-exporter` | not set | not set | chart `prometheus-node-exporter-5.1.0` `resources: {}` [CT] |
| Grafana 13.3.1 | `grafana` | not set | not set | chart `grafana-community/grafana` 14.4.1 `resources: {}`. Comment có ví dụ 100m / 128Mi cho cả request lẫn limit [CT] |
| Grafana | `grafana-sc-dashboard`, `grafana-sc-datasources` | not set | not set | `sidecar.resources: {}` [CT] |

Hướng dẫn chính thức của Prometheus về bộ nhớ:

- Docs `storage.md` @v3.16.0 chỉ có công thức **dung lượng đĩa**: trung bình 1–2 byte mỗi sample, và `needed_disk_space = retention_time_seconds * ingested_samples_per_second * bytes_per_sample` [CT]. **Không có con số RAM cho mỗi active series** trong docs chính thức **[CXM]**.
- `--auto-gomemlimit` mặc định `true`, `--auto-gomemlimit.ratio` mặc định `0.9`. Prometheus tự đặt `GOMEMLIMIT` bằng 90% memory limit của container, hoặc của hệ thống nếu container không có limit [CT, `docs/command-line/prometheus.md`].

## 9. Loki 3.7.9, Tempo 3.1.1, OTel Collector

### 9.1 Loki (chart `grafana-community/loki` 21.2.1, `deploymentMode: Monolithic`)

Chart từ chối render khi chưa có cấu hình storage, nên phải dùng override tối thiểu: `loki.storage.type: filesystem`, `commonConfig.replication_factor: 1`, schema v13/tsdb, `singleBinary.replicas: 1`, và `write/read/backend.replicas: 0` (validate của chart bắt buộc). Mọi giá trị resource để mặc định.

| Thành phần | Container | Request CPU / mem | Limit CPU / mem | Nguồn |
|---|---|---|---|---|
| `loki` (StatefulSet, single binary) | `loki` | not set | not set | `singleBinary.resources: {}` [CT] |
| `loki` | `loki-sc-rules` (sidecar) | not set | not set | `sidecar.resources: {}` [CT] |
| `loki-chunks-cache` (StatefulSet, `chunksCache.enabled: true`) | `memcached` | 500m / **9830Mi** | — / **9830Mi** | Render. `chunksCache.allocatedMemory: 8192` (MB). 9830 ≈ 8192 × 1,2 [CT render; hệ số 1,2 là SL] |
| `loki-chunks-cache` | `exporter` | not set | not set | `memcachedExporter.resources: {requests: {}, limits: {}}` [CT] |
| `loki-results-cache` (`resultsCache.enabled: true`) | `memcached` | 500m / 1229Mi | — / 1229Mi | Render. `resultsCache.allocatedMemory: 1024` [CT] |
| `loki-gateway` (Deployment, 1, `gateway.enabled: true`) | `nginx`, `exporter` | not set | not set | `gateway.resources: {}` [CT] |
| `loki-canary` (DaemonSet, `lokiCanary.enabled: true`) | `canary` | not set | not set | `lokiCanary.resources: {}` [CT] |

Comment trong `values.yaml` mô tả Monolithic là "useful for small installs typically without HA, up to a few tens of GB/day". Không tìm thấy khuyến nghị RAM chính thức cho chế độ monolithic **[CXM]**.

### 9.2 Tempo (chart `grafana-community/tempo` 3.2.1, monolithic)

| Thành phần | Container | Request CPU / mem | Limit CPU / mem | Nguồn |
|---|---|---|---|---|
| `tempo` (StatefulSet, 1) | `tempo` | not set | not set | `tempo.resources: {}` @`tempo-3.2.1`. Comment có ví dụ request 1000m / 4Gi, limit 2000m / 6Gi [CT] |
| `tempo-query` | — | (tắt: `tempoQuery.enabled: false`) | | [CT] |

### 9.3 OTel Collector (chart `opentelemetry-collector` 0.178.3, `mode: daemonset`)

Phải đặt `mode=daemonset` và `image.repository=otel/opentelemetry-collector-k8s` khi render, vì chart để trống hai giá trị này.

| Thành phần | Container | Request CPU / mem | Limit CPU / mem | Nguồn |
|---|---|---|---|---|
| `…-agent` (DaemonSet) | `opentelemetry-collector` (0.163.2) | not set | not set | `values.yaml` `resources: {}`. Comment: "It is HIGHLY recommended to set resource limits", ví dụ limit 250m / 512Mi [CT] |

Config mặc định của chart có processor `memory_limiter` với `limit_percentage: 80` và `spike_limit_percentage: 25` [CT, render]. Phần trăm này tính trên memory limit của container. Không có limit thì tính trên RAM của node **[SL]**.

## 10. Add-on của cụm

| Thành phần | Container | Request CPU / mem | Limit CPU / mem | Nguồn |
|---|---|---|---|---|
| Calico: `tigera-operator` (Deployment, 1) | `tigera-operator` (v1.44.0) | not set | not set | `manifests/tigera-operator.yaml` @v3.33.0 [CT] |
| Calico (cài bằng operator): `calico-node` (DaemonSet) | `calico-node` | not set | not set | `tigera/operator@v1.44.0` `pkg/render/node.go` `nodeResources()` → `GetResourceRequirements()` trả rỗng nếu `Installation` không khai báo [CT] |
| Calico (operator): `calico-typha` | `calico-typha` | not set | not set | `pkg/render/typha.go`, tương tự [CT] |
| Calico (operator): `calico-kube-controllers` | `calico-kube-controllers` | not set | not set | `pkg/render/kubecontrollers/kube-controllers.go`, tương tự [CT] |
| Calico (operator): `APIServer`, `Goldmane`, `Whisker` (có trong `custom-resources.yaml` mặc định) | — | not set | not set | Grep `pkg/render/{apiserver.go,goldmane/component.go,whisker/component.go}` không thấy `resource.MustParse` hay resource gán cứng **[CT, mức kiểm yếu]** |
| Calico (manifest `calico.yaml`, không dùng operator, để đối chiếu) | `calico-node` | cpu 250m / mem not set | not set | `manifests/calico.yaml` @v3.33.0 [CT] |
| MetalLB `controller` (Deployment) | `controller` | not set | not set | `config/manifests/metallb-native.yaml` @v0.16.2 [CT] |
| MetalLB `speaker` (DaemonSet) | `speaker` | not set | not set | như trên [CT] |
| metrics-server | `metrics-server` | 100m / 200Mi | not set | `components.yaml` (release v0.9.1) [CT] |
| local-path-provisioner | `local-path-provisioner` | not set | not set | `deploy/local-path-storage.yaml` @v0.0.37 [CT] |
| CoreDNS v1.14.6 (kubeadm, **2 replica**) | `coredns` | 100m / 70Mi | — / 170Mi | `cmd/kubeadm/app/phases/addons/dns/manifests.go`, `dns.go` (`coreDNSReplicas = 2`) @v1.37.2 [CT] |
| kube-apiserver (static pod) | `kube-apiserver` | 250m / not set | not set | `cmd/kubeadm/app/phases/controlplane/manifests.go` → `staticpodutil.ComponentResources("250m")`, chỉ đặt CPU [CT] |
| kube-controller-manager | `kube-controller-manager` | 200m / not set | not set | như trên [CT] |
| kube-scheduler | `kube-scheduler` | 100m / not set | not set | như trên [CT] |
| etcd 3.7.0-0 (static pod) | `etcd` | 100m / 100Mi | not set | `cmd/kubeadm/app/phases/etcd/local.go` [CT] |
| kube-proxy (DaemonSet do kubeadm cài) | `kube-proxy` | not set | not set | `cmd/kubeadm/app/phases/addons/proxy/manifests.go` không có khối `resources` [CT] |

Ghi chú:

- README metrics-server: request mặc định (100m, 200MiB) đủ cho "most cluster configurations up to 100 nodes". Mức tiêu thụ được nêu là "1 mili core of CPU and 2 MB of memory for each node" [CT, `README.md` @v0.9.1].
- Số replica Typha mà operator chọn cho cụm 3 node: comment trong `pkg/controller/installation/typha_autoscaler.go` ghi "at least (1 typha for every 200 nodes) + 1 but … cannot exceed the number of nodes+masters". Con số chính xác cho 3 node **[CXM]** vì không tìm được hàm `GetExpectedTyphaScale` ở các đường dẫn đã thử (`pkg/common/*.go`).
- Yêu cầu tối thiểu của kubeadm: "2 GB or more of RAM per machine", "2 CPUs or more for control plane machines" [CT, `kubernetes/website` `install-kubeadm.md`, nhánh `main`].

## 11. Định cỡ container JVM và Next.js

### 11.1 Spring Boot 4.1 / JDK 25

Spring Boot 4.1.2 dùng builder mặc định `paketobuildpacks/builder-noble-java-tiny:latest` cho `build-image` / `bootBuildImage` [CT, `build-image.adoc` và `packaging-oci-image.adoc` @v4.1.2]. Image do builder này tạo dùng **memory calculator** của Paketo (`libjvm`) để đặt cờ JVM theo memory limit của container:

| Vùng nhớ | Cờ JVM | Mặc định | Nguồn |
|---|---|---|---|
| Heap | `-Xmx` | `Tổng memory container − Non-Heap − Headroom` | Paketo Java reference [CT] |
| Headroom | — | 0% (`BPL_JVM_HEAD_ROOM`) | `helper/memory_calculator.go` `DefaultHeadroom = 0` @libjvm v1.46.0 [CT] |
| Direct memory | `-XX:MaxDirectMemorySize` | 10M | `calc/direct_memory.go` [CT] |
| Reserved code cache | `-XX:ReservedCodeCacheSize` | 240M | `calc/reserved_code_cache.go`. Khớp mặc định JDK 25 (240 MB khi bật tiered compilation) [CT] |
| Thread stack | `-Xss` | 1M × **250** thread (`BPL_JVM_THREAD_COUNT`) | `calc/stack.go`, `DefaultThreadCount = 250` [CT] |
| Metaspace | `-XX:MaxMetaspaceSize` | `14 000 000 + 5 800 × loadedClassCount` byte, với `loadedClassCount = 0,35 × tổng số class` (JVM + app + agent) | `calc/calculator.go` (`ClassOverhead`, `ClassSize`), `ClassLoadFactor = 0.35` [CT] |

Ghi chú:

- Docs Paketo: nếu Spring Boot buildpack phát hiện ứng dụng reactive (WebFlux), số thread giảm từ 250 xuống **50** [CT, `paketo-website` `content/docs/reference/java-reference.md`].
- Calculator báo lỗi và không khởi động nếu tổng vùng cố định lớn hơn memory của container [CT, `calc/calculator.go`]. Tổng vùng non-heap cố định, chưa tính metaspace, là 10M + 240M + 250 × 1M = **500 MiB** [SL, cộng tay].
- Trên Linux/AArch64, stack mặc định của JDK 25 là 2048 KB, trên Linux/x64 là 1024 KB [CT, JDK 25 `java` man page]. Calculator cố định 1M trừ khi đặt `-Xss`.
- Nếu không dùng buildpack, JDK 25 mặc định `-XX:MaxRAMPercentage=25`, tức heap tối đa bằng 25% memory mà JVM nhìn thấy [CT, JDK 25 `java` man page].
- Phiên bản `libjvm` đúng trong builder `builder-noble-java-tiny:latest` hiện tại **[CXM]**. Đã đọc `libjvm` v1.46.0, release mới nhất. Repo đã có tag `v2.0.0-alpha.1`.
- Spring Boot 4.1 không công bố memory tối thiểu cho một web service **[CXM: không tìm thấy]**.

### 11.2 Next.js (output standalone)

- Docs Next.js @v16.4.6 **không nêu RAM tối thiểu** cho server. Trang "Memory Usage" chỉ hướng dẫn giảm dependency, `webpackMemoryOptimizations`, debug memory khi build, và heap profile [CT, `docs/01-app/02-guides/memory-usage.mdx`].
- Cache trong RAM mặc định **50 MB** cho mỗi instance (`cacheMaxMemorySize`). Trên Kubernetes mỗi pod giữ một bản riêng. Docs gợi ý đặt `cacheMaxMemorySize: 0` và dùng cache handler ngoài [CT, `docs/01-app/02-guides/self-hosting.mdx` @v16.4.6].
- Trên Linux glibc, Image Optimization (sharp) có thể cần chỉnh memory allocator để tránh dùng quá nhiều bộ nhớ [CT, cùng file].

## Điểm chưa xác minh

1. Prometheus: không có con số RAM cho mỗi active series trong docs chính thức. Docs chỉ có định cỡ đĩa (1–2 byte/sample).
2. Apicurio Registry 3.3.4: không có khuyến nghị memory cho app. Chưa kiểm được `spec.ui.replicas: 0` có tắt UI hay không.
3. Loki monolithic và Tempo monolithic: không có khuyến nghị RAM chính thức. Tempo chỉ có ví dụ comment 4Gi/6Gi.
4. Số replica Typha cho cụm 3 node.
5. Calico `APIServer`/`Goldmane`/`Whisker`: "not set" mới kiểm bằng grep, chưa đọc toàn bộ code render.
6. Argo CD: docs không nói thẳng rằng xóa được notifications-controller hoặc applicationset-controller khỏi `install.yaml`. Kết luận về notifications là suy luận từ bản Core.
7. Phiên bản `libjvm` thực tế trong `paketobuildpacks/builder-noble-java-tiny:latest`.
8. Spring Boot 4.1 và Next.js 16.4: không có memory tối thiểu chính thức.

## Nguồn

Tất cả tra ngày 12/11/2026. File đọc ở đúng tag ghi kèm.

- Strimzi `strimzi/strimzi-kafka-operator@1.3.1`: `install/cluster-operator/060-Deployment-strimzi-cluster-operator.yaml`, `packaging/helm-charts/helm3/strimzi-kafka-operator/values.yaml`, `install/drain-cleaner/kubernetes/060-Deployment.yaml`, `cluster-operator/src/main/java/io/strimzi/operator/cluster/model/{EntityTopicOperator,EntityUserOperator}.java`, `documentation/modules/con-common-configuration-properties.adoc`, `documentation/modules/configuring/ref-kafka-entity-operator.adoc`, `packaging/examples/kafka/kafka-persistent.yaml`, `docker-images/operator/scripts/launch_java.sh`. `strimzi/drain-cleaner@1.8.0`: `packaging/install/kubernetes/060-Deployment.yaml`, `packaging/helm-charts/helm3/strimzi-drain-cleaner/values.yaml`. [Releases](https://github.com/strimzi/strimzi-kafka-operator/releases/tag/1.3.1).
- Apicurio `Apicurio/apicurio-registry@3.3.4`: `operator/install/apicurio-registry-operator-3.3.4.yaml`, `operator/controller/src/main/java/io/apicurio/registry/operator/resource/ResourceFactory.java`, `.../ApicurioRegistry3Reconciler.java`, `.../resource/ui/UIDeploymentResource.java`, `docs/modules/ROOT/pages/getting-started/assembly-operator-config-reference.adoc`, `assembly-deploying-registry-operator.adoc`, `assembly-installing-registry-docker.adoc`, `assembly-installing-registry-storage-openshift.adoc`. [Release 3.3.4](https://github.com/Apicurio/apicurio-registry/releases/tag/3.3.4).
- Keycloak: `keycloak/keycloak-k8s-resources@26.8.2` `kubernetes/kubernetes.yml`. [Release 26.8.2](https://github.com/keycloak/keycloak/releases/tag/26.8.2).
- CloudNativePG `cloudnative-pg/cloudnative-pg@v1.30.1`: `pkg/specs/pgbouncer/deployments.go`, `api/v1/pooler_funcs.go`, `api/v1/pooler_types.go`, `docs/src/connection_pooling.md`, release asset `cnpg-1.30.1.yaml`. Plugin `cloudnative-pg/plugin-barman-cloud@v0.16.0`: release asset `manifest.yaml`, `internal/cnpgi/operator/lifecycle.go`, `internal/cnpgi/operator/lifecycle_resources.go`, `web/docs/usage.md`.
- cert-manager `cert-manager/cert-manager@v1.21.3`: `deploy/charts/cert-manager/values.yaml`. [Releases](https://github.com/cert-manager/cert-manager/releases).
- Argo CD `argoproj/argo-cd@v3.6.1`: `manifests/install.yaml`, `manifests/core-install.yaml`, `docs/operator-manual/core.md`, `docs/operator-manual/installation.md`, `docs/operator-manual/user-management/index.md`, `docs/developer-guide/architecture/components.md`, `docs/operator-manual/high_availability.md`.
- Sealed Secrets `bitnami/sealed-secrets` (trước là `bitnami-labs/sealed-secrets`): release asset `controller.yaml` v0.41.2, `helm/sealed-secrets/values.yaml` @v0.41.2.
- kube-prometheus-stack: `prometheus-community/helm-charts@kube-prometheus-stack-93.2.2` `charts/kube-prometheus-stack/{values.yaml,Chart.yaml,templates/prometheus-operator/deployment.yaml}`, render bằng `helm template`. `kube-state-metrics-9.0.1` và `prometheus-node-exporter-5.1.0` `values.yaml`. `grafana-community/helm-charts@grafana-14.4.1` `charts/grafana/{values.yaml,Chart.yaml}`. `prometheus-operator/prometheus-operator@v0.95.2`: `cmd/operator/main.go`, `pkg/alertmanager/statefulset.go`, `pkg/prometheus/server/statefulset.go`. [Helm repo index](https://prometheus-community.github.io/helm-charts/index.yaml).
- Prometheus `prometheus/prometheus@v3.16.0`: `docs/storage.md`, `docs/command-line/prometheus.md`, `docs/feature_flags.md`.
- Loki và Tempo: `grafana-community/helm-charts@loki-21.2.1` `charts/loki/values.yaml`, `@tempo-3.2.1` `charts/tempo/values.yaml`. Chart OCI `ghcr.io/grafana-community/helm-charts/{loki:21.2.1,tempo:3.2.1}` render bằng `helm template`. [Helm repo index](https://grafana-community.github.io/helm-charts/index.yaml).
- OTel Collector: chart `opentelemetry-collector` 0.178.3 từ [open-telemetry Helm repo](https://open-telemetry.github.io/opentelemetry-helm-charts/index.yaml), render `mode=daemonset`. [Release collector v0.165.0](https://github.com/open-telemetry/opentelemetry-collector-releases/releases/tag/v0.165.0).
- Calico `projectcalico/calico@v3.33.0`: `manifests/tigera-operator.yaml`, `manifests/custom-resources.yaml`, `manifests/calico.yaml`. `tigera/operator@v1.44.0`: `pkg/render/node.go`, `pkg/render/typha.go`, `pkg/render/kubecontrollers/kube-controllers.go`, `pkg/render/common/meta/meta.go`, `pkg/render/apiserver.go`, `pkg/render/goldmane/component.go`, `pkg/render/whisker/component.go`, `pkg/controller/installation/typha_autoscaler.go`.
- MetalLB `metallb/metallb@v0.16.2` `config/manifests/metallb-native.yaml`.
- metrics-server: release asset `components.yaml` v0.9.1, `README.md` @v0.9.1.
- local-path-provisioner `rancher/local-path-provisioner@v0.0.37` `deploy/local-path-storage.yaml`.
- kubeadm `kubernetes/kubernetes@v1.37.2`: `cmd/kubeadm/app/phases/addons/dns/{manifests.go,dns.go}`, `cmd/kubeadm/app/phases/addons/proxy/manifests.go`, `cmd/kubeadm/app/phases/controlplane/manifests.go`, `cmd/kubeadm/app/util/staticpod/utils.go`, `cmd/kubeadm/app/phases/etcd/local.go`, `cmd/kubeadm/app/constants/constants.go`. [Installing kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/).
- JVM: `spring-projects/spring-boot@v4.1.2` `build-plugin/spring-boot-maven-plugin/src/docs/antora/modules/maven-plugin/pages/build-image.adoc`, `build-plugin/spring-boot-gradle-plugin/src/docs/antora/modules/gradle-plugin/pages/packaging-oci-image.adoc`. `paketo-buildpacks/libjvm@v1.46.0`: `helper/memory_calculator.go`, `calc/{calculator.go,direct_memory.go,reserved_code_cache.go,stack.go}`. [Paketo Java reference](https://paketo.io/docs/reference/java-reference/) (nguồn `paketo-buildpacks/paketo-website` `content/docs/reference/java-reference.md`). [JDK 25 `java` command](https://docs.oracle.com/en/java/javase/25/docs/specs/man/java.html).
- Next.js `vercel/next.js@v16.4.6`: `docs/01-app/02-guides/memory-usage.mdx`, `docs/01-app/02-guides/self-hosting.mdx`.
