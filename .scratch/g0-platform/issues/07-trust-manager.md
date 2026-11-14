# 07: trust-manager phân phối CA cho pod

Status: resolved
Blocked by: 06
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

trust-manager v0.26.0 sinh `Bundle` `lab-trust` gồm root của lab, ra cả PEM lẫn truststore PKCS12. Một pod JVM tạm và một pod Node tạm mount bundle đó, gọi được `https://argocd.lab.internal` mà không sửa code và không tắt kiểm TLS. Đây là cơ chế chart `app` sẽ dùng ở ticket 22. Theo mục "Phân phối trust" của [cluster-entry.md](../../../standards/cluster-entry.md).

## Mục tiêu học

- Cách JVM (`javax.net.ssl.trustStore`) và Node (`NODE_EXTRA_CA_CERTS`) quyết định tin CA nào.

## Tiêu chí nghiệm thu

- [x] Pod JVM tạm có mount truststore gọi `https://argocd.lab.internal` thành công; bỏ mount thì lỗi `PKIX`.
- [x] Pod Node tạm với `NODE_EXTRA_CA_CERTS` gọi thành công, không đặt `NODE_TLS_REJECT_UNAUTHORIZED`.
- [x] Hairpin: pod trên node không có Envoy gọi `https://*.lab.internal` thành công.
- [x] JVM và Node từ chối chứng chỉ `evil.example.com` của ticket 06; kết quả ghi vào [cluster-entry.md](../../../standards/cluster-entry.md).

## Lộ trình

Duyệt ngày 2026-11-15. Chủ repo giao Claude làm cả ticket. Hiện trạng lúc lập: 8 app `Synced/Healthy`; Envoy chạy trên `k8s-w2`; chart trust-manager v0.26.0 chỉ có CRD `Bundle` `trust.cert-manager.io/v1alpha1` (chưa có `ClusterBundle`); profile PKCS12 mặc định `LegacyRC2` mà API reference ghi "Not supported by default in OpenSSL 3 or Java 20"; một `Bundle` chỉ ghi được một key PEM.

Quyết định khi duyệt: (A) Node dùng `Bundle` thứ hai `lab-root` chỉ chứa root lab (không `useDefaultCAs`), vì `NODE_EXTRA_CA_CERTS` chỉ thêm root, không bớt được: trỏ Node vào gói CA công khai của trust-manager sẽ tin lại root mà Node đã gỡ. (B) `Bundle` và ConfigMap nguồn nằm ở app `lab-ca` (wave 5), không ở app `trust-manager`. (C) Pod và namespace tạm áp bằng `kubectl`, manifest lưu ở bản ghi thí nghiệm, gỡ ở bước 7.

- [x] 1. App `trust-manager` (wave 4): chart OCI v0.26.0, CRD vendor `Prune=false,Delete=false`, image ghim digest, 64 Mi kèm `GOMEMLIMIT`, resources cho init container `defaultPackage`, trust namespace `cert-manager`, Secret target tắt. Kiểm: `Synced/Healthy`; `kubectl api-resources | grep bundles`; RAM.
  - Kết quả: `e5858be`; push → `Synced/Healthy` sau khoảng 50 s (gồm refresh); `bundles` `trust.cert-manager.io/v1alpha1`; chứng chỉ webhook từ Issuer selfSigned `Ready`, cainjector đã điền `caBundle`. RAM 15 Mi. Chart không có `extraEnv` nên không đặt được `GOMEMLIMIT` (ghi lệch ở app). Thấy thêm: K8s 1.37 phục vụ `ClusterTrustBundle` `certificates.k8s.io/v1` (ghi ở phương án đã loại).
