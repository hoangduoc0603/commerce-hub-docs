# Chuẩn: Keycloak (IdP, OIDC client, xác minh JWT)

- Ngày tra: 2026-11-12
- Phiên bản áp dụng: Keycloak **26.8.2** (phát hành 2026-11-05) và Keycloak Operator 26.8.2 (CR `k8s.keycloak.org/v2beta1`); PostgreSQL 17 trên CloudNativePG (Keycloak 26.8 hỗ trợ PostgreSQL 14–18); Spring Security 7.1.2 (theo Spring Boot 4.1.2); keycloak-config-cli 6.5.1
- Phạm vi: CR `Keycloak` và HTTPRoute của nó, image Keycloak tùy biến, cấu hình realm `commerce-hub` dạng code trong repo `gitops`, client OIDC của Next.js (seller app, admin) và của service, cấu hình resource server (`spring.security.oauth2.resourceserver.*`) ở gateway và mọi service. Yêu cầu liên quan: F1.1a–F1.1e, F1.2a–F1.2c (BR-07), F1.3, N11, BR-04

## Checklist

### Cài trên Kubernetes bằng Operator
- [ ] Cài Operator kiểu namespace-scoped, **ghim** phiên bản: `kubectl apply -k 'github.com/keycloak/keycloak-k8s-resources/kubernetes?ref=26.8.2'` (qua Argo CD). Một phiên bản Operator chạy đúng một phiên bản Keycloak. Không dùng Helm chart của Operator (mới ở mức experimental). [Keycloak Operator – Installation](https://www.keycloak.org/operator/installation)
- [ ] Dùng image tùy biến đã tối ưu: Containerfile chạy `kc.sh build` với `db=postgres`, `health-enabled=true`, `metrics-enabled=true`, `tracing-enabled=true`, `features=user-event-metrics`; CR đặt `spec.image` và để `startOptimized` mặc định. Với image tùy biến, mọi build option truyền qua CR bị bỏ qua. Theo [`container-image.md`](container-image.md) khi build. [Keycloak – Running in a container](https://www.keycloak.org/server/containers), [Operator – Custom images](https://www.keycloak.org/operator/customizing-keycloak), [Tracing](https://www.keycloak.org/observability/tracing)
- [ ] Không bao giờ dùng `start-dev` ngoài máy cá nhân; Operator chạy `start`. `start-dev` có mặc định không an toàn. [Keycloak – Running in a container](https://www.keycloak.org/server/containers)
- [ ] `spec.resources` đặt tường minh, request = limit memory (lab: 1,5 Gi). Heap mặc định là 70% limit, nên thiếu limit thì heap không xác định; nếu bỏ trống Operator đặt request 1700 MiB, limit 2 GiB. [Keycloak – Containers: memory](https://www.keycloak.org/server/containers), [Operator – Advanced configuration](https://www.keycloak.org/operator/advanced-configuration)
- [ ] `spec.update.strategy: Auto` để Operator tự kiểm và rolling update khi lên bản vá cùng `major.minor`; mặc định `RecreateOnImageChange` gây downtime mỗi lần đổi image. Rolling update cần ≥ 2 replica (xem lệch chuẩn). [Operator – Rolling updates](https://www.keycloak.org/operator/rolling-updates)
- [ ] Đổi tài khoản admin tạm trong Secret `<cr>-initial-admin` thành admin cố định có MFA ngay sau lần chạy đầu, rồi xóa admin tạm. [Operator – Basic deployment](https://www.keycloak.org/operator/basic-deployment)

### Database
- [ ] Database và user riêng cho Keycloak trong cụm CloudNativePG, tham chiếu bằng `spec.db.usernameSecret`/`passwordSecret`. Operator không tạo DB; DB mẫu trong tài liệu chỉ dùng thử. [Operator – Basic deployment](https://www.keycloak.org/operator/basic-deployment), [Keycloak – Database](https://www.keycloak.org/server/db)
- [ ] `db-pool-max-size` hạ từ mặc định 100 xuống khoảng 20 và tính vào `max_connections` của PostgreSQL. 100 kết nối mỗi pod sẽ ăn hết giới hạn của cụm Postgres dùng chung. [Keycloak – Database](https://www.keycloak.org/server/db)
- [ ] Backup DB Keycloak nằm trong lịch backup chung của CloudNativePG (N10); mất DB là mất mọi Account. Migration schema ở bản nâng cấp do Keycloak tự chạy; diễn tập nâng cấp trên bản sao trước (xem [`db-migration.md`](db-migration.md)). [Keycloak – Database](https://www.keycloak.org/server/db)

### Hostname, TLS, reverse proxy
- [ ] `spec.hostname.hostname` là URL đầy đủ (`https://auth.<domain-lab>`), giữ `hostname-strict=true`, `hostname-backchannel-dynamic=false`. URL cố định để `iss` trong token không phụ thuộc header của request. [Keycloak – Hostname v2](https://www.keycloak.org/server/hostname)
- [ ] TLS kiểu re-encrypt: Gateway API terminate TLS phía ngoài và mở TLS mới tới Keycloak (`spec.http.tlsSecret`); `spec.proxy.headers: xforwarded` (hoặc `forwarded`, theo đúng header gateway gửi) và `proxy-trusted-addresses` chỉ là dải IP của pod gateway. Sai cấu hình header thì Keycloak bị giả mạo địa chỉ. [Keycloak – Reverse proxy](https://www.keycloak.org/server/reverseproxy), [Operator – Basic deployment](https://www.keycloak.org/operator/basic-deployment)
- [ ] `spec.ingress.enabled: false`; HTTPRoute chỉ mở tiền tố `/realms/`, `/resources/`, `/.well-known/`; **không** mở `/admin/`, `/realms/master/`, `/metrics`, `/health` và không định tuyến cổng quản trị 9000. [Keycloak – Reverse proxy: exposed paths](https://www.keycloak.org/server/reverseproxy)
- [ ] Admin Console dùng `hostname-admin` riêng, chỉ truy cập qua Tailscale. [Keycloak – Production configuration](https://www.keycloak.org/server/configuration-production)
- [ ] Đặt `http-max-queued-requests` để quá tải thì trả 503 ngay thay vì xếp hàng vô hạn (mặc định không giới hạn). [Keycloak – Production configuration](https://www.keycloak.org/server/configuration-production)
- [ ] Giữ NetworkPolicy do Operator tạo và thêm luật: HTTPS chỉ từ namespace gateway và các service; cổng 9000 chỉ từ namespace `observability` và kubelet. [Operator – Advanced configuration: networkPolicy](https://www.keycloak.org/operator/advanced-configuration)

### Realm dạng code
- [ ] Ứng dụng dùng realm `commerce-hub`; realm `master` chỉ để quản trị Keycloak. Tài khoản quản trị Keycloak và Account của nhà bán không lẫn nhau.
- [ ] Cấu hình realm (client, scope, mapper, chính sách mật khẩu, brute force, timeout, SMTP) là file YAML trong repo `gitops`, áp bằng keycloak-config-cli chạy như Job của Argo CD (`import.remote-state.enabled=true`, `import.var-substitution.enabled=true`, secret lấy từ biến môi trường). Công cụ này áp lại được nhiều lần (idempotent) và chỉ xóa tài nguyên do nó quản lý. [keycloak-config-cli](https://github.com/adorsys/keycloak-config-cli)
- [ ] Ghim phiên bản keycloak-config-cli và chạy thử với Keycloak 26.8.2 (Testcontainers) trong CI trước khi nâng. Hỗ trợ 26.8 **chưa xác minh**: bản 6.5.1 ra 2026-05-22, nhánh chính đang build với Keycloak 26.7.4. [keycloak-config-cli releases](https://github.com/adorsys/keycloak-config-cli/releases)
- [ ] Client secret, mật khẩu SMTP không nằm trong Git dạng rõ (Sealed Secrets). Sửa realm bằng UI chỉ để thử nghiệm, sau đó đưa vào YAML; lần sync kế tiếp sẽ ghi đè.

### Account, Workspace và vai trò
- [ ] Account là user của realm, đăng nhập bằng email; bật **Verify email** (F1.1a) và **Forgot password** (F1.1b); SMTP trỏ Mailpit ở lab. [Keycloak – Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/index.html)
- [ ] Workspace, Member, vai trò (Owner, Quản lý, Vận hành, Kho, Kế toán) và phạm vi theo Shop/Warehouse nằm ở service `tenant`, không nằm trong token. Token chỉ dùng để biết Account nào (`sub`). Workspace đang làm việc truyền bằng header (ví dụ `X-Workspace-Id`); gateway hoặc service kiểm Member qua `tenant`, cache bị vô hiệu bằng event khi gỡ Member hay đổi vai trò. Đây là cách đạt BR-07 (hiệu lực trong 5 giây) mà không phải chờ token hết hạn.
- [ ] Platform Admin là realm role `platform-admin`, bắt buộc OTP, chỉ được cấp cho client `admin-web`; không phải Member của Workspace nào (GLOSSARY).
- [ ] Không bật tính năng Organizations ở P0 (xem bảng lựa chọn).

### Client OIDC
- [ ] `seller-web` và `admin-web` theo mẫu BFF: phần server của Next.js là **confidential client**, chỉ bật Standard Flow (Authorization Code) có PKCE `S256` bắt buộc (client policy `pkce-enforcer`), redirect URI chính xác, không wildcard. Token giữ ở server; trình duyệt chỉ có cookie phiên `HttpOnly`, `Secure`, `SameSite`. RFC 10017 khuyên mạnh BFF cho ứng dụng doanh nghiệp và ứng dụng có dữ liệu cá nhân. [IETF – OAuth 2.0 for Browser-Based Applications (RFC 10017)](https://datatracker.ietf.org/doc/draft-ietf-oauth-browser-based-apps/), [Keycloak – OIDC layers](https://www.keycloak.org/securing-apps/oidc-layers)
- [ ] Tắt Implicit Flow và Direct Access Grants (password grant) cho mọi client. RFC 9700 nói implicit "SHOULD NOT", password grant "MUST NOT". [Keycloak – OIDC layers](https://www.keycloak.org/securing-apps/oidc-layers)
- [ ] Client của web khai **Backchannel logout URL** trỏ vào BFF, để thu hồi phiên ở Keycloak (đăng xuất, khóa Account) xóa luôn phiên ở BFF. [Server Administration Guide – Backchannel logout](https://www.keycloak.org/docs/latest/server_admin/index.html)
- [ ] Service cần gọi service khác bằng danh tính riêng có client riêng chỉ bật Client Credentials (service account), quyền tối thiểu; không bật "Use refresh tokens for client credentials grant" (deprecated). [Keycloak – OIDC layers](https://www.keycloak.org/securing-apps/oidc-layers), [Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/index.html)
- [ ] Mapper **Audience** thêm `commerce-hub-api` vào access token của `seller-web`, `admin-web` và client service; resource server kiểm `aud`. Không có `aud` thì token cấp cho client khác cũng lọt qua. [Server Administration Guide – Audience support](https://www.keycloak.org/docs/latest/server_admin/index.html)

### Token, phiên, brute force
- [ ] Realm: Access Token Lifespan 5 phút; SSO Session Idle 30 phút; SSO Session Max 10 giờ; Client Session Idle/Max không lớn hơn giá trị SSO tương ứng. Token ngắn giới hạn thời gian một token bị lộ còn dùng được. [Server Administration Guide – Session and token timeouts](https://www.keycloak.org/docs/latest/server_admin/index.html)
- [ ] **Revoke Refresh Token** bật (refresh token dùng một lần, mỗi lần refresh nhận token mới). BFF tuần tự hóa việc refresh trong một phiên; hai request refresh song song bằng cùng refresh token thì một cái bị từ chối (đúng case token xoay vòng của C5.3). [Server Administration Guide – Refresh token rotation](https://www.keycloak.org/docs/latest/server_admin/index.html)
- [ ] Không cấp scope `offline_access` cho client web. Offline token không chịu SSO Session Idle/Max và còn hiệu lực sau khi đăng xuất. [Server Administration Guide – Offline access](https://www.keycloak.org/docs/latest/server_admin/index.html)
- [ ] Bật Brute Force Detection chế độ **Lockout temporarily** (mặc định tắt): Max Login Failures 30, Wait Increment 1 phút, Max Wait 15 phút, Failure Reset Time 12 giờ, Quick Login Check 1000 ms (giá trị mặc định của chế độ này). Khóa vĩnh viễn cho phép kẻ tấn công khóa tài khoản người khác. [Server Administration Guide – Brute force attacks](https://www.keycloak.org/docs/latest/server_admin/index.html)
- [ ] Bật lưu user event và admin event có thời hạn hết hạn, làm nguồn audit cho đăng nhập và thay đổi cấu hình (F1.3). [Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/index.html)

### Thu hồi phiên và token (F1.2c, F1.1e)
- [ ] Gỡ Member hoặc thu hẹp quyền: không động tới Keycloak; `tenant` phát event, cache quyền ở gateway/service bị xóa, kết nối SSE bị đóng; đo được ≤ 5 giây (BR-07).
- [ ] Khóa hoặc xóa Account, hay nghi lộ token: tắt user và gọi "Sign out all active sessions" qua Admin API (đặt not-before cho user); BFF nhận backchannel logout và xóa phiên. Access token đã phát vẫn hợp lệ tới hết hạn (≤ 5 phút), vì vậy gateway phải từ chối Account bị khóa dựa trên trạng thái trong `tenant`. [Server Administration Guide – Revoking active sessions](https://www.keycloak.org/docs/latest/server_admin/index.html)
- [ ] BFF gọi `/realms/commerce-hub/protocol/openid-connect/revoke` với refresh token khi người dùng đăng xuất. [Keycloak – OIDC layers](https://www.keycloak.org/securing-apps/oidc-layers)

### Resource server (Spring Security)
- [ ] `spring.security.oauth2.resourceserver.jwt.issuer-uri` bằng đúng URL công khai của realm; thêm `jwk-set-uri` trỏ địa chỉ nội bộ của Keycloak để service không phải đi vòng ra ngoài và không gọi IdP lúc khởi động. Spring vẫn so `iss` với `issuer-uri`. [Spring Security – OAuth 2.0 Resource Server JWT](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/jwt.html)
- [ ] `audiences: commerce-hub-api` và `jws-algorithms: RS256`; giữ validator mặc định (`iss`, `exp`, `nbf`, lệch đồng hồ 60 s). [Spring Security – Resource Server JWT](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/jwt.html)
- [ ] JWK Set được cache 5 phút (mặc định). Khi xoay khóa ký ở Keycloak, khóa cũ phải còn ở trạng thái passive ít nhất bằng Access Token Lifespan + 5 phút rồi mới xóa, để token đang lưu hành vẫn kiểm được. [Spring Security – JWK Set caching](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/jwt.html), [Server Administration Guide – Rotating keys](https://www.keycloak.org/docs/latest/server_admin/index.html)
- [ ] `JwtAuthenticationConverter` không biến realm role thành quyền trong Workspace; quyền nghiệp vụ lấy từ `tenant`. Gateway và từng service đều kiểm JWT (không tin header do gateway thêm).
- [ ] Test tự động (BR-04): token sai `aud`, hết hạn, từ realm khác, ký bằng khóa lạ → 401; Account không phải Member của Workspace trong header → 403.

### Giám sát
- [ ] `/health/started`, `/health/live`, `/health/ready` và `/metrics` trên cổng quản trị 9000; bật `http-metrics-histograms-enabled`; ServiceMonitor do Operator tạo (cần CRD ServiceMonitor ≥ v0.72.0). [Keycloak – Health](https://www.keycloak.org/observability/health), [Metrics](https://www.keycloak.org/observability/configuration-metrics), [Operator – Advanced configuration](https://www.keycloak.org/operator/advanced-configuration)
- [ ] `event-metrics-user-enabled=true` với `event-metrics-user-tags=realm` (mặc định). Thêm `clientId` hay `idp` làm tăng bộ nhớ và số series. [Keycloak – Event metrics](https://www.keycloak.org/observability/event-metrics)
- [ ] Log JSON (`log-console-output=json`, `log-console-json-format=ecs`) và tracing OTLP gửi tới Collector (`tracing-endpoint`, `tracing-protocol=http/protobuf`). Log tự kèm trace id khi bật tracing. Xem [`observability.md`](observability.md). [Keycloak – Logging](https://www.keycloak.org/server/logging), [Tracing](https://www.keycloak.org/observability/tracing)

## Lựa chọn và phương án đã loại

| Quyết định | Chọn | Loại | Lý do | Nguồn |
|---|---|---|---|---|
| Cài trên K8s | Keycloak Operator chính thức | Helm chart bên thứ ba; Helm chart của Operator | Operator do dự án Keycloak duy trì, có rolling update có kiểm tra, ServiceMonitor, NetworkPolicy; chart bên thứ ba đi sau bản Keycloak; chart của Operator mới experimental | [Operator – Installation](https://www.keycloak.org/operator/installation) |
| Mô hình multi-tenant (**nên viết ADR**) | Một realm; Keycloak chỉ xác thực Account; Workspace, Member, vai trò, phạm vi ở `tenant` | (a) Realm cho mỗi Workspace; (b) một realm + Organizations (Workspace = Organization) | (a) Một Account là Member của nhiều Workspace (GLOSSARY) sẽ bị nhân bản danh tính; 1.000 realm cần chỉnh cache và quản trị nặng. (b) Organizations là GA từ 26.0, có claim `organization` theo scope, nhưng claim chỉ đúng tại lúc phát token nên gỡ Member có hiệu lực sau tới 5 phút, trái BR-07; phạm vi theo Shop/Warehouse (F1.2b) không có chỗ tự nhiên. Có thể xét lại (b) khi làm SSO doanh nghiệp | [Server Administration Guide – Organizations](https://www.keycloak.org/docs/latest/server_admin/index.html), [Release notes 26.0](https://www.keycloak.org/docs/latest/release_notes/index.html) |
| Kiểu client cho Next.js (**nên viết ADR**) | BFF, confidential client | SPA public client giữ token trong trình duyệt; token-mediating backend | RFC 10017 xếp BFF an toàn nhất; app chứa dữ liệu người mua (N11) | [RFC 10017](https://datatracker.ietf.org/doc/draft-ietf-oauth-browser-based-apps/) |
| Realm dạng code | keycloak-config-cli (Job của Argo CD) | `KeycloakRealmImport`; CR `KeycloakOIDCClient` | `KeycloakRealmImport` chỉ tạo realm mới, không cập nhật hay xóa; CR client mới ở mức Preview trong 26.8 | [Operator – Realm import](https://www.keycloak.org/operator/realm-import), [Release notes 26.8](https://www.keycloak.org/docs/latest/release_notes/index.html) |
| Brute force | Khóa tạm thời | Khóa vĩnh viễn | Khóa vĩnh viễn biến tấn công dò mật khẩu thành tấn công từ chối dịch vụ lên Account | [Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/index.html) |
| Thu hồi quyền nhanh | Kiểm Member tại `tenant` mỗi request, cache bị xóa bằng event | Token rất ngắn (vài giây); introspection mỗi request | Token vài giây làm tải refresh tăng mạnh; introspection biến Keycloak thành điểm nghẽn của mọi request | [Keycloak – Sizing](https://www.keycloak.org/high-availability/multi-cluster/concepts-memory-and-cpu-sizing) |

## Lệch chuẩn có chủ đích ở home lab
- **Một instance Keycloak.** Production cần ≥ 2 instance, và rolling update cũng cần ≥ 2. Lab chạy 1 để tiết kiệm RAM; mỗi lần nâng cấp image sẽ có downtime đăng nhập (người đang có token vẫn gọi API được tới khi token hết hạn). Khi làm N15 cho đăng nhập thì tăng lên 2.
- **Bộ nhớ 1,5 Gi thay vì 2 GB** mà hướng dẫn container khuyên cho production nhỏ. Hướng dẫn sizing tính khoảng 1.250 MB cho một pod với 10.000 phiên cache; lab ít phiên hơn nhiều. Phải đo lại (bảng bên dưới).
- **Chứng chỉ TLS tự ký hoặc từ CA nội bộ** cho domain lab; trình duyệt và service phải tin CA này (truststore của Spring Boot qua SSL bundle).
- **Ngân sách RAM:** bảng ước lượng trong `platform/docs/homelab-hyperv.md` chưa có dòng cho Keycloak; khoảng 1,5 GB này lấy từ phần dành cho service.

## Bằng chứng cần có
Ghi vào `docs/experiments/` kèm ngày chạy.

| Kiểm tra | Lệnh / cách đo | Đạt khi |
|---|---|---|
| Keycloak chạy chế độ production | `kubectl get keycloak -n keycloak -o jsonpath='{.items[0].status.conditions}'`; log khởi động | `Ready=True`; log không có "dev mode"; dùng image đã build sẵn |
| Issuer đúng | `curl -s https://auth.<domain-lab>/realms/commerce-hub/.well-known/openid-configuration \| jq .issuer` | Bằng `issuer-uri` của service |
| Đường dẫn bị chặn | `curl -s -o /dev/null -w '%{http_code}' https://auth.<domain-lab>/admin/` và `/metrics` từ ngoài cụm | 404 hoặc 403 |
| Health và metric | `kubectl port-forward svc/<kc>-service 9000` rồi `curl localhost:9000/health/ready`, `curl localhost:9000/metrics \| grep keycloak_user_events` | `UP`; có metric event |
| Realm dạng code | Chạy Job keycloak-config-cli hai lần liên tiếp | Lần 2 không đổi gì; sửa tay một client trên UI rồi sync lại thì bị ghi đè |
| Resource server | Gọi API bằng token sai `aud`, hết hạn, realm khác | 401 cho cả ba (test tự động) |
| BR-07 | Script vòng lặp gọi API mỗi 200 ms bằng phiên của Member; Owner gỡ Member | Request bị từ chối đầu tiên ≤ 5 s sau lúc gỡ; SSE bị đóng |
| Refresh rotation | Dùng lại refresh token cũ sau khi đã refresh | Keycloak trả `invalid_grant` |
| Brute force | 31 lần sai mật khẩu liên tiếp | Có event khóa tạm; đăng nhập đúng bị từ chối trong thời gian chờ |
| Tài nguyên | `kubectl top pod -n keycloak` khi chạy k6 đăng nhập 5 lượt/s trong 10 phút | Ghi RAM và CPU thật; không OOMKilled; so với hướng dẫn sizing (1 vCPU cho 15 lượt đăng nhập bằng mật khẩu/s) |

## Nguồn
- Keycloak: [Downloads](https://www.keycloak.org/downloads) · [Release notes](https://www.keycloak.org/docs/latest/release_notes/index.html) · [Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/index.html) · [Production configuration](https://www.keycloak.org/server/configuration-production) · [Hostname v2](https://www.keycloak.org/server/hostname) · [Reverse proxy](https://www.keycloak.org/server/reverseproxy) · [Database](https://www.keycloak.org/server/db) · [Containers](https://www.keycloak.org/server/containers) · [Logging](https://www.keycloak.org/server/logging) · [Health](https://www.keycloak.org/observability/health) · [Metrics](https://www.keycloak.org/observability/configuration-metrics) · [Event metrics](https://www.keycloak.org/observability/event-metrics) · [Tracing](https://www.keycloak.org/observability/tracing) · [Sizing](https://www.keycloak.org/high-availability/multi-cluster/concepts-memory-and-cpu-sizing) · [OIDC layers](https://www.keycloak.org/securing-apps/oidc-layers)
- Keycloak Operator: [Installation](https://www.keycloak.org/operator/installation) · [Basic deployment](https://www.keycloak.org/operator/basic-deployment) · [Advanced configuration](https://www.keycloak.org/operator/advanced-configuration) · [Custom images](https://www.keycloak.org/operator/customizing-keycloak) · [Rolling updates](https://www.keycloak.org/operator/rolling-updates) · [Realm import](https://www.keycloak.org/operator/realm-import)
- [keycloak-config-cli](https://github.com/adorsys/keycloak-config-cli) (công cụ của adorsys, không thuộc dự án Keycloak)
- [Spring Security 7.1 – OAuth 2.0 Resource Server JWT](https://docs.spring.io/spring-security/reference/servlet/oauth2/resource-server/jwt.html)
- [IETF – OAuth 2.0 for Browser-Based Applications (RFC 10017, BCP 212)](https://datatracker.ietf.org/doc/draft-ietf-oauth-browser-based-apps/)
