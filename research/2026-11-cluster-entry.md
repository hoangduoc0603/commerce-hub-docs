# Cửa vào cụm home lab: Gateway API, implementation, TLS, domain lab, hostname, Mailpit

Tra cứu ngày 13/11/2026 cho ticket [16 Cửa vào cụm](../.scratch/architecture-g0-g1/issues/16-cluster-entry.md). Bối cảnh: cụm kubeadm Kubernetes 1.37, 3 node, Calico v3.33.0, MetalLB v0.16.2 chế độ L2 (dải `10.20.0.200–250`), kube-proxy chế độ iptables. VM `gw` (`10.20.0.5`) là Tailscale subnet router quảng bá `10.20.0.0/24`, MacBook vào lab qua Tailscale ([homelab](../../platform/docs/homelab-hyperv.md)). cert-manager đã có từ ticket 03 (plugin Barman Cloud cần). Ngân sách RAM còn dư khoảng 1 GiB ([ADR-0004](../adr/0004-single-instance-by-default-on-homelab.md), ticket 04). Gateway của dự án (Spring Cloud Gateway, service `gateway`) là ClusterIP và chỉ nhận traffic từ `seller-web` ([ADR-0011](../adr/0011-nextjs-bff-with-server-side-session.md)).

Phiên bản lấy từ GitHub Releases API và trang release chính thức. Conformance lấy từ file report trong `kubernetes-sigs/gateway-api/conformance/reports/`. Số RAM của Envoy Gateway lấy từ `benchmark_result.json` đính kèm release v1.10.0.

Nhãn: **[CT]** tài liệu, mã nguồn hoặc artifact chính thức · **[CXM]** chưa xác minh · **[SL]** suy luận của người viết, chưa có nguồn nói thẳng.

Để tránh nhầm với service `gateway` của dự án, tài liệu này gọi resource `Gateway` của Gateway API là **Gateway `edge`**, và gọi cả lớp này là **cửa vào cụm**.

## Tóm tắt

- **Gateway API, không dùng Ingress.** Docs Kubernetes 1.37 ghi "The Ingress API has been frozen" và khuyên dùng Gateway. `ingress-nginx` đã ngừng phát triển sau tháng 03/2026, không còn bản vá bảo mật.
- **Implementation: Envoy Gateway v1.10.0** (06/11/2026). Đây là bản duy nhất của Envoy Gateway liệt kê hỗ trợ Kubernetes 1.37 (dải v1.34–v1.37), đi với Gateway API v1.6.1. Report conformance (v1.9.0, Gateway API v1.6.1) pass toàn bộ core và extended của ba profile HTTP, TLS, gRPC, có `BackendTLSPolicy`, `BackendTLSPolicySANValidation`, `ListenerSet`, timeout và retry của HTTPRoute. Benchmark chính thức của v1.10.0 với 10 HTTPRoute: controller tối đa khoảng 134 MiB, Envoy proxy khoảng 18 MiB. Mặc định chart lại đặt 256 Mi request và 1 024 Mi limit cho controller, 512 Mi cho Envoy, nên phải tự đặt limit.
- **Phương án đã loại:** Istio (istiod mặc định request 2 048 Mi), NGINX Gateway Fabric 2.8.1 (không hỗ trợ timeout và retry của HTTPRoute, không kiểm SAN ở BackendTLSPolicy), Traefik 3.7.18 (core HTTP chỉ "partial", không có `ListenerSet`, timeout, retry), kgateway 2.5.1 (khả thi, nhưng không có cam kết nào về K8s 1.37 và không nhẹ hơn), HAProxy Kubernetes Ingress Controller (chỉ có TCPRoute), Cilium (CNI là Calico).
- **Sở hữu:** app `platform` trong `gitops` cài Gateway API CRD (standard channel v1.6.1), Envoy Gateway, `GatewayClass`, Gateway `edge`, chứng chỉ wildcard và route chuyển HTTP sang HTTPS. Chart `app` sinh **`HTTPRoute`** trong namespace của app. Namespace được gắn route khi mang nhãn do `platform` đặt (`allowedRoutes.namespaces.from: Selector`). Không cần `ReferenceGrant`, vì route và Service cùng namespace, Secret chứng chỉ cùng namespace với Gateway.
- **TLS:** CA nội bộ hai tầng. Root CA tạo offline trên Mac, có name constraints, khóa không vào cụm. Intermediate CA nằm trong cụm dưới dạng Sealed Secret, cấp cho `ClusterIssuer` kiểu CA của cert-manager. Không dùng ACME, vì `.internal` không có chủ trên DNS công cộng. Trình duyệt tin root qua Keychain hệ thống của macOS. JVM tin qua truststore PKCS12 do trust-manager v0.26.0 sinh, nạp bằng `-Djavax.net.ssl.trustStore`. Node tin qua `NODE_EXTRA_CA_CERTS`. Keycloak dùng TLS re-encrypt bằng `BackendTLSPolicy` `gateway.networking.k8s.io/v1`, GA từ Gateway API v1.4.0.
- **Domain:** `lab.internal`. ICANN đã giữ `.INTERNAL` cho dùng riêng từ 29/07/2024. Không dùng `.local`, vì RFC 6762 dành nó cho mDNS. Phân giải bằng dnsmasq trên `gw`, trả `*.lab.internal → 10.20.0.200` (IP MetalLB cố định của Gateway `edge`). Mac dùng split DNS của Tailscale, `lab.internal` trỏ về `10.20.0.5`. Pod dùng một server block trong CoreDNS chuyển `lab.internal` về `10.20.0.5`.
- **Hostname:** G0–G1 có `app.`, `auth.`, `shopee-sim.`, cộng hostname vận hành `argocd.`, `grafana.`, `kc-admin.`. Từ G2 thêm `tiktok-sim.` và `webhooks.`. Mailpit không đi qua Gateway.
- **Mailpit v1.33.1 chạy trên `gw`** dạng binary cùng systemd. arc42 đã vẽ Mailpit là hệ thống ngoài, nên nó không tốn RAM của cụm. Docs Mailpit đo khoảng 50 MB RAM sau khi nhận 2 500 email khi tắt nén.
- **RAM thêm vào cụm** khoảng 480 MiB (limit tự đặt): controller 256, Envoy 128, shutdown-manager 32, trust-manager 64. Phần dư của ADR-0004 còn khoảng 520 MiB **[SL, phải đo ở G0]**.

---

## 1. Gateway API hay Ingress