- [x] 2. App `lab-ca`: ConfigMap nguồn root lab, `Bundle` `lab-trust` (`useDefaultCAs` + root, PEM + PKCS12) và `lab-root` (chỉ root), `namespaceSelector` theo nhãn; namespace tạm `sandbox-trust` mang nhãn. Kiểm: ConfigMap có ở namespace có nhãn, không có ở namespace không nhãn; `openssl pkcs12`/`keytool -list` thấy root lab.
  - Kết quả: `672b854`; hai `Bundle` `Synced=True` sau 4 s, Argo CD báo `Healthy` (health check có sẵn). ConfigMap `lab-trust`, `lab-root` có ở `sandbox-trust`, không có ở `sandbox-nolabel`. `bundle.p12` 149 chứng chỉ (148 công khai + root lab), `keytool -list` của JDK 25.0.3 đọc được không cần mật khẩu. Phát hiện: mật khẩu rỗng thì trust-manager ghi PKCS12 **không MAC, không mã hóa** (`openssl`: "MAC is absent", `PKCS7 Data`), tức `profile` có thể không có tác dụng; kiểm ở bước 3.
- [x] 3. Pod JVM tạm (JDK 25, `HttpClient` qua source launcher) mount bundle, `JAVA_TOOL_OPTIONS`. Kiểm: `https://argocd.lab.internal` 200; bỏ mount thì `PKIX`; thử profile mặc định.
  - Kết quả: 200 tới `argocd.lab.internal` và `github.com` (149 trust cert, không cần `trustStorePassword`); bỏ mount thì `PKIX path building failed`. **Lệch chuẩn:** cờ trỏ file thiếu thì JDK 25 báo `Inaccessible trust store` ở mức DEBUG rồi quay về `cacerts`, không dùng keystore rỗng. Profile: mật khẩu rỗng cho ra PKCS12 không mã hóa (LegacyRC2 và Modern2023 giống từng byte); có mật khẩu mà thiếu `trustStorePassword` thì `trustAnchors parameter must be non-empty`; JDK 25 đọc được RC2-40, OpenSSL 3 thì không.
- [x] 4. Pod Node tạm với `NODE_EXTRA_CA_CERTS`, `fetch`. Kiểm: 200; không có biến thì lỗi issuer; không đặt `NODE_TLS_REJECT_UNAUTHORIZED`.
  - Kết quả: Node 24.22.3 và 26.13.1, `fetch` 200 có biến; không biến thì `UNABLE_TO_GET_ISSUER_CERT_LOCALLY`; biến trỏ file thiếu thì một dòng cảnh báo rồi chạy tiếp. Trả lời câu hỏi mở của ADR-0014: undici đọc `NODE_EXTRA_CA_CERTS`.
- [x] 5. Hairpin: pod JVM và Node trên `k8s-w1` (không có Envoy). Kiểm: gọi thành công.
  - Kết quả: Envoy ở `k8s-w2`; pod JVM và Node trên `k8s-w1`: `argocd.lab.internal` 200, `hairpin-check.lab.internal` 404 từ Envoy. Service Envoy `externalTrafficPolicy: Local` không chặn traffic từ pod tới IP LoadBalancer.
- [x] 6. Name constraints: `Certificate` `evil.example.com` và đối chứng `nc-control.lab.internal` từ `lab-ca`, `openssl s_server` trong pod, `hostAliases`. Kiểm: JVM, Node từ chối `evil`, chấp nhận đối chứng.
  - Kết quả: máy chủ TLS là pod Node (`serve.mjs`, SNI) thay cho `openssl s_server` (image có sẵn, PSS restricted). JDK 25: `CertPathValidatorException: name constraints check failed`; Node 24/26: `permitted subtree violation`; `nc-control.lab.internal` 200.
