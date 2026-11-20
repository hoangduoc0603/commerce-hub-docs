# 22: Chart `app`: HTTPRoute, truststore

Status: resolved
Blocked by: 07, 21
Repos: platform, gitops, docs
Spec: [G0](../spec.md)

## Mô tả

Thêm vào chart `app` hai khả năng bật bằng values: `httpRoute.*` gắn vào Gateway `edge` (nhiều hostname, chỉ port chính); mount truststore của trust-manager (JVM thêm `-Djavax.net.ssl.trustStore`, Node đặt `NODE_EXTRA_CA_CERTS`). Truststore cần vì Spring Resource Server gọi JWKS qua `https://auth.lab.internal` (ticket 29). Kiểm trên lab bằng một release thử deploy qua Argo CD, chart kéo từ GHCR. Theo [helm-chart.md](../../../standards/helm-chart.md), [ADR-0013](../../../adr/0013-gateway-api-envoy-gateway-shared-edge.md), [ADR-0014](../../../adr/0014-lab-pki-and-dns.md), [ADR-0017](../../../adr/0017-images-and-charts-on-ghcr.md).

## Mục tiêu học

- JVM tin CA nội bộ: truststore phát từ trust-manager, và lỗi `PKIX` khi thiếu.

## Thu hẹp 2026-11-15

Theo quyết định D6, D7 (spec G0 mục "Sửa phạm vi 2026-11-15").

- Giữ: `httpRoute.*`, truststore từ trust-manager, kiểm trên lab qua Argo CD.
- Đổi: chart publish và kéo từ GHCR.
- Hoãn tới G7: NetworkPolicy (ingress theo danh sách cho phép, tự mở cho pod Envoy khi có route, egress chỉ siết khi khai báo `egress.to`); `ct install`; JSON schema của values, kể cả phần kiểm `httpRoute.parentRef`.

Tiêu chí hoãn tới G7:

- Gọi `servicePort` từ pod lạ ở namespace khác bị chặn; qua `edge` vẫn thành công.
- `ct install` vẫn pass (biến thể route chạy trên kind có CRD Gateway API, hoặc chỉ render nếu không có controller; ghi lựa chọn). Kind không có trust-manager: tạo ConfigMap `lab-trust`, `lab-root` giả hoặc đặt `trust.enabled: false` (review G0-22).
- Schema của chart kiểm `httpRoute.parentRef` (chỉ `edge/edge`, `sectionName` hợp lệ): `parentRef` sai tên làm app chỉ `Progressing` mãi, không `Degraded`. Chuyển từ G0-05, review điểm 7.

## Tiêu chí nghiệm thu

- [x] Release thử có route: `HTTPRoute` `Accepted`, `ResolvedRefs`; `curl https://<host>.lab.internal` qua `edge` trả 200.
- [x] Release thử JVM gọi `https://argocd.lab.internal` OK; tắt truststore trong values thì lỗi `PKIX`.
- [x] Release chart mới publish lên GHCR.

## Quyết định khi lập lộ trình (2026-11-20)

Chốt với chủ repo trước bước 1. Chủ repo giao Claude làm cả ticket.

- **Q1. Release thử là `hello`, qua đường thật của service.** Ticket này làm luôn phần gitops mà ticket 24 liệt kê: namespace `hello` có nhãn (PSS, route, trust) do app hạ tầng tạo, GHCR vào `sourceRepos` của `commerce`, ApplicationSet kéo chart từ GHCR, `envs/lab/hello/values.yaml` ghi tay digest của ticket 23. Ticket 24 còn CI `update-gitops`, đo lead time, rollback. Loại: Application tạm `chart-test` trong project `platform` (làm hai lần, không kiểm ranh giới quyền của `commerce`).
- **Q2. Route chỉ trỏ cổng `http`, không có value `servicePort`.** Không trỏ nhầm được cổng Actuator 8081; thêm khi có workload cần cổng khác. Lệch chuẩn ghi ở `helm-chart.md`.
- **Q3. Hostname kiểm bằng `regexMatch` + `fail` trong template** (một nhãn trước `.lab.internal`), thay schema tới G7.
- **Q4. Schema `HTTPRoute` cho kubeconform sinh từ CRD v1.6.1** bằng `openapi2jsonschema.py` của kubeconform, commit vào `platform`. Loại: CRDs-catalog (không ghim được đúng v1.6.1).