- Trang Ingress của Kubernetes (bản docs v1.37) ghi: "The Kubernetes project recommends using Gateway instead of Ingress. The Ingress API has been frozen." Ingress vẫn GA và "has no plans to remove", nhưng "no longer being developed". [CT, [kubernetes.io – Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/)]
- `ingress-nginx`: "Best-effort maintenance will continue until March 2026. Afterward, there will be no further releases, no bugfixes, and no updates to resolve any security vulnerabilities". SIG Network và Security Response Committee khuyên chuyển "to Gateway API or another Ingress controller immediately". [CT, [Kubernetes blog 11/11/2025](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/)]. Homelab ghi ngày archive là 24/03/2026, trang Ingress của Argo CD cũng ghi như vậy.
- Gateway API mới nhất là **v1.7.0** (29/10/2026). Trước đó có v1.6.3 (06/10/2026) và v1.6.1 (16/07/2026) [CT, GitHub Releases API]. v1.5.0 (27/02/2026) đưa `TLSRoute` và `ListenerSet` lên Standard dưới `v1` [CT, [Kubernetes blog – Gateway API v1.5](https://kubernetes.io/blog/2026/04/21/gateway-api-v1-5/)]. `BackendTLSPolicy` "is GA and has been part of the Standard Channel since v1.4.0" [CT, [Gateway API – TLS guide](https://gateway-api.sigs.k8s.io/guides/tls/)].
- Bundle `standard-install.yaml` v1.6.1 có các CRD `gatewayclasses`, `gateways`, `httproutes`, `grpcroutes`, `tlsroutes`, `tcproutes`, `udproutes`, `listenersets`, `referencegrants`, `backendtlspolicies`, cùng một ValidatingAdmissionPolicy `safe-upgrades`. `backendtlspolicies` chỉ còn phục vụ `v1` (`v1alpha3` có `served: false`). [CT, file release v1.6.1]

**Kết luận:** dùng Gateway API. Ingress không có `BackendTLSPolicy` chuẩn (re-encrypt tới Keycloak phải qua annotation riêng của từng controller), không có timeout chuẩn cho SSE ở G2, và không có mô hình chia vai Gateway/route.

## 2. Chọn implementation

### 2.1 So sánh

| Tiêu chí | **Envoy Gateway** | NGINX Gateway Fabric | Traefik Proxy | kgateway | Istio (gateway) | HAProxy |
|---|---|---|---|---|---|---|
| Bản mới nhất (13/11/2026) | **v1.10.0** (06/11/2026) [CT] | 2.8.1 [CT] | v3.7.18 (10/11/2026); v3.8 đang rc [CT] | v2.5.1 (06/11/2026) [CT] | 1.32 (09/11/2026) [CT] | Ingress Controller: Gateway API chỉ có TCPRoute. HTTPRoute nằm ở sản phẩm khác (HAProxy Unified Gateway) [CT, [haproxy.com](https://www.haproxy.com/documentation/kubernetes-ingress/gateway-api/)] |
| Kubernetes | v1.10: **v1.34–v1.37**; v1.9: v1.33–v1.36 [CT, [matrix](https://gateway.envoyproxy.io/news/releases/matrix/)] | "1.32+" [CT, [tech specs](https://docs.nginx.com/nginx-gateway-fabric/overview/technical-specifications/)] | Không công bố matrix [CXM] | "minimum ... 1.33", không ghi cận trên [CT, release notes v2.5.0] | 1.32: 1.33–1.37 [CT, [supported releases](https://istio.io/latest/docs/releases/supported-releases/)] | — |
| Gateway API đi kèm | v1.6.1 [CT] | 1.6.3 [CT] | Standard v1.6.3 [CT, [docs v3.7](https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-gateway/)] | v1.7.0 [CT] | — | — |
| Report conformance mới nhất | v1.9.0 trên v1.6.1: HTTP core 37/37, extended 55/55; TLS 20/14; gRPC 15/9; 0 fail, 0 skip [CT] | 2.8.0 trên v1.6.3: HTTP core 36, extended 51, pass hết [CT] | v3.7.10 trên v1.6.1: **HTTP core "partial"** (skip `HTTPRouteMultipleGateways`) [CT] | v2.4.5 trên v1.6.1: HTTP 37/56, TCP, TLS, gRPC pass [CT] | 1.31.0 có report [CT] | — |
| `BackendTLSPolicy` | Có, kèm `BackendTLSPolicySANValidation` [CT] | Có, **không** có SAN validation [CT] | Có, **không** có SAN validation [CT] | Có [CT] | — | — |
| Timeout và retry của HTTPRoute (SSE ở G2) | Có [CT] | **Không** (`HTTPRouteRequestTimeout`, `HTTPRouteRetry` unsupported) [CT] | **Không** [CT] | Có [CT] | — | — |
| `ListenerSet` | Có [CT] | — | **Không** [CT] | — | — | — |
| RAM | Xem 2.2 | Không công bố [CXM] | Chart không đặt `resources` [CT, `values.yaml`]; số thực tế [CXM] | Control plane cộng Envoy, tương tự Envoy Gateway [SL] | **istiod request 2 048 Mi** mặc định [CT, `istio-discovery/values.yaml`@1.32.0] | — |

Các report đều chạy với `gatewayAPIChannel: experimental`. Report của Envoy Gateway v1.10.0 chưa được nộp lên repo `gateway-api` (thư mục `v1.6/envoy-gateway/` chỉ có report v1.9.0). Ở thư mục `v1.7` hiện chỉ có agentgateway, Airlock và kgateway. [CT, tra 13/11/2026]

### 2.2 RAM của Envoy Gateway

- Mặc định của chart `gateway-helm` v1.10.0: controller `requests: {cpu: 100m, memory: 256Mi}`, `limits: {memory: 1024Mi}`, 1 replica [CT, [Helm API](https://gateway.envoyproxy.io/docs/install/gateway-helm-api/)].
- Mặc định cho Envoy proxy mỗi Gateway, trong `api/v1alpha1/shared_types.go`@v1.10.0: `DefaultDeploymentReplicas = 1`, `DefaultDeploymentMemoryResourceRequests = "512Mi"`, `DefaultDeploymentCPUResourceRequests = "100m"`. Container shutdown-manager đi kèm request `32Mi` và `10m` [CT]. Service của Envoy mặc định có `type: LoadBalancer` và `externalTrafficPolicy` mặc định `"Local"` [CT, `envoyproxy_helpers.go`, `shared_types.go`].
- Số đo chính thức trong `benchmark_result.json` của release v1.10.0. Bài test cấp 2000Mi cho mỗi pod; đơn vị RAM suy ra là MiB [SL]:

| Số HTTPRoute (scale up) | Controller max | Envoy proxy max |
|---|---|---|
| 10 | 133,8 | 18,3 |
| 100 | 143,2 | 25,9 |
| 500 | 183,9 | 61,0 |
| 1 000 | 250,0 | 107,4 |

- Trang Developer Guide ghi "nearly 550MiB memory" cho 500 HTTPRoute ở control plane [CT, [Develop](https://gateway.envoyproxy.io/community/develop/)]. Số này lệch với benchmark v1.10.0 (khoảng 184 MiB ở 500 route), có lẽ vì trang không được cập nhật [SL].
- Lab có dưới 15 route. Đặt limit **controller 256 Mi** (gần gấp đôi mức đo được ở 10 route) và **Envoy 128 Mi**. Benchmark chạy HTTP thường, còn lab có TLS và một số kết nối SSE dài từ G2, nên Envoy được để dư nhiều [SL]. Phải đo lại ở G0.

### 2.3 Kết luận mục 2

Chọn **Envoy Gateway v1.10.0**:
1. Nó là bản duy nhất trong nhóm có matrix chính thức ghi Kubernetes 1.37 (Istio 1.32 cũng có, nhưng istiod một mình đã 2 GiB).
2. Có đủ các thứ dự án cần mà không phải dùng CRD riêng: `BackendTLSPolicy` có kiểm SAN (Keycloak re-encrypt), timeout của HTTPRoute (SSE ở G2), `ListenerSet` để dùng sau.
3. RAM đo được ở cỡ lab khoảng 150 MiB cho cả controller lẫn Envoy.

Rủi ro: chu kỳ hỗ trợ ngắn. v1.10 hết hỗ trợ ngày 05/05/2027, nên phải nâng minor theo quý. Report conformance của v1.10 chưa có **[CXM]**.

Phương án dự phòng nếu số đo ở G0 vượt ngân sách: Traefik (một process cho cả control plane lẫn data plane). Giá phải trả là mất timeout và retry chuẩn của HTTPRoute và mất kiểm SAN.

## 3. Sở hữu Gateway, chart `app` và gắn route nhiều namespace

- Mô hình vai trò: nhóm hạ tầng sở hữu Gateway dùng chung "to centrally manage TLS on behalf of app owners". Nhóm app tạo HTTPRoute trong namespace của mình và trỏ `parentRefs` tới Gateway. "Attachment can only succeed if the Gateway owner and Route owner both agree". [CT, [Cross-namespace routing](https://gateway-api.sigs.k8s.io/guides/user-guides/multiple-ns/)]
- `allowedRoutes.namespaces.from` nhận `Same` (mặc định), `All` hoặc `Selector` [CT, CRD v1.6.1]. Ví dụ chính thức dùng `Selector` với nhãn namespace [CT, như trên].
- `ReferenceGrant` chỉ dùng cho tham chiếu chéo namespace từ route tới Service, hoặc từ Gateway tới Secret. Việc route gắn vào Gateway dùng handshake của listener, không cần `ReferenceGrant`. [CT, [ReferenceGrant](https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/)]
- Mặc định, Envoy Gateway tạo Deployment và Service của Envoy trong namespace của controller (`envoy-gateway-system`), mỗi Gateway một bộ proxy riêng [CT, [Deployment mode](https://gateway.envoyproxy.io/docs/tasks/operations/deployment-mode/)]. Pod Envoy mang nhãn `app.kubernetes.io/name=envoy`, `app.kubernetes.io/component=proxy`, `app.kubernetes.io/managed-by=envoy-gateway` [CT, `internal/infrastructure/kubernetes/proxy/resource.go`@v1.10.0]. NetworkPolicy của app phải cho phép nguồn này.
- cert-manager chỉ cấp chứng chỉ cho Secret cùng namespace với Gateway ("cross-namespace Secrets are not supported") [CT, [cert-manager – Gateway](https://cert-manager.io/docs/usage/gateway/)].

**Đề xuất:**
- App `platform` (project `platform`) sở hữu: CRD Gateway API v1.6.1 standard, Envoy Gateway, `GatewayClass envoy`, `EnvoyProxy` (limit RAM, IP MetalLB), namespace `edge` chứa Gateway `edge`, chứng chỉ wildcard, HTTPRoute chuyển HTTP sang HTTPS, cùng các route của thành phần hạ tầng (Keycloak, Argo CD, Grafana).
- Listener `https` có `hostname: "*.lab.internal"` và `allowedRoutes.namespaces.from: Selector` theo nhãn `edge.lab.internal/routes: "true"`. Nhãn này do `platform` gắn khi tạo namespace. Listener `http` chỉ nhận route từ namespace của nó (`Same`).
- Chart `app` sinh **`HTTPRoute`**, không sinh `Ingress`. Một route có thể chứa nhiều hostname, dùng cho `marketplace-sim`. Route chỉ trỏ tới port chính của Service, không bao giờ trỏ tới port admin hay port quản trị. Khi bật route, chart tự thêm nguồn Envoy vào `NetworkPolicy.ingress.from`.
- Không dùng `ReferenceGrant`. Không dùng `ListenerSet` ở G1: wildcard listener đã đủ, và hỗ trợ `ListenerSet` của cert-manager mới ở mức alpha (1.20) [CT].

## 4. TLS

### 4.1 CA nội bộ hay chứng chỉ công khai

| | CA nội bộ (cert-manager `CA` issuer) | ACME DNS-01 (Let's Encrypt) |
|---|---|---|
| Domain | Dùng được `.internal` | Cần domain thật. Chứng minh quyền sở hữu qua DNS công cộng, mà `.internal` không bao giờ được delegate [SL] |
| Phân phối trust | Phải tự làm: Mac, JVM, Node, CI | Không cần |
| Bí mật trong cụm | Khóa CA ký được mọi tên. Giảm rủi ro bằng name constraints | Token API của nhà cung cấp DNS |
| Lộ thông tin | Không | Hostname lộ trên Certificate Transparency log [SL] |
| Phụ thuộc ngoài | Không | Internet, rate limit, nhà cung cấp DNS |

Docs cert-manager ghi CA issuer dành cho "advanced users with experience and tooling for running a PKI", phải tự lo xoay vòng, phân phối trust, khôi phục. cert-manager không tự xoay khóa CA và "name constraints ... are not validated at the time of issuance". Docs khuyên dùng trust-manager để phân phối CA. [CT, [CA issuer](https://cert-manager.io/docs/configuration/ca/)]

**Đề xuất:** CA nội bộ. Lab không có domain thật trong tài liệu, và việc phân phối trust (Mac, JVM, Node, CI) là case kỹ thuật mà hệ thống production nội bộ cũng gặp. ACME là phương án nếu người dùng có domain và muốn bỏ bước phân phối trust. Chỉ cần đổi `ClusterIssuer`, chart không đổi.

### 4.2 Thiết kế PKI

- **Root CA offline:** tạo một lần trên Mac bằng `openssl`, hạn 10 năm, `basicConstraints: CA:TRUE`, `keyUsage: keyCertSign, cRLSign`, **name constraints critical** với permitted DNS `lab.internal`, `svc` và `svc.cluster.local`. Khóa root không vào Git và không vào cụm. Lưu ngoài máy theo cách người dùng chọn.
- **Intermediate CA:** hạn 2 năm, ký bởi root, cũng có name constraints. Lưu trong cụm dưới dạng Sealed Secret `lab-intermediate-ca` (`tls.crt` chứa chuỗi intermediate rồi root, kèm `tls.key`) ở namespace `cert-manager`. `ClusterIssuer lab-ca` kiểu `ca` dùng Secret này. Docs yêu cầu Secret của ClusterIssuer nằm ở "cluster resource namespace", mặc định `cert-manager`. Với intermediate, `tls.crt` chứa cả chuỗi để `ca.crt` của chứng chỉ được cấp đúng [CT, [CA issuer](https://cert-manager.io/docs/configuration/ca/)].
- **Vì sao không bootstrap bằng `SelfSigned` trong cụm:** dựng lại cụm sẽ sinh root mới, và Mac, CI, mọi truststore phải tin lại từ đầu. Khóa root cũng phải sống trong cụm [SL].
- **Name constraints:** cert-manager hỗ trợ trường `nameConstraints` trong `Certificate` có `isCA: true`, nhưng không kiểm SAN của chứng chỉ con theo constraint. Vì vậy chứng chỉ sai vẫn được cấp và chỉ bị client từ chối lúc handshake [CT, [Certificate](https://cert-manager.io/docs/usage/certificate/)]. Ở đây root tạo ngoài cụm nên constraint đặt bằng `openssl`. Chromium tự kiểm name constraints, kể cả khi hệ điều hành đã chấp nhận chuỗi [CT, [Chromium – net/cert README](https://chromium.googlesource.com/chromium/src/+/HEAD/net/cert/README.md)]. Safari/macOS, JDK 25 và Node có thực thi constraint trên root do người dùng thêm vào hay không: **[CXM]**, phải kiểm bằng bằng chứng.
- **Chứng chỉ lá:**
  - Wildcard `*.lab.internal` cho Gateway `edge`, sinh tự động từ annotation `cert-manager.io/cluster-issuer: lab-ca` trên Gateway. Listener phải có `hostname`, `tls.mode: Terminate` và `certificateRefs[].name`, khi đó tên Secret trở thành `secretName` của Certificate [CT, [cert-manager – Gateway](https://cert-manager.io/docs/usage/gateway/)].
  - Một chứng chỉ cho Service của Keycloak (`<kc>-service.keycloak.svc`) dùng cho re-encrypt.
- **Bật Gateway API trong cert-manager:** đặt Helm value `config.gatewayAPI.enabled: true`. CRD Gateway API phải có trước khi cert-manager khởi động, nếu không thì phải restart cert-manager [CT, như trên].
- **Rủi ro phiên bản:** cert-manager 1.21 (bản mới nhất v1.21.3, 23/10/2026) chỉ ghi hỗ trợ Kubernetes 1.33–1.36. Bản 1.22 dự kiến khoảng 11/2026 nhưng chưa phát hành [CT, [Supported releases](https://cert-manager.io/docs/installation/supported-releases/), GitHub Releases]. cert-manager vốn đã là phụ thuộc từ ticket 03, nên rủi ro này đã có sẵn. Ở G0 phải ghi rõ bản cài.

### 4.3 Phân phối trust

| Client | Cách tin root | Nguồn |
|---|---|---|
| Safari, Chrome trên Mac | `sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain lab-root-ca.crt`. Tùy chọn `-d` ghi vào admin cert store, `-r trustRoot` là mặc định | [CT, `man security`]. Chrome tin chứng chỉ trong Keychain có "When using this certificate" hoặc "SSL" đặt "Always Trust" [CT, [Chrome Root Store FAQ](https://chromium.googlesource.com/chromium/src/+/main/net/data/ssl/chrome_root_store/faq.md)] |
| Firefox | Có đọc root trong Keychain của macOS hay không: **[CXM]** (trang hỗ trợ của Mozilla không tải được khi tra). Nếu không thì import tay | — |
| Pod JVM (`channel-connector`, service gọi `auth.` hay `shopee-sim.`) | trust-manager `Bundle`: nguồn `useDefaultCAs: true` cộng root lab. Target là ConfigMap ở namespace có nhãn, kèm `additionalFormats.pkcs12`. Chart `app` mount vào `/etc/trust/` và thêm `-Djavax.net.ssl.trustStore=/etc/trust/bundle.p12 -Djavax.net.ssl.trustStoreType=PKCS12` vào `JAVA_TOOL_OPTIONS` | trust-manager: `Bundle` `trust.cert-manager.io/v1alpha1`, cluster-scoped, `additionalFormats` có `jks` và `pkcs12`, nguồn `configMap`/`secret` đọc từ trust namespace, `namespaceSelector` rỗng thì đồng bộ ra mọi namespace [CT, [trust-manager](https://cert-manager.io/docs/trust/trust-manager/)]. JSSE: nếu `javax.net.ssl.trustStore` trỏ tới file không tồn tại thì JDK tạo TrustManager với "an empty keystore", tức mọi TLS hỏng [CT, [JSSE Reference Guide 25](https://docs.oracle.com/en/java/javase/25/security/java-secure-socket-extension-jsse-reference-guide.html)] |
| Pod Node (`seller-web`) | `NODE_EXTRA_CA_CERTS=/etc/trust/lab-root-ca.pem` (chỉ root lab) | Biến này mở rộng bộ root có sẵn và "only read when the Node.js process is first launched". File thiếu hay hỏng thì chỉ cảnh báo một lần. Không áp dụng khi client tự truyền tùy chọn `ca` [CT, [Node CLI](https://nodejs.org/api/cli.html)]. `fetch` (undici) mà `openid-client` dùng có tôn trọng biến này: **[CXM]**, cần test |
| Envoy (re-encrypt) | `BackendTLSPolicy.validation.caCertificateRefs` trỏ tới ConfigMap do trust-manager đồng bộ vào namespace của policy | Không cho tham chiếu CA chéo namespace [CT, [TLS guide](https://gateway-api.sigs.k8s.io/guides/tls/)] |
| Runner CI (GitHub-hosted, vào lab qua Tailscale) | Cài root vào store của OS (`update-ca-certificates`) và đặt `NODE_EXTRA_CA_CERTS` cho Playwright | **[SL]** |

Vì sao truststore toàn JVM thay vì SSL bundle của Spring Boot: SSL bundle phải gắn vào từng client (RestClient builder, `SslBundles`) [CT, [Spring Boot 4.1.2 – SSL](https://docs.spring.io/spring-boot/reference/features/ssl.html)]. Trong khi đó `JwtDecoder` của resource server và client sinh từ OpenAPI dễ bị sót. Truststore toàn JVM áp cho mọi client mà không phải sửa code. Đổi lại, bundle phải chứa cả CA công khai (`useDefaultCAs`), và gói CA công khai được cập nhật theo bản trust-manager. Ví dụ: v0.26.0 gỡ hai root eMudhra bị lộ, có trong gói mặc định của v0.25.0 [CT, release notes v0.26.0].

### 4.4 Keycloak: re-encrypt bằng `BackendTLSPolicy`

- Keycloak 26.8 gọi re-encrypt là cách "recommended for most production use". Edge termination bắt buộc `http-enabled` và docs coi là kém an toàn hơn. Passthrough thì không có proxy header, phải dùng PROXY protocol. [CT, [Keycloak – Reverse proxy](https://www.keycloak.org/server/reverseproxy)]
- Đường dẫn được mở: `/realms/`, `/resources/`, `/.well-known/`. `/admin/` và `/realms/master/` chỉ cho nội bộ. Không mở `/`, `/metrics`, `/health` và port 9000. [CT, như trên]
- `BackendTLSPolicy` `v1`: `targetRefs` trỏ Service, bắt buộc có `validation.hostname` (làm SNI), CA lấy từ `caCertificateRefs` hoặc `wellKnownCACertificates: "System"`. Không cho tham chiếu chéo namespace, không cho hostname wildcard. [CT, [TLS guide](https://gateway-api.sigs.k8s.io/guides/tls/)]. Envoy Gateway pass `BackendTLSPolicy` và `BackendTLSPolicySANValidation` [CT, conformance v1.9.0]. Trang task của Envoy Gateway v1.10 vẫn dùng `v1alpha3` trong ví dụ, mà bản này không còn được phục vụ ở CRD v1.6.1. Vậy phải viết `gateway.networking.k8s.io/v1` (xem mục 9).
- CR `Keycloak`: `spec.http.tlsSecret`, `spec.ingress.enabled: false`, `spec.proxy.headers: xforwarded|forwarded`. Bỏ `proxy.headers` thì operator quay về hành vi `proxy=passthrough` cũ (deprecated). Docs khuyên giới hạn kết nối tới Keycloak bằng NetworkPolicy. [CT, [Operator – Basic deployment](https://www.keycloak.org/operator/basic-deployment)]

**Đề xuất:**
- Route `auth.lab.internal` chỉ mở `PathPrefix /realms/commerce-hub`, `/resources/`, `/.well-known/`, thay cho `/realms/`. Gateway API so khớp tiền tố theo từng phần tử đường dẫn, nên `/realms/master` không lọt ra mà không cần thêm luật chặn [SL, theo ngữ nghĩa `PathPrefix`].
- Admin Console đi hostname riêng `kc-admin.lab.internal` (`hostname-admin`), mở `/admin/`, `/realms/master/`, `/resources/`.
- `BackendTLSPolicy` trỏ Service `<kc>-service` port https, `hostname: <kc>-service.keycloak.svc`, CA lấy từ ConfigMap của trust-manager.

### 4.5 Header chuyển tiếp

- Mặc định Envoy Gateway **nối thêm** địa chỉ client vào `X-Forwarded-For` có sẵn, chứ không ghi đè. `disableXForwardedForAppend` không xóa header cũ. `clientIPDetection.xForwardedFor.numTrustedHops` lấy IP thứ N tính từ bên phải. [CT, [ClientTrafficPolicy](https://gateway.envoyproxy.io/docs/tasks/traffic/client-traffic-policy/)]
- Keycloak yêu cầu proxy "set and overwrite" header, nếu không thì "rogue clients can inject false values". `proxy-trusted-addresses` chỉ là "weak protection" [CT, [Keycloak – Reverse proxy](https://www.keycloak.org/server/reverseproxy)].
- Subnet router của Tailscale mặc định bật SNAT, nên mọi traffic từ Mac tới cụm đều mang IP nguồn của `gw` [CT, [Tailscale – Subnet routers](https://tailscale.com/kb/1019/subnets)]. Với `externalTrafficPolicy: Local`, MetalLB giữ IP nguồn [CT, [MetalLB – Usage](https://metallb.io/usage/)], nhưng IP đó vẫn là `10.20.0.5`.
- Hệ quả: Keycloak đọc giá trị `X-Forwarded-For` nào khi chuỗi có nhiều phần tử, và client có giả được IP trong event của Keycloak hay không: **[CXM]**. Ở lab, ảnh hưởng thấp vì khóa brute force tính theo user, không theo IP. Bằng chứng bắt buộc: gửi `X-Forwarded-For: 6.6.6.6` rồi xem `ipAddress` trong event đăng nhập. Nếu giả được thì đặt `proxy-headers: forwarded`, hoặc dùng filter xóa header ở biên **[CXM]**.

## 5. Domain lab và DNS

### 5.1 Chọn tên

- ICANN Board giữ vĩnh viễn `.INTERNAL` cho dùng riêng (nghị quyết 2024.07.29.06), tên này không bao giờ được delegate ở root zone [CT, [ICANN Approved Resolutions 29/07/2024](https://www.icann.org/en/board-activities-and-meetings/materials/approved-resolutions-special-meeting-of-the-icann-board-29-07-2024-en)]. Draft IETF ghi rằng resolver có kiểm DNSSEC theo trust anchor toàn cầu sẽ không phân giải được tên `.internal` [CT, [draft-davies-internal-tld](https://datatracker.ietf.org/doc/draft-davies-internal-tld/)]. Draft này chưa phải RFC.
- `.local` được RFC 6762 dành cho Multicast DNS, nên macOS gửi truy vấn `.local` qua mDNS [CT, [RFC 6762](https://www.rfc-editor.org/rfc/rfc6762)]. Loại.
- `home.arpa` được RFC 8375 dành cho mạng gia đình [CT, [RFC 8375](https://www.rfc-editor.org/rfc/rfc8375)]. Dùng được, nhưng `.internal` là tên ICANN chọn cho đúng mục đích "private-use" và ngắn hơn [SL].
- Subdomain của domain thật chỉ cần khi chọn ACME (mục 4.1).

**Đề xuất:** `<domain-lab>` = **`lab.internal`**. Hostname có dạng `app.lab.internal`.

### 5.2 Phân giải

- Tailscale: restricted nameserver (split DNS) "only applies to DNS queries matching a specific search domain". Nếu nameserver là IP riêng thì "you probably need to configure subnet routing". Không thêm bản ghi tùy ý vào MagicDNS được. Client phải bật dùng DNS của Tailscale. Trên macOS, kiểm bằng `dscacheutil -q host -a name <hostname>` vì `nslookup` có thể không đi qua cấu hình DNS của OS. [CT, [Tailscale – DNS](https://tailscale.com/kb/1054/dns)]. "You can use an internal DNS server on your subnet by configuring split DNS". macOS tự nhận subnet route [CT, [Tailscale – Subnet routers](https://tailscale.com/kb/1019/subnets)].
- dnsmasq: `address=/lab.internal/10.20.0.200` khớp cả domain lẫn mọi subdomain (so theo nhãn đầy đủ). `--no-resolv` không đọc `/etc/resolv.conf`. `--bind-interfaces` cùng `--listen-address` giới hạn chỗ nghe. [CT, [dnsmasq man page](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html)]
- CoreDNS trong cụm: thêm server block `lab.internal:53 { errors; cache 30; forward . 10.20.0.5 }` vào ConfigMap `coredns`. Plugin `reload` áp thay đổi trong khoảng 2 phút. CoreDNS không nhận FQDN cho nameserver, phải dùng IP. [CT, [Customizing DNS Service](https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/)]
- MetalLB: xin IP cố định bằng annotation `metallb.io/loadBalancerIPs` (`spec.loadBalancerIP` sắp deprecated). Ở chế độ L2, một node hút traffic cho IP. Với `Local`, chỉ pod trên node đó nhận traffic và IP nguồn được giữ. [CT, [MetalLB – Usage](https://metallb.io/usage/)]. Annotation đặt qua `EnvoyProxy.spec.provider.kubernetes.envoyService.annotations` **[CXM, tên trường theo API extension của Envoy Gateway]**.

**Đề xuất:**
- dnsmasq trên `gw` nghe ở `10.20.0.5:53`, chỉ phục vụ `lab.internal` (`no-resolv`, không upstream), trả wildcard về `10.20.0.200`.
- Split DNS của Tailscale: `lab.internal → 10.20.0.5`.
- CoreDNS chuyển `lab.internal` về `10.20.0.5`.
- Envoy của Gateway `edge` giữ cố định `10.20.0.200`.

Một nguồn sự thật, wildcard nên thêm hostname không phải sửa DNS. Đã loại `/etc/hosts`, vì phải sửa ở Mac, ở runner CI và ở CoreDNS (plugin `hosts`) mỗi lần thêm hostname. Pod cần tên này vì `seller-web` gọi `https://auth.lab.internal` (issuer) và `channel-connector` gọi `https://shopee-sim.lab.internal` (base URL theo ticket 12). Service Spring dùng `jwk-set-uri` nội bộ nên không phụ thuộc DNS này ([keycloak.md](../standards/keycloak.md)).

**Pod gọi IP LoadBalancer của chính cụm (hairpin):** kube-proxy chế độ iptables xử lý traffic từ pod tới IP LoadBalancer ngay trên node, kể cả khi Service để `externalTrafficPolicy: Local`. **[CXM, cần kiểm trên K8s 1.37]**. Bằng chứng: gọi từ một pod nằm trên node không có Envoy.

**Rủi ro khi nâng kubeadm:** hai trang docs nói khác nhau, xem mục 9. Sau mỗi lần `kubeadm upgrade` phải diff ConfigMap `coredns`.

## 6. Hostname

| Hostname | Từ | Tới | Ghi chú |
|---|---|---|---|
| `app.lab.internal` | G1 | `seller-web` | Callback OAuth của sàn cũng về đây (arc42 3.2) |
| `auth.lab.internal` | G0 | Keycloak (re-encrypt) | Chỉ `/realms/commerce-hub`, `/resources/`, `/.well-known/` |
| `shopee-sim.lab.internal` | G1 | `marketplace-sim`, port API | Trình duyệt mở trang ủy quyền; connector dùng làm base URL |
| `argocd.lab.internal` | G0 | `argocd-server` | SSO qua Keycloak cần URL ổn định (`url` trong `argocd-cm`). Docs Argo CD có ví dụ Gateway API. CLI dùng GRPCRoute hoặc `--grpc-web` [CT, [Argo CD – Ingress](https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/)] |
| `grafana.lab.internal` | G0 | Grafana | Tempo, Loki, Prometheus xem qua Grafana Explore |
| `kc-admin.lab.internal` | G0 | Keycloak Admin Console | `hostname-admin` |
| `tiktok-sim.lab.internal` | G2 | `marketplace-sim` (cùng Service) | Thêm hostname vào cùng HTTPRoute |
| `webhooks.lab.internal` | G2 | `webhook-ingress` | Simulator gửi webhook qua cửa vào như sàn thật. Tên chốt ở spec G2 |
| — | — | Admin API của `marketplace-sim`, Prometheus, Alertmanager | Không mở. Dùng `kubectl port-forward` khi cần. Cách runner CI gọi admin API của simulator để spec G1 quyết |
| `http://10.20.0.5:8025` | G1 | Mailpit trên `gw` | Không đi qua Gateway (mục 7) |

UI vận hành đi qua Gateway vì hai lý do. Thứ nhất, SSO bằng Keycloak cần redirect URI ổn định. Thứ hai, chi phí gần như 0, chỉ thêm route vào Envoy sẵn có. Ở lab, mọi người dùng tới được `10.20.0.200` đều đã qua ACL Tailscale. Production sẽ tách UI vận hành sang một Gateway nội bộ riêng **[SL]**. Argo CD và Grafana dùng edge termination (`server.insecure: "true"`), NetworkPolicy chỉ cho Envoy vào. Docs Argo CD cho phép cách này "if your security requirements allow it" [CT]. Chỉ Keycloak re-encrypt, vì nó nhận mật khẩu người dùng cuối và docs Keycloak khuyên re-encrypt.

SSE ở G2: Envoy mặc định timeout request 15 giây [CT, [HTTP timeouts](https://gateway.envoyproxy.io/docs/tasks/traffic/http-timeouts/)]. Gateway API quy định `timeouts.request: "0s"` "SHOULD disable the timeout completely" [CT, CRD v1.6.1]. Route `app.` ở G2 cần một rule riêng cho đường SSE.

## 7. Mailpit

- Bản mới nhất **v1.33.1** (07/11/2026) [CT, GitHub Releases API]. Một binary tĩnh, có install script, hướng dẫn chạy bằng systemd. Mặc định UI ở `0.0.0.0:8025`, SMTP ở `0.0.0.0:1025` [CT, [Install](https://mailpit.axllent.org/docs/install/)].
- Mặc định database là file tạm, tự xóa khi thoát. `--max` mặc định 500 email. UI không có xác thực nếu không đặt `--ui-auth-file` [CT, [Runtime options](https://mailpit.axllent.org/docs/configuration/runtime-options/)].
- RAM: benchmark của docs với 2 500 email (khoảng một nửa có file đính kèm nhỏ): mức nén 0 dùng khoảng 50 MB, mức 1 (mặc định) khoảng 290 MB, mức 3 khoảng 1,2 GB. Docs khuyên mức 0 khi RAM là vấn đề [CT, [Compression](https://mailpit.axllent.org/docs/configuration/compression/)].
- Lỗi đã biết: rò bộ nhớ ở bộ đệm envelope từ v1.31.2, sửa ở v1.31.6 [CT, [issue #748](https://github.com/axllent/mailpit/issues/748)]. CVE-2026-45713 (DoS bằng email cực lớn, CVSS 7,5) ảnh hưởng bản dưới 1.30.0 [CT, [GHSA-fpxj-m5q8-fphw](https://github.com/advisories/GHSA-fpxj-m5q8-fphw)].

**Đề xuất:** Mailpit v1.33.1 chạy trên `gw`, cài binary và chạy bằng systemd. `gw` không cài Docker theo homelab mục 6. Cấu hình: `--compression 0`, `--max 500`, `--max-message-size` nhỏ (ví dụ 5 MB), systemd `MemoryMax=128M`. UI và API nghe ở `10.20.0.5:8025` cho Mac và runner CI (e2e đọc link xác minh qua API). SMTP nghe ở `10.20.0.5:1025` cho Keycloak.

Lý do: arc42 mục 3 và 5 đã vẽ Mailpit là hệ thống ngoài. Đặt trên `gw` không lấy RAM của cụm (còn khoảng 520 MiB sau Envoy Gateway) và không phải thêm route. Đã loại phương án chạy trong cụm: tốn 64–128 Mi của phần dư và phải thêm một route vận hành. Rủi ro là `gw` 2 GB đang có registry, Tailscale và RustFS (RAM của RustFS **[CXM]**), nên phải đo ở G0.

## 8. Ngân sách RAM (bổ sung cho ticket 04)

| Thành phần | Limit đề xuất (MiB) | Căn cứ |
|---|---|---|
| Envoy Gateway controller | 256 | Đo 133,8 MiB ở 10 route [CT, benchmark v1.10.0]; mặc định chart 1 024 |
| Envoy proxy (1 replica, Gateway `edge`) | 128 | Đo 18,3 MiB ở 10 route, không TLS [CT]; mặc định 512 |
| shutdown-manager (sidecar của Envoy) | 32 | Mặc định request 32Mi [CT] |
| trust-manager | 64 | Chart không đặt `resources` [CT]; số [SL] |
| Job certgen của Envoy Gateway | 0 thường trực | Job chạy một lần, `ttlSecondsAfterFinished: 30` [CT] |
| **Cộng** | **480** | Phần dư còn khoảng **520** [SL] |
| Ngoài cụm, trên `gw` | Mailpit `MemoryMax=128M`; dnsmasq vài MiB [SL] | |

## 9. Điểm chưa xác minh và chỗ nguồn mâu thuẫn

**Chưa xác minh:**

1. Report conformance của Envoy Gateway v1.10.0. Đã có report của v1.9.0.
2. Mức RAM thực tế của controller và Envoy khi có TLS, wildcard listener và SSE. Đơn vị trong `benchmark_result.json` suy ra là MiB.
3. Safari/macOS, JDK 25, Node 24 có thực thi name constraints trên root do người dùng thêm vào hay không. Firefox có đọc Keychain không.
4. `fetch` (undici) của Node có tôn trọng `NODE_EXTRA_CA_CERTS` trong `openid-client` không.
5. Keycloak lấy phần tử nào trong `X-Forwarded-For` nhiều giá trị. Client có giả được IP không.
6. Pod gọi IP LoadBalancer (`externalTrafficPolicy: Local`) từ node không có Envoy, trên K8s 1.37 với kube-proxy iptables.
7. cert-manager 1.21 và trust-manager 0.26 trên Kubernetes 1.37 (1.21 chỉ ghi tới 1.36).
8. Tên trường của `EnvoyProxy` để đặt annotation cho Service và limit cho container (docs API quá dài, chưa đọc đoạn đó).
9. Traefik không công bố matrix Kubernetes. RAM của Traefik và NGF.
10. Split DNS của Tailscale trên runner GitHub-hosted (Linux, systemd-resolved).
11. Namespace `envoy-gateway-system` có chạy được với Pod Security `restricted` không.
12. RAM của RustFS trên `gw` (từ ticket 04).

**Mâu thuẫn hoặc không nhất quán giữa các nguồn:**

- **CoreDNS khi `kubeadm upgrade`:** trang "Using CoreDNS" ghi "kubeadm can take care of retaining the existing CoreDNS configuration automatically", còn trang "Reconfiguring a kubeadm cluster" ghi "if you execute `kubeadm upgrade apply`, your changes to the CoreDNS objects will be lost and must be reapplied". Trang sau nói về Deployment và Service, trang trước nói về Corefile. Xử lý: runbook nâng cấp có bước diff ConfigMap `coredns`, và bằng chứng phân giải `auth.lab.internal` từ pod sau khi nâng.
- **API version của `BackendTLSPolicy`:** Gateway API ghi GA `v1` từ v1.4.0, và CRD v1.6.1 không phục vụ `v1alpha3`. Trang task backend TLS của Envoy Gateway v1.10 vẫn dùng `v1alpha3`. Dùng `v1`.
- **Phiên bản CRD Gateway API:** docs cert-manager dùng bundle v1.4.1 trong ví dụ. Envoy Gateway v1.10 yêu cầu "upgrade the Gateway API CRDs to v1.6" trước khi nâng. Gateway API mới nhất là v1.7.0, nhưng Envoy Gateway v1.10 chỉ test với v1.6.1. Chọn v1.6.1.
- **RAM control plane của Envoy Gateway:** Developer Guide ghi "nearly 550MiB" cho 500 route, benchmark v1.10.0 đo khoảng 184 MiB. Dùng số benchmark vì gắn với đúng phiên bản.
- **EOL của Envoy Gateway v1.8:** matrix ghi 2026/11/08, trang Releases ghi 2026/11/14. Không ảnh hưởng vì chọn v1.10.
- **Ngày phát hành Envoy Gateway v1.10.0:** trang Releases ghi 2026/11/05, GitHub ghi 2026-11-06T11:48Z (lệch múi giờ hoặc ngày công bố).
- **Tài liệu trong repo:** ticket 11 và 12 viết "Ingress nhiều hostname", [keycloak.md](../standards/keycloak.md) viết HTTPRoute và mở `/realms/`, đồng thời ghi "truststore của Spring Boot qua SSL bundle". [Homelab](../../platform/docs/homelab-hyperv.md) mục 8.6 ghi Gateway API là "Tùy chọn".

---

## Đề xuất cho ticket 16

| Quyết định | Đề xuất | Đã loại | Lý do |
|---|---|---|---|
| API | **Gateway API** (CRD standard channel **v1.6.1**) | Ingress | Ingress đã đóng băng. `ingress-nginx` không còn bản vá. Cần `BackendTLSPolicy`, timeout chuẩn, chia vai |
| Implementation | **Envoy Gateway v1.10.0**, 1 Gateway `edge`, Envoy 1 replica | Istio 1.32 (istiod 2 Gi); NGF 2.8.1 (thiếu timeout, retry, kiểm SAN); Traefik 3.7 (core HTTP partial, thiếu timeout, retry, ListenerSet); kgateway 2.5.1 (không có cam kết K8s 1.37); HAProxy (chỉ TCPRoute); Cilium (CNI là Calico) | Bản duy nhất ghi hỗ trợ K8s 1.37 với RAM nhỏ, pass đủ HTTP, TLS, gRPC, có `BackendTLSPolicy` kiểm SAN |
| RAM | Controller 256 Mi, Envoy 128 Mi, shutdown-manager 32 Mi, trust-manager 64 Mi: **480 MiB** | Mặc định (controller limit 1 024 Mi, Envoy request 512 Mi) | Benchmark v1.10.0 ở 10 route: 134 và 18 MiB |
| Sở hữu | App `platform`: CRD, Envoy Gateway, `GatewayClass envoy`, `EnvoyProxy`, namespace `edge` (Gateway, chứng chỉ wildcard, redirect HTTP), route của Keycloak, Argo CD, Grafana | Mỗi app tự tạo Gateway hoặc ListenerSet | TLS tập trung, app không đụng chứng chỉ |
| Chart `app` | Sinh **`HTTPRoute`** (`parentRefs` tới `edge/https`, nhiều hostname, chỉ port chính), tự mở NetworkPolicy cho pod Envoy | Sinh `Ingress` | Khớp API đã chọn |
| Gắn route | `allowedRoutes.namespaces.from: Selector`, nhãn namespace do `platform` gắn. Không dùng `ReferenceGrant` | `from: All`; `ReferenceGrant` | Chỉ namespace được duyệt mới gắn route |
| TLS | CA nội bộ: **root offline có name constraints** (`lab.internal`, `svc`, `svc.cluster.local`), **intermediate trong cụm** (Sealed Secret), `ClusterIssuer lab-ca`; wildcard `*.lab.internal` do annotation trên Gateway sinh | ACME DNS-01 (cần domain thật, lộ hostname trên CT log, token DNS trong cụm); `SelfSigned` bootstrap trong cụm (dựng lại cụm phải tin lại root) | `.internal` không xin được chứng chỉ công khai. Root ổn định qua các lần dựng lại cụm |
| Trust | Mac: Keychain hệ thống; JVM: PKCS12 từ **trust-manager v0.26.0** cùng `javax.net.ssl.trustStore`; Node: `NODE_EXTRA_CA_CERTS`; CI: store của OS | SSL bundle của Spring Boot cho từng client; init container chạy `keytool` | Không phải sửa code. Áp cho cả `JwtDecoder` |
| Keycloak | Re-encrypt bằng `BackendTLSPolicy` `v1` (`hostname` là tên Service). Route chỉ `/realms/commerce-hub`, `/resources/`, `/.well-known/`. Admin ở `kc-admin.` | Edge; passthrough | Docs Keycloak khuyên re-encrypt. Passthrough mất header |
| `<domain-lab>` | **`lab.internal`** | `.local` (mDNS); `home.arpa`; subdomain của domain thật (chỉ khi chọn ACME) | ICANN giữ `.INTERNAL` cho dùng riêng |
| Phân giải | **dnsmasq trên `gw`** (wildcard tới `10.20.0.200`), split DNS Tailscale `lab.internal → 10.20.0.5`, server block CoreDNS chuyển về `10.20.0.5`, IP MetalLB cố định bằng `metallb.io/loadBalancerIPs` | `/etc/hosts` (sửa nhiều chỗ); DNS công cộng trỏ IP riêng (cần domain) | Một nguồn sự thật, wildcard |
| Hostname | G0–G1: `app.`, `auth.`, `shopee-sim.`, `argocd.`, `grafana.`, `kc-admin.`. G2: `tiktok-sim.`, `webhooks.` | — | UI vận hành cần redirect URI ổn định cho SSO |
| UI khác | Prometheus, Alertmanager, admin API của simulator: `port-forward` | Mở hết qua Gateway | Giảm bề mặt |
| Mailpit | **v1.33.1 trên `gw`**, systemd, `--compression 0`, `MemoryMax=128M`, `:1025` và `:8025` | Trong cụm | 0 RAM của cụm. Khớp arc42 (hệ thống ngoài) |

Cần cập nhật sau khi chốt (thuộc spec hoặc ticket sửa tài liệu, không làm trong ticket này):

- Ticket [11](../.scratch/architecture-g0-g1/issues/11-service-template.md) và [12](../.scratch/architecture-g0-g1/issues/12-shopee-sim.md): "Ingress nhiều hostname" đổi thành "HTTPRoute nhiều hostname". Chart `app` thêm values `httpRoute.*`, mount trust bundle, `JAVA_TOOL_OPTIONS` truststore, `NODE_EXTRA_CA_CERTS`, nguồn Envoy trong NetworkPolicy.
- [keycloak.md](../standards/keycloak.md): route `/realms/commerce-hub` thay `/realms/`; `BackendTLSPolicy` `v1`; truststore JVM thay SSL bundle; kiểm `X-Forwarded-For`; `kc-admin.` cho `hostname-admin`; SMTP `10.20.0.5:1025`.
- [Homelab](../../platform/docs/homelab-hyperv.md): mục 8.6 thành bắt buộc; thêm dnsmasq và Mailpit trên `gw`; split DNS Tailscale; CoreDNS; tin root CA trên Mac; bảng RAM.
- Ticket [04](../.scratch/architecture-g0-g1/issues/04-resource-budget.md) và [ADR-0004](../adr/0004-single-instance-by-default-on-homelab.md): thêm khoảng 480 MiB, phần dư còn khoảng 520 MiB.
- arc42 [mục 3.2](../architecture/03-context-and-scope.md), [mục 5](../architecture/05-building-block-view.md), [mục 8](../architecture/08-crosscutting-concepts.md): cửa vào, `lab.internal`, Mailpit trên `gw`, PKI và trust.
- [helm-chart.md](../standards/helm-chart.md), [gitops-argocd.md](../standards/gitops-argocd.md) (thứ tự sync wave: CRD trước cert-manager và Envoy Gateway; app `platform` có thêm thành phần), [zero-downtime.md](../standards/zero-downtime.md) (kịch bản tải đi qua `https://*.lab.internal`).

## Nên viết ADR

1. **Gateway API với Envoy Gateway làm cửa vào cụm, Gateway `edge` do `platform` sở hữu, app chỉ viết HTTPRoute.** Khó đảo ngược vì mọi chart, route và NetworkPolicy phụ thuộc. Người quen `ingress-nginx` sẽ bất ngờ. Đây cũng là trade-off thật giữa RAM, tính năng và chu kỳ hỗ trợ ngắn của Envoy Gateway.
2. **PKI của lab: `lab.internal`, root offline có name constraints, intermediate trong cụm, phân phối trust bằng trust-manager và truststore toàn JVM.** Khó đảo ngược vì mọi client (Mac, CI, JVM, Node) đã tin root. Nếu thiếu bối cảnh thì việc không dùng ACME hay SSL bundle sẽ gây bất ngờ. Có thể gộp DNS (dnsmasq trên `gw`, split DNS) vào ADR này.
3. Không cần ADR cho Mailpit trên `gw` (đổi chỗ rẻ) và danh sách hostname (ghi ở arc42 mục 3.2).

## Nguồn

- Kubernetes 1.37: [Ingress](https://kubernetes.io/docs/concepts/services-networking/ingress/), [Ingress NGINX retirement (11/11/2025)](https://kubernetes.io/blog/2025/11/11/ingress-nginx-retirement/), [Gateway API v1.5](https://kubernetes.io/blog/2026/04/21/gateway-api-v1-5/), [Customizing DNS Service](https://kubernetes.io/docs/tasks/administer-cluster/dns-custom-nameservers/), [Using CoreDNS](https://kubernetes.io/docs/tasks/administer-cluster/coredns/), [Reconfiguring a kubeadm cluster](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-reconfigure/).
- Gateway API: [Releases](https://github.com/kubernetes-sigs/gateway-api/releases) (v1.7.0, v1.6.3, v1.6.1), `standard-install.yaml` v1.6.1, [Implementations](https://gateway-api.sigs.k8s.io/implementations/), report trong `conformance/reports/v1.6/` (`envoy-gateway/experimental-v1.9.0-default-report.yaml`, `traefik-traefik/experimental-v3.7.10-default-report.yaml`, `nginx-nginx-gateway-fabric/experimental-2.8.0-default-report.yaml`, `kgateway/v2.4.5-report.yaml`), [TLS guide](https://gateway-api.sigs.k8s.io/guides/tls/), [Cross-namespace routing](https://gateway-api.sigs.k8s.io/guides/user-guides/multiple-ns/), [ReferenceGrant](https://gateway-api.sigs.k8s.io/reference/api-types/referencegrant/), [ListenerSet](https://gateway-api.sigs.k8s.io/reference/api-types/listenerset/).
- Envoy Gateway v1.10.0: [Compatibility matrix](https://gateway.envoyproxy.io/news/releases/matrix/), [Releases](https://gateway.envoyproxy.io/news/releases/), [GitHub release v1.10.0](https://github.com/envoyproxy/gateway/releases/tag/v1.10.0) (`benchmark_result.json`), [Install with Helm](https://gateway.envoyproxy.io/docs/install/install-helm/), [Install with Argo CD](https://gateway.envoyproxy.io/docs/install/install-argocd/), [Helm API](https://gateway.envoyproxy.io/docs/install/gateway-helm-api/), [Deployment mode](https://gateway.envoyproxy.io/docs/tasks/operations/deployment-mode/), [Backend TLS](https://gateway.envoyproxy.io/docs/tasks/security/backend-tls/), [ClientTrafficPolicy](https://gateway.envoyproxy.io/docs/tasks/traffic/client-traffic-policy/), [HTTP timeouts](https://gateway.envoyproxy.io/docs/tasks/traffic/http-timeouts/), [Developer Guide](https://gateway.envoyproxy.io/community/develop/); mã nguồn `api/v1alpha1/shared_types.go`, `api/v1alpha1/envoyproxy_helpers.go`, `internal/infrastructure/kubernetes/proxy/resource.go` tại tag v1.10.0.
- Phương án khác: [NGINX Gateway Fabric – Technical specifications](https://docs.nginx.com/nginx-gateway-fabric/overview/technical-specifications/), [Traefik – Kubernetes Gateway provider](https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-gateway/), [Traefik releases](https://github.com/traefik/traefik/releases), `traefik-helm-chart/traefik/values.yaml`, [kgateway releases](https://github.com/kgateway-dev/kgateway/releases), [Istio supported releases](https://istio.io/latest/docs/releases/supported-releases/), `istio/manifests/charts/istio-control/istio-discovery/values.yaml`@1.32.0, [HAProxy Kubernetes Ingress – Gateway API](https://www.haproxy.com/documentation/kubernetes-ingress/gateway-api/).
- cert-manager: [Gateway](https://cert-manager.io/docs/usage/gateway/), [CA issuer](https://cert-manager.io/docs/configuration/ca/), [Certificate](https://cert-manager.io/docs/usage/certificate/), [Releases](https://cert-manager.io/docs/releases/), [Supported releases](https://cert-manager.io/docs/installation/supported-releases/), [GitHub releases](https://github.com/cert-manager/cert-manager/releases); [trust-manager](https://cert-manager.io/docs/trust/trust-manager/), [trust-manager release v0.26.0](https://github.com/cert-manager/trust-manager/releases/tag/v0.26.0), `deploy/charts/trust-manager/values.yaml`@v0.26.0.
- Keycloak 26.8: [Reverse proxy](https://www.keycloak.org/server/reverseproxy), [Operator – Basic deployment](https://www.keycloak.org/operator/basic-deployment).
- [Argo CD – Ingress configuration (Gateway API example)](https://argo-cd.readthedocs.io/en/stable/operator-manual/ingress/).
- MetalLB: [Usage](https://metallb.io/usage/), [Releases](https://github.com/metallb/metallb/releases) (v0.16.2).
- Tailscale: [DNS](https://tailscale.com/kb/1054/dns), [Subnet routers](https://tailscale.com/kb/1019/subnets).
- Tên miền: [ICANN Approved Resolutions 29/07/2024](https://www.icann.org/en/board-activities-and-meetings/materials/approved-resolutions-special-meeting-of-the-icann-board-29-07-2024-en), [draft-davies-internal-tld](https://datatracker.ietf.org/doc/draft-davies-internal-tld/), [RFC 6762](https://www.rfc-editor.org/rfc/rfc6762), [RFC 8375](https://www.rfc-editor.org/rfc/rfc8375).
- [dnsmasq man page](https://thekelleys.org.uk/dnsmasq/docs/dnsmasq-man.html).
- Trust: `man security` (macOS), [Chrome Root Store FAQ](https://chromium.googlesource.com/chromium/src/+/main/net/data/ssl/chrome_root_store/faq.md), [Chromium net/cert README](https://chromium.googlesource.com/chromium/src/+/HEAD/net/cert/README.md), [Node.js CLI](https://nodejs.org/api/cli.html) (`cli.json` v24), [JSSE Reference Guide (JDK 25)](https://docs.oracle.com/en/java/javase/25/security/java-secure-socket-extension-jsse-reference-guide.html), [Spring Boot 4.1.2 – SSL](https://docs.spring.io/spring-boot/reference/features/ssl.html).
- Mailpit: [Install](https://mailpit.axllent.org/docs/install/), [Runtime options](https://mailpit.axllent.org/docs/configuration/runtime-options/), [Compression](https://mailpit.axllent.org/docs/configuration/compression/), [Releases](https://github.com/axllent/mailpit/releases), [issue #748](https://github.com/axllent/mailpit/issues/748), [GHSA-fpxj-m5q8-fphw](https://github.com/advisories/GHSA-fpxj-m5q8-fphw).