- [x] 7. Kết ticket: dọn sandbox, `code-review`, số đo vào `docs/experiments/`, sửa `cluster-entry.md`, `helm-chart.md`, ADR-0014, Bài học.
  - Kết quả: sandbox và Bundle thử đã gỡ; 9 app `Synced/Healthy`. Số đo ở [bản ghi G0, mục 6](../../../experiments/2026-11-g0.md#6-phân-phối-trust-bằng-trust-manager-jvm-node-hairpin-name-constraints), probe ở `docs/experiments/2026-11-g0-07-probes/`. Sửa `cluster-entry.md`, `helm-chart.md`, `gitops-argocd.md`, `keycloak.md`, mục chưa xác minh của ADR-0014, bảng [bằng chứng cửa vào cụm](../../../experiments/2026-11-cluster-entry.md).

## Kết quả

- Bằng chứng: [bản ghi G0, mục 6](../../../experiments/2026-11-g0.md#6-phân-phối-trust-bằng-trust-manager-jvm-node-hairpin-name-constraints) và các dòng G0-07 trong [bằng chứng cửa vào cụm](../../../experiments/2026-11-cluster-entry.md).
- `gitops`: `e5858be` (app `trust-manager` wave 4), `672b854` (Bundle `lab-trust`, `lab-root`), `9e39bd9` (ghi kết quả PKCS12), `49f0851` (sửa theo review). 9 app `Synced/Healthy`.
- `docs`: chưa commit (repo còn thay đổi khác của chủ repo, xem đề xuất commit ở cuối).
- Ma trận truy vết: không có dòng tương ứng (ticket hạ tầng, như G0-03..06).
- Chuyển cho ticket sau:
  - G0-10: namespace `keycloak` gắn nhãn `trust.lab.internal/inject: "true"`; `BackendTLSPolicy` trỏ ConfigMap `lab-root` (key `ca.crt`). Chạy lại dòng "Trust ở Node" bằng discovery `openid-client` tới `auth.lab.internal`.
  - G0-22: chart `app` mount `projected` (`lab-trust` key `bundle.p12`; `lab-root` key `ca.crt` → `lab-root-ca.pem`), không `optional`; `JAVA_TOOL_OPTIONS` không cần mật khẩu; namespace service mang nhãn trust (do `platform` gắn).
  - G0-34: diễn tập cụm trắng có trust-manager (cainjector điền `caBundle` của webhook có kịp trước wave 5 không; review điểm 4); RAM trust-manager sau 24 giờ.

## Review

`code-review` (high) trên `gitops` `74472df..9e39bd9` ra 7 điểm. Claude sửa 5 (chủ repo giao cả ticket), bỏ qua 2:

1. **Không Bundle nào ghi key `ca.crt`** mà `BackendTLSPolicy` đòi (CRD v1.6.1: thiếu key là `InvalidCACertificateRef`); lab-trust lại chứa cả CA công khai. Sửa: `lab-root` ghi `ca.crt`, chart đổi tên khi mount; chạy lại Node 26: 200.
2. **Bundle không có `Prune=false`**: commit lỡ xóa Bundle thì ConfigMap đích ở mọi namespace mất. Sửa: thêm annotation.
3. **Comment "empty keystore" sai** so với số đo. Sửa.
4. **Cụm trắng chưa thử** với webhook trust-manager (`failurePolicy: Fail`, CA do cainjector điền sau). Bỏ qua ở đây, chuyển G0-34.
5. **Webhook 1 replica, `failurePolicy: Fail`** chặn sync Bundle khi pod chết. Sửa: ghi lệch chuẩn ở app và `cluster-entry.md`.
6. **Root chép tay từ `platform` sang `gitops`**, không có kiểm lệch. Bỏ qua: fingerprint ghi trong `kustomization.yaml`, xoay root là việc hiếm và có runbook.
7. **Health của Bundle chưa kiểm phía âm.** Sửa: `argocd admin settings resource-overrides health` cho `Synced=False` → `Degraded`.

## Bài học

- Tài liệu chính thức và hành vi thật có thể lệch nhau, và chỉ đối chứng âm mới bắt được: JDK 25 thiếu file truststore không "hỏng hết" mà lặng lẽ quay về `cacerts`, nên lỗi chỉ lộ ở host nội bộ. Hệ quả thiết kế: mount bắt buộc để hỏng sớm (pod kẹt `ContainerCreating`) thay vì hỏng một nửa.
- Tham số "an toàn" có thể vô hiệu: `profile: Modern2023` không đổi được byte nào khi mật khẩu rỗng. Đọc file sinh ra (`openssl pkcs12 -info`) trước khi tin cấu hình.
- Câu chuyện kể được: "Tôi phân phối CA nội bộ cho pod JVM và Node bằng trust-manager mà không sửa code, chứng minh bằng pod thật rằng JDK 25 và Node từ chối chứng chỉ do chính CA của lab cấp cho tên ngoài name constraints, và phát hiện JDK quay về cacerts khi thiếu truststore, nên chart bắt mount phải có."
