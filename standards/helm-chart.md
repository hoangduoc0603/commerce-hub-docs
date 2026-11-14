# Chuẩn: Helm chart `app`

- Ngày tra: 2026-11-12; cập nhật 2026-11-13 theo ticket 16, [ADR-0013](../adr/0013-gateway-api-envoy-gateway-shared-edge.md) và [ADR-0014](../adr/0014-lab-pki-and-dns.md) (`HTTPRoute`, trust bundle, NetworkPolicy cho Envoy)
- Phiên bản áp dụng: Helm 4.3.1 (Helm 3.22.x vẫn nhận bản vá nhưng không còn bản minor), Kubernetes 1.37 (Helm 4.3 hỗ trợ 1.34–1.37), Argo CD 3.5+ (render bằng Helm v4), chart `apiVersion: v2`, Gateway API CRD v1.6.1 (`HTTPRoute` `gateway.networking.k8s.io/v1`), Envoy Gateway v1.10.0, trust-manager v0.26.0
- Phạm vi: chart dùng chung `platform/charts/app` (tên chốt ở ticket [11](../.scratch/architecture-g0-g1/issues/11-service-template.md#answer), dùng cho mọi workload kể cả `marketplace-sim` và `seller-web`), bản publish trên OCI registry, và cách repo `gitops` dùng chart đó. Cấu hình Argo CD xem [`gitops-argocd.md`](gitops-argocd.md); pipeline CI xem [`ci-cd.md`](ci-cd.md)

## Checklist

### Cấu trúc và metadata
- [ ] Cấu trúc: `Chart.yaml`, `values.yaml`, `values.schema.json`, `README.md`, `templates/` (`_helpers.tpl`, `deployment.yaml`, `service.yaml`, `serviceaccount.yaml`, `configmap.yaml`, `pdb.yaml`, `hpa.yaml`, `httproute.yaml`, `networkpolicy.yaml`, `NOTES.txt`), `ci/*-values.yaml` cho từng biến thể cần test. [Helm – Charts](https://helm.sh/docs/topics/charts/)
- [ ] `Chart.yaml` có `apiVersion: v2`, `type: application`, `kubeVersion: ">=1.35.0-0"`. Helm từ chối cài lên cụm ngoài khoảng hỗ trợ thay vì để lỗi xuất hiện lúc chạy. [Helm – Charts: kubeVersion](https://helm.sh/docs/topics/charts/#the-kubeversion-field)
- [ ] `version` theo SemVer 2 và tăng mỗi lần chart đổi: MAJOR khi đổi tên/xóa/đổi nghĩa một value, MINOR khi thêm value có mặc định giữ hành vi cũ, PATCH khi sửa lỗi template. `appVersion` độc lập với `version` và không ảnh hưởng cách tính version. [Helm – Charts: version, appVersion](https://helm.sh/docs/topics/charts/#charts-and-versioning)
- [ ] Chart dùng chung cho nhiều service nên `appVersion` không quyết định image chạy; image lấy từ `values.image` do `gitops` cung cấp. Tránh hiểu nhầm `appVersion` là phiên bản service. [Helm – Charts: appVersion](https://helm.sh/docs/topics/charts/#the-appversion-field)

### Values và schema
- [ ] Tên value dạng camelCase, ưu tiên cấu trúc phẳng, dùng map thay cho list khi người dùng cần ghi đè bằng `--set`. Mỗi value có comment bắt đầu bằng tên của nó. [Helm – Values best practices](https://helm.sh/docs/chart_best_practices/values/)
- [ ] Có `values.schema.json` (JSON Schema draft-07) với `required` cho `image.repository`, `image.digest`, `resources`; `additionalProperties: false` ở các object cấp cao để bắt lỗi gõ sai tên key. Helm kiểm schema khi `install`, `upgrade`, `lint`, `template`. [Helm – Charts: Schema files](https://helm.sh/docs/topics/charts/#schema-files)
- [ ] Image tham chiếu theo digest: template sinh `{{ repository }}@{{ digest }}`, `tag` chỉ để đọc. Kubernetes chạy đúng một bản image mỗi lần khi có digest. [Kubernetes – Images](https://kubernetes.io/docs/concepts/containers/images/#image-names)
- [ ] Value bắt buộc mà schema không diễn tả được thì dùng `required` trong template, kèm thông điệp lỗi rõ. [Helm – Tips: required](https://helm.sh/docs/howto/charts_tips_and_tricks/#using-the-required-function)

### Labels
- [ ] Mọi resource có `app.kubernetes.io/name`, `app.kubernetes.io/instance`, `app.kubernetes.io/managed-by`, `helm.sh/chart`, và `app.kubernetes.io/version`, `app.kubernetes.io/component`, `app.kubernetes.io/part-of: commerce-hub`, sinh từ một helper trong `_helpers.tpl`. Đây là bộ nhãn chung để công cụ và người vận hành truy vấn. [Helm – Labels](https://helm.sh/docs/chart_best_practices/labels/), [Kubernetes – Recommended labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/)
- [ ] `selector.matchLabels` chỉ gồm `app.kubernetes.io/name` và `app.kubernetes.io/instance`. Selector của Deployment không đổi được sau khi tạo, nên không đưa `version` hay `helm.sh/chart` vào. [Kubernetes – Deployments: Selector](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#selector)

### Tài nguyên và JVM
- [ ] `resources.requests` cho CPU và memory là bắt buộc (schema), và `limits.memory` = `requests.memory`. Scheduler xếp pod theo requests; vượt memory limit thì container bị OOM kill. [Kubernetes – Resource management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [ ] Mặc định không đặt `limits.cpu`. CPU limit được thực thi bằng throttling, làm chậm JVM lúc khởi động và lúc GC. Nếu bỏ CPU limit thì đặt `-XX:ActiveProcessorCount` trong `JAVA_TOOL_OPTIONS` để JVM không tính thread pool theo số CPU của node. [Kubernetes – Resource management: CPU limits](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/#how-pods-with-resource-limits-are-run), [JDK 25 – java: -XX:ActiveProcessorCount](https://docs.oracle.com/en/java/javase/25/docs/specs/man/java.html)
- [ ] `JAVA_TOOL_OPTIONS` có mặc định `-XX:MaxRAMPercentage=75` và ghi đè được qua values (xem [`container-image.md`](container-image.md)). Khi `trust.enabled`, chart nối thêm cờ truststore (mục Trust bundle), không để values ghi đè làm mất cờ này.

### Bảo mật pod (Pod Security Standards "restricted")
- [ ] Pod: `securityContext.runAsNonRoot: true`, `runAsUser`/`runAsGroup`/`fsGroup` khác 0, `seccompProfile.type: RuntimeDefault`. Container: `allowPrivilegeEscalation: false`, `capabilities.drop: ["ALL"]`. Đây là các trường profile Restricted bắt buộc. [Kubernetes – Pod Security Standards: Restricted](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted)
- [ ] Thêm `readOnlyRootFilesystem: true` và một `emptyDir` mount tại `/tmp`. Không nằm trong Restricted, nhưng chặn ghi đè file trong container. [Kubernetes – Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [ ] Chỉ dùng volume `configMap`, `secret`, `emptyDir`, `projected`, `downwardAPI`, `persistentVolumeClaim`; không `hostPath`, `hostPort`, `hostNetwork`. [Kubernetes – Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [ ] Namespace của service có nhãn `pod-security.kubernetes.io/enforce: restricted` (nhãn đặt ở `gitops`, không ở chart). Pod Security Admission từ chối pod vi phạm ngay khi tạo. [Kubernetes – Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)

### ServiceAccount
- [ ] Mỗi release có ServiceAccount riêng (`serviceAccount.create: true`), `automountServiceAccountToken: false` khi service không gọi Kubernetes API. Không gắn token vào pod thì lộ pod không lộ quyền gọi API. [Kubernetes – Configure Service Accounts: opt out of automounting](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/#opt-out-of-api-credential-automounting)

### Probe, rollout, PDB, phân tán
- [ ] Deployment có `startupProbe`, `readinessProbe`, `livenessProbe` trỏ vào nhóm health của Actuator, `strategy.rollingUpdate`, `minReadySeconds`, `lifecycle.preStop.sleep`, `terminationGracePeriodSeconds`; giá trị và lý do ở [`zero-downtime.md`](zero-downtime.md). [Kubernetes – Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- [ ] Render `PodDisruptionBudget` với `maxUnavailable: 1` khi `replicaCount >= 2` hoặc HPA bật; không render khi chỉ 1 replica (PDB với 1 replica vẫn cho phép mất 100%). Dùng `maxUnavailable` vì nó chạy đúng khi số replica thay đổi. [Kubernetes – Configure PDB](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)
- [ ] PDB đặt `unhealthyPodEvictionPolicy: AlwaysAllow`. Mặc định `IfHealthyBudget` để pod `CrashLoopBackOff` chặn `kubectl drain`. [Kubernetes – Configure PDB: Unhealthy Pod Eviction Policy](https://kubernetes.io/docs/tasks/run-application/configure-pdb/#unhealthy-pod-eviction-policy)
- [ ] `topologySpreadConstraints` theo `kubernetes.io/hostname`, `maxSkew: 1`, `whenUnsatisfiable: ScheduleAnyway`, `matchLabelKeys: [pod-template-hash]`. Rải replica qua 3 node; `pod-template-hash` để chỉ tính pod cùng revision trong lúc rolling update. [Kubernetes – Topology spread constraints](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/)

### `HTTPRoute` (cửa vào cụm)
- [ ] Chart sinh `HTTPRoute`, **không sinh `Ingress`** ([ADR-0013](../adr/0013-gateway-api-envoy-gateway-shared-edge.md)). Values `httpRoute.*`: `enabled` (mặc định `false`), `hostnames` (nhiều hostname được, ví dụ `marketplace-sim`), `servicePort` (chỉ port chính; schema cấm port admin và port quản trị 8081), `parentRef` (mặc định `{name: edge, namespace: edge, sectionName: https}`), `timeouts`. Kubernetes khuyên dùng Gateway thay Ingress vì "The Ingress API has been frozen". [Kubernetes – Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/), [`cluster-entry.md`](cluster-entry.md#httproute-trong-chart-app)
- [ ] Hostname khớp `*.lab.internal` và chỉ có một nhãn bên trái (wildcard của listener chỉ phủ một nhãn); schema kiểm bằng `pattern`. Chart không tạo `Gateway`, `GatewayClass`, `BackendTLSPolicy`, chứng chỉ: những thứ đó thuộc app `platform`. [`cluster-entry.md`](cluster-entry.md#gateway-edge-và-sở-hữu)
- [ ] Route chỉ gắn được khi namespace có nhãn `edge.lab.internal/routes: "true"` do `platform` gắn (`allowedRoutes.namespaces.from: Selector`). Route sai không làm sync lỗi mà chỉ không `Accepted`, nên `ct install` phải kiểm `status.conditions` của route. [Gateway API – Cross-namespace routing](https://gateway-api.sigs.k8s.io/guides/user-guides/multiple-ns/)

### NetworkPolicy
- [ ] Chart render NetworkPolicy theo app: ingress theo danh sách cho phép (`ingress.from` theo nhãn app/namespace) ([ticket 11](../.scratch/architecture-g0-g1/issues/11-service-template.md#answer)). Khi `httpRoute.enabled`, chart tự thêm nguồn là pod Envoy: `namespaceSelector` `kubernetes.io/metadata.name: envoy-gateway-system` và `podSelector` `app.kubernetes.io/name: envoy`, `app.kubernetes.io/component: proxy`, `app.kubernetes.io/managed-by: envoy-gateway`, chỉ tới `servicePort`. Proxy của Envoy Gateway chạy trong namespace của controller. [Envoy Gateway – Deployment mode](https://gateway.envoyproxy.io/docs/tasks/operations/deployment-mode/), [`cluster-entry.md`](cluster-entry.md#httproute-trong-chart-app)

### Trust bundle (CA của lab)
- [ ] `trust.enabled` mặc định `true`: mount vào `/etc/trust/` một volume `projected` gộp hai ConfigMap do trust-manager đồng bộ vào namespace: `lab-trust` (key `bundle.p12`, cho JVM) và `lab-root` (key `ca.crt`, mount thành `lab-root-ca.pem` bằng `items.path`, cho Node). Một `Bundle` chỉ ghi được một key PEM nên phải hai `Bundle` (G0-07). Volume `projected`/`configMap` hợp PSS restricted và `readOnlyRootFilesystem`. Namespace của service phải mang nhãn `trust.lab.internal/inject: "true"` (do `platform` gắn). [`cluster-entry.md`](cluster-entry.md#phân-phối-trust), [ADR-0014](../adr/0014-lab-pki-and-dns.md)
- [ ] Không đặt `optional: true` cho hai nguồn ConfigMap. Thiếu ConfigMap thì pod kẹt `ContainerCreating`, lỗi lộ ngay. Nếu cho phép thiếu, JDK 25 thấy file truststore không tồn tại sẽ **lặng lẽ quay về `cacerts`** (chỉ log ở mức DEBUG): host công khai vẫn chạy, chỉ host `*.lab.internal` lỗi `PKIX`. Đo ở G0-07 ([bản ghi](../experiments/2026-11-g0.md#6-phân-phối-trust-bằng-trust-manager-jvm-node-hairpin-name-constraints)).
- [ ] Workload JVM: thêm `-Djavax.net.ssl.trustStore=/etc/trust/bundle.p12 -Djavax.net.ssl.trustStoreType=PKCS12` vào `JAVA_TOOL_OPTIONS`, để mọi HTTP client và `JwtDecoder` tin CA lab mà không sửa code. Không đặt `trustStorePassword`: `Bundle` để mật khẩu rỗng, trust-manager ghi PKCS12 không mã hóa và JDK 25 đọc được. Nếu sau này `Bundle` có mật khẩu thì cờ mật khẩu là bắt buộc; thiếu thì JDK nạp store rỗng và mọi TLS hỏng (`the trustAnchors parameter must be non-empty`). [JSSE Reference Guide (JDK 25)](https://docs.oracle.com/en/java/javase/25/security/java-secure-socket-extension-jsse-reference-guide.html), [bản ghi G0-07](../experiments/2026-11-g0.md#6-phân-phối-trust-bằng-trust-manager-jvm-node-hairpin-name-constraints)
- [ ] Workload Node (`seller-web`): đặt `NODE_EXTRA_CA_CERTS=/etc/trust/lab-root-ca.pem` (chỉ root lab, không trỏ vào gói CA công khai: biến này chỉ thêm root, không bớt). Biến chỉ đọc lúc process khởi động; file thiếu thì Node chỉ in một cảnh báo và chạy tiếp. `fetch` (undici) của Node 24 và 26 đọc biến này (G0-07). [Node.js CLI](https://nodejs.org/api/cli.html)
- [ ] Không dùng SSL bundle của Spring Boot cho từng client, không dùng init container chạy `keytool`. [Spring Boot – SSL](https://docs.spring.io/spring-boot/reference/features/ssl.html), [ADR-0014](../adr/0014-lab-pki-and-dns.md)

### ConfigMap, Secret
- [ ] Cấu hình không bí mật đưa vào ConfigMap do chart render; pod template có annotation `checksum/config: {{ include (print $.Template.BasePath "/configmap.yaml") . | sha256sum }}`. Đổi config thì pod được rollout lại. [Helm – Tips: Automatically roll deployments](https://helm.sh/docs/howto/charts_tips_and_tricks/#automatically-roll-deployments)
- [ ] Chart không chứa giá trị bí mật; chỉ tham chiếu Secret có sẵn qua `existingSecret`. Checksum không thấy Secret ngoài chart, nên đổi Secret cần một cơ chế rollout riêng (ghi ở [`gitops-argocd.md`](gitops-argocd.md)).
- [ ] Không dùng `randAlphaNum` hay annotation `rollme` ngẫu nhiên. Argo CD render bằng `helm template`, giá trị ngẫu nhiên làm app luôn `OutOfSync`. [Argo CD – Helm](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/)

### HPA
- [ ] `autoscaling.enabled` mặc định `false`. Khi bật: render `autoscaling/v2` HPA, **không** render `spec.replicas` trong Deployment. Có `spec.replicas` thì mỗi lần sync sẽ đặt lại số replica, giằng co với HPA. [Kubernetes – HPA: Migrating Deployments](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/#migrating-deployments-and-statefulsets-to-horizontal-autoscaling)
- [ ] HPA theo CPU yêu cầu container có CPU request (đã bắt buộc ở schema); giữ cửa sổ ổn định scale-down mặc định 300 s. [Kubernetes – HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/)

### Kiểm tra
- [ ] `helm lint --strict` với từng file `ci/*-values.yaml`. [Helm – helm lint](https://helm.sh/docs/helm/helm_lint/)
- [ ] `helm template` với từng file `ci/*-values.yaml`, chuyển qua `kubeconform -strict -summary -kubernetes-version 1.37.0`. Bắt field sai schema API trước khi lên cụm. **Chưa xác minh**: kho schema mặc định của kubeconform đã có bản 1.37 chưa; nếu chưa, dùng bản mới nhất có sẵn và ghi lại. [kubeconform](https://github.com/yannh/kubeconform)
- [ ] `ct lint` và `ct install` (chart-testing) trên cụm thử. Cài thật từng biến thể values và chờ pod Ready. [chart-testing](https://github.com/helm/chart-testing)
- [ ] Test âm cho schema: value sai kiểu hoặc thiếu `image.digest` phải làm `helm template` thất bại; hostname ngoài `*.lab.internal` hoặc `servicePort` là 8081 cũng phải thất bại.
- [ ] kubeconform cần schema của CRD Gateway API v1.6.1 để kiểm `HTTPRoute`; schema mặc định chỉ có resource gốc của Kubernetes. Thêm `-schema-location` trỏ tới schema sinh từ CRD v1.6.1, không dùng `-ignore-missing-schemas` cho kind này. [kubeconform](https://github.com/yannh/kubeconform)
- [ ] `kubectl label --dry-run=server --overwrite ns <ns> pod-security.kubernetes.io/enforce=restricted` không in cảnh báo nào sau khi cài chart. [Kubernetes – Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/)

### Publish OCI
- [ ] `helm package` rồi `helm push app-<version>.tgz oci://10.20.0.5:5000/charts` (thêm `--plain-http` ở lab). Tên chart là tên repository, version là tag. [Helm – Registries](https://helm.sh/docs/topics/registries/), [helm push](https://helm.sh/docs/helm/helm_push/)
- [ ] Version đã push thì không push lại với nội dung khác; CI chặn khi tag đã tồn tại. Chart version là định danh bất biến giống image tag.
- [ ] `gitops` tham chiếu chart bằng version cụ thể (không range); digest chart ghi kèm trong comment để đối chiếu. [Helm – Registries (digest)](https://helm.sh/docs/topics/registries/)

## Lựa chọn và phương án đã loại

| Quyết định | Chọn | Loại | Lý do | Nguồn |
|---|---|---|---|---|
| Kiểu chart | Một chart `app` dùng chung, mỗi service một release | Chart riêng mỗi service; library chart + chart mỏng mỗi service | Ít trùng lặp, đổi chuẩn một chỗ. Library chart linh hoạt hơn nhưng thêm một tầng phải version | [Helm – Charts: type](https://helm.sh/docs/topics/charts/#chart-types) |
| Phân phối chart | OCI registry | Chart repository HTTP (`index.yaml`) | Helm khuyên OCI; dùng chung registry với image | [Helm – Registries](https://helm.sh/docs/topics/registries/) |
| Ngưỡng PDB | `maxUnavailable: 1` | `minAvailable` | Chạy đúng khi HPA đổi số replica | [Configure PDB](https://kubernetes.io/docs/tasks/run-application/configure-pdb/) |
| Phân tán pod | `topologySpreadConstraints`, `ScheduleAnyway` | `podAntiAffinity` bắt buộc; `DoNotSchedule` | Chỉ 3 node; `DoNotSchedule` có thể làm pod surge Pending khi một node đầy RAM | [Topology spread](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/) |
| CPU limit | Không đặt mặc định | Đặt CPU limit = request | Throttling làm chậm khởi động JVM; vẫn có memory limit | [Resource management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/) |
| Schema | JSON Schema draft-07 | draft 2020-12 | Draft-07 chắc chắn chạy trên Helm 3 và 4 | [Helm – Schema files](https://helm.sh/docs/topics/charts/#schema-files) |
| Cửa vào ([ADR-0013](../adr/0013-gateway-api-envoy-gateway-shared-edge.md)) | Chart sinh `HTTPRoute` gắn vào Gateway `edge` dùng chung | Sinh `Ingress`; mỗi app tự tạo Gateway hoặc ListenerSet | Ingress đã đóng băng, `ingress-nginx` không còn bản vá; TLS tập trung ở `edge`, app không đụng chứng chỉ | [Kubernetes – Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/), [`cluster-entry.md`](cluster-entry.md) |
| Tin CA lab ([ADR-0014](../adr/0014-lab-pki-and-dns.md)) | Truststore PKCS12 toàn JVM từ trust-manager; `NODE_EXTRA_CA_CERTS` cho Node | SSL bundle của Spring Boot cho từng client; init container `keytool` | Không sửa code, không sót `JwtDecoder`; init container thêm image và bước chạy | [Spring Boot – SSL](https://docs.spring.io/spring-boot/reference/features/ssl.html), [trust-manager](https://cert-manager.io/docs/trust/trust-manager/) |

## Lệch chuẩn có chủ đích ở home lab

- **Chart trên docker-registry 2.8 không TLS, không auth** (`--plain-http`). Docs Helm ghi Docker Registry chỉ hợp cho thử nghiệm cục bộ. Chấp nhận vì registry chỉ trong lab/tailnet. Cách Argo CD kéo chart từ registry HTTP thuộc [`gitops-argocd.md`](gitops-argocd.md).
- **Chart giữ `replicaCount: 2` mặc định**, không phải 3. Values của môi trường lab trong `gitops` đặt `replicaCount: 1` và memory 512Mi; chỉ tăng khi làm thí nghiệm ([ADR-0004](../adr/0004-single-instance-by-default-on-homelab.md), ngân sách ở [ticket 04](../.scratch/architecture-g0-g1/issues/04-resource-budget.md#answer)). Với 1 replica chart không render PDB.
- **`ScheduleAnyway` thay cho `DoNotSchedule`.** 3 node, trong đó control plane cũng nhận pod; ưu tiên rollout chạy được hơn rải tuyệt đối.
- **Không ký chart** (`helm-sigstore`) vì lý do giống image, xem [`container-image.md`](container-image.md).

## Bằng chứng cần có

| Số đo | Lệnh | Tiêu chí |
|---|---|---|
| Lint | `helm lint --strict charts/app -f charts/app/ci/<f>.yaml` | 0 lỗi, 0 cảnh báo, mọi file `ci/` |
| Schema API | `helm template t charts/app -f ci/<f>.yaml \| kubeconform -strict -summary -kubernetes-version 1.37.0` | `Invalid: 0, Errors: 0` |
| Schema values | `helm template t charts/app --set image.digest=` | Thất bại, có thông báo lỗi schema |
| PSS restricted | `kubectl label --dry-run=server --overwrite ns <ns> pod-security.kubernetes.io/enforce=restricted` | Không có `Warning:` |
| Cài thật | `ct install --charts charts/app` | Mọi biến thể pass |
| Rải pod | `kubectl get pod -l app.kubernetes.io/instance=<rel> -o wide` | Replica nằm trên các node khác nhau |
| Publish | `helm show chart oci://10.20.0.5:5000/charts/app --version <v> --plain-http` | Trả đúng `Chart.yaml` |
| HTTPRoute gắn được | `ct install` với `ci/httproute-values.yaml`; `kubectl get httproute -n <ns> -o jsonpath='{.items[*].status.parents[*].conditions}'` | `Accepted`, `ResolvedRefs` là `True`; `curl https://<host>.lab.internal` qua `edge` trả 200 |
| NetworkPolicy cho Envoy | Gọi `servicePort` từ một pod lạ trong namespace khác | Bị chặn; gọi qua `edge` vẫn thành công |
| Truststore JVM | Theo bảng bằng chứng "Trust ở JVM" của [`cluster-entry.md`](cluster-entry.md#bằng-chứng-cần-có) | Có mount thì gọi `https://*.lab.internal` OK; bỏ mount thì lỗi `PKIX` |
| Rollout theo config | Sửa một key ConfigMap trong `gitops`, sync | Pod mới được tạo, chạy tải không lỗi (đo theo [`zero-downtime.md`](zero-downtime.md)) |

## Nguồn

- Helm 4.3.1: [Charts](https://helm.sh/docs/topics/charts/), [Values](https://helm.sh/docs/chart_best_practices/values/), [Labels](https://helm.sh/docs/chart_best_practices/labels/), [Tips and tricks](https://helm.sh/docs/howto/charts_tips_and_tricks/), [Registries](https://helm.sh/docs/topics/registries/), [helm push](https://helm.sh/docs/helm/helm_push/), [helm lint](https://helm.sh/docs/helm/helm_lint/), [Version skew](https://helm.sh/docs/topics/version_skew/), [Releases](https://github.com/helm/helm/releases)
- Kubernetes 1.37: [Recommended labels](https://kubernetes.io/docs/concepts/overview/working-with-objects/common-labels/), [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/), [Resource management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/), [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/), [Pod Security Admission](https://kubernetes.io/docs/concepts/security/pod-security-admission/), [Service accounts](https://kubernetes.io/docs/tasks/configure-pod-container/configure-service-account/), [Configure PDB](https://kubernetes.io/docs/tasks/run-application/configure-pdb/), [Topology spread](https://kubernetes.io/docs/concepts/scheduling-eviction/topology-spread-constraints/), [HPA](https://kubernetes.io/docs/tasks/run-application/horizontal-pod-autoscale/), [Images](https://kubernetes.io/docs/concepts/containers/images/), [Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)
- Công cụ: [chart-testing](https://github.com/helm/chart-testing), [kubeconform](https://github.com/yannh/kubeconform), [Argo CD – Helm](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/)
- [JDK 25 – java command](https://docs.oracle.com/en/java/javase/25/docs/specs/man/java.html), [JSSE Reference Guide (JDK 25)](https://docs.oracle.com/en/java/javase/25/security/java-secure-socket-extension-jsse-reference-guide.html), [Node.js CLI](https://nodejs.org/api/cli.html), [Spring Boot – SSL](https://docs.spring.io/spring-boot/reference/features/ssl.html)
- Cửa vào và trust: [Kubernetes – Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/), [Gateway API – Cross-namespace routing](https://gateway-api.sigs.k8s.io/guides/user-guides/multiple-ns/), [Envoy Gateway – Deployment mode](https://gateway.envoyproxy.io/docs/tasks/operations/deployment-mode/), [trust-manager](https://cert-manager.io/docs/trust/trust-manager/); chi tiết ở [`cluster-entry.md`](cluster-entry.md)