## Lộ trình

- [x] 1. `trust.*`: volume `projected` hai ConfigMap, mount `/etc/trust`, cờ truststore nối cuối `JAVA_TOOL_OPTIONS`, `NODE_EXTRA_CA_CERTS` khi `jvm.enabled=false`. Kiểm: render ba biến thể; kubeconform xanh.
- [x] 2. `httpRoute.*`, `httproute.yaml`; `ci/lab-values.yaml` bật route. Kiểm: render đúng; hostname hai nhãn làm render fail.
- [x] 3. Schema HTTPRoute v1.6.1 cho kubeconform, sửa `chart.yml`. Kiểm: thiếu schema thì lỗi, có thì `Valid`, field sai thì `Invalid`.
- [x] 4. Smoke `helm install` chart local vào namespace thử có nhãn. Kiểm: route `Accepted`, `curl …/livez` 200, probe JVM 200; namespace thiếu nhãn trust thì pod kẹt `ContainerCreating`.
- [x] 5. Chart 0.2.0: PR, publish. Kiểm: `helm show chart oci://ghcr.io/hoangduoc0603/charts/app --version 0.2.0`.
- [x] 6. Gitops: namespace `hello`, GHCR trong `commerce`, ApplicationSet sang GHCR 0.2.0. Kiểm: Argo CD kéo được chart.
- [x] 7. `envs/lab/hello/values.yaml`; commit `trust.enabled: false` rồi revert. Kiểm: `svc-hello` `Synced/Healthy`, route `Accepted`/`ResolvedRefs`, `curl` 200, probe JVM 200 rồi `PKIX`.
- [x] 8. Kết ticket: `code-review`, bằng chứng, `helm-chart.md`, `cluster-entry.md`, ticket 24, `## Bài học`.

## Bằng chứng

Helm 4.3.2, kubeconform 0.8.0, cụm `homelab` v1.37.2, Argo CD 3.6.1, image `hello` `sha256:5f13c9cc…e1c739` (commit `16efc28`). Probe JVM là `Get.java` của G0-07 biên dịch bằng `javac --release 25` trên Mac, `kubectl cp` vào `/tmp` của pod rồi `kubectl exec … java -cp /tmp Get <url>`: tiến trình này nhận đúng `JAVA_TOOL_OPTIONS` mà chart đặt cho container.

- **Render** (bước 1–2): biến thể lab có `-Djavax.net.ssl.trustStore=/etc/trust/bundle.p12 -Djavax.net.ssl.trustStoreType=PKCS12` ở cuối `JAVA_TOOL_OPTIONS`; `jvm-off` có `NODE_EXTRA_CA_CERTS=/etc/trust/lab-root-ca.pem`; `trust.enabled=false` thì không volume, không cờ. Hostname `a.b.lab.internal`, `hello.example.com`, `Hello.lab.internal`, `*.lab.internal`, danh sách rỗng, `parentRef` null hoặc thiếu `sectionName` đều làm `helm template` thất bại kèm thông điệp.
- **kubeconform** (bước 3): chỉ schema mặc định thì `could not find schema for HTTPRoute` (`Errors: 1`); thêm schema sinh từ CRD v1.6.1 thì `Valid: 5`; `sectionNam` → `additional properties 'sectionNam' not allowed`; `timeouts.request: 15` → `got number, want string`. CI ([platform#6](https://github.com/hoangduoc0603/commerce-hub-platform/pull/6)): ba biến thể `Valid: 3`, `4`, `5`, `Invalid: 0, Errors: 0`.
- **Smoke chart local** (bước 4, namespace `chart-test`): thiếu nhãn trust thì pod `ContainerCreating`, event `MountVolume.SetUp failed for volume "trust" : [configmap "lab-trust" not found, configmap "lab-root" not found]`; gắn nhãn thì trust-manager chép ConfigMap và pod `Ready` sau 11 s, không cần cài lại. Route `Accepted=True`, `ResolvedRefs=True`; `curl https://chart-test.lab.internal/livez` trả 200, `/actuator` trả 404 (Actuator ở 8081, không qua edge). Probe: `argocd.lab.internal` 200, `github.com` 200; `helm upgrade --set trust.enabled=false` thì `argocd.lab.internal` → `PKIX path building failed`, `github.com` vẫn 200. Đã dọn namespace.
- **Publish** (bước 5): `oci://ghcr.io/hoangduoc0603/charts/app:0.2.0`, digest `sha256:83ce4f39d3802ea4f3a9602aea1902b05f39931c4a0b54b52dfc234d4b35840a`; `helm show chart` không đăng nhập in `version: 0.2.0`.
- **Qua Argo CD** (bước 6–7): `gitops` `83b3f35` (app `namespaces`, GHCR trong `commerce`, ApplicationSet sang 0.2.0), `5ad97b5` (values `hello`). `svc-hello` `Synced/Healthy` 23 s sau push; revision `["0.2.0","5ad97b5…"]`; pod chạy đúng digest, nhãn `helm.sh/chart: app-0.2.0`. Route `Accepted=True`, `ResolvedRefs=True`; `curl https://hello.lab.internal/livez` và `/readyz` trả 200 `{"status":"UP"}`. Probe trong pod `hello`: `argocd.lab.internal` 200. Commit `17d4a9b` (`trust.enabled: false`): pod mới chỉ có volume `tmp`, `PKIX path building failed`; revert `484f61e`: lại 200. 13 app `Synced/Healthy`.

## Review

`code-review` (high) trên `platform` `main..g0-22-chart-edge` trước khi publish (version trên GHCR không ghi đè được), ra 6 điểm. Sửa 4 trong platform#6: `required` cho `httpRoute.parentRef` và ba trường; biến thể `jvm-off` có route kèm `timeouts` để CI render nhánh đó; README ghi thay đổi phá vỡ của trust mặc định và việc restart khi xoay root; lệnh sinh lại schema kiểm sha256 của script. Không sửa, ghi vào lệch chuẩn của `helm-chart.md`: `ct install` trên kind (G7) cần ConfigMap trust giả; xoay root không tự rollout pod. Thay đổi `gitops` (namespace, project, ApplicationSet, values) nhỏ và đã kiểm trực tiếp trên cụm, không chạy review riêng.

## Bài học

- `javax.net.ssl.trustStore` **thay thế** `cacerts` chứ không cộng thêm. Bundle `lab-trust` phải chứa cả CA công khai (`useDefaultCAs`); chỉ chứa root lab thì `github.com` sẽ lỗi `PKIX`. Đối chứng hai chiều (host lab và host công khai, bật và tắt) mới thấy rõ JVM đang tin store nào.
- Mount bắt buộc biến lỗi im lặng thành lỗi ồn: namespace thiếu nhãn thì pod kẹt ở `FailedMount`, nêu đúng tên ConfigMap thiếu. Gắn nhãn xong, kubelet tự thử mount lại, không cần cài lại.
- Smoke chart local trên cụm trước khi publish là bắt buộc khi version trên registry bất biến; review cũng đặt trước publish, vì sửa sau là phải tăng version.
- Câu chuyện kể được: "Chart dùng chung cho service một cửa vào qua Gateway API và cho JVM tin CA nội bộ mà không sửa code: trust-manager phân phối truststore, chart mount bắt buộc và nối cờ JVM. Kiểm qua Argo CD bằng commit tắt truststore: host nội bộ lỗi PKIX, host công khai vẫn chạy; revert là hết. CI kiểm HTTPRoute bằng schema sinh từ CRD đúng phiên bản."

## Chuyển từ G0-05

- **Hoãn tới G7** (2026-11-15: bảo mật cửa vào, không cần để service chạy; chỉ một người deploy nên rủi ro chiếm hostname thấp). Ràng buộc hostname theo namespace: hiện mọi namespace có nhãn `edge.lab.internal/routes` khai được bất kỳ `*.lab.internal` nào, kể cả hostname của app khác (path cụ thể hơn thắng). Chọn cơ chế (ví dụ `ValidatingAdmissionPolicy` so `spec.hostnames` của HTTPRoute với danh sách cho phép gắn trên namespace) và thử bằng một route khai `auth.lab.internal` từ namespace service. Review G0-05 điểm 1.
