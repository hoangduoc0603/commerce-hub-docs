# Bản ghi: realm `commerce-hub` dạng code

Ticket [G0-11](../.scratch/g0-platform/issues/11-realm-as-code.md). Bằng chứng theo các dòng "Realm dạng code", "Refresh rotation", "Brute force" trong bảng "Bằng chứng cần có" của [keycloak.md](../standards/keycloak.md), cộng `aud` và `iss` của token client credentials (story 29). Đo ngày **2026-11-27 từ 01:10 đến 02:40 UTC** (sáng cùng ngày giờ Việt Nam) trên cụm `homelab`: Kubernetes 1.37.2, Argo CD 3.6.1, Keycloak và Keycloak Operator 26.8.2, keycloak-config-cli **6.6.0** (image `6.6.0-26.8.1`).

## Bối cảnh

- `gitops` từ `772cfb6` tới `41add37`. Realm ở `infra/keycloak/realm/commerce-hub.yaml`, đưa vào ConfigMap bằng `configMapGenerator` (tên có hash). Job `keycloak-config-cli` là hook `PostSync` của app `keycloak`.
- Job đăng nhập bằng client `keycloak-config-cli` của realm `master` (client credentials). Client này tạo một lần bằng `scripts/bootstrap-keycloak-config-cli.sh`, do chủ repo chạy vì cần mật khẩu admin `master`. Secret của nó và secret của client `smoke-test` là hai SealedSecret.
- Đường đi: pod Job trong namespace `keycloak` → `keycloak-service:8080` (NetworkPolicy cho pod cùng namespace, G0-10 bước 7). Phép đo token đi đúng đường production: Mac → Tailscale → `gw` → Envoy `edge` → Keycloak.
- Mailpit chưa cài trên `gw`. Chủ repo quyết định bỏ qua tiêu chí email trong ticket này.

## Giả thuyết

1. keycloak-config-cli 6.5.1 (bản `keycloak.md` ghi) chạy được với Keycloak 26.8.2.
2. Client service account trong `master` chỉ có role của client `commerce-hub-realm` là đủ cho Job, kể cả bước đọc phiên bản qua `/admin/serverinfo`.
3. Chạy lại Job khi file không đổi thì không có gì thay đổi; sửa tay trên server thì lần chạy sau ghi đè.
4. Hook `PostSync` có `BeforeHookCreation` cho Argo CD biết đúng kết quả của Job vừa tạo.
5. Token client credentials của `smoke-test` có `aud` là `commerce-hub-api` và `iss` là `https://auth.lab.internal/realms/commerce-hub`.
6. Brute force khóa tạm sau 5 lần sai (BR-02). Dùng lại refresh token cũ thì nhận `invalid_grant`.

## Cách đo

- Đọc mã và tài liệu: `CHANGELOG.md`, `README.md`, `docs/SKIP_SERVER_INFO.md` ở tag `v6.6.0` của keycloak-config-cli; ở tag 26.8.2 của `keycloak`: `AdminRoot.java`, `ServerInfoAdminResource.java`, `MigrateTo26_8_2.java`, `Constants.java`, `Profile.java`, `RealmRepresentation.java`, `kubernetes.adoc`; `kcadm` 26.8.2 (giải nén jar trong pod) để tìm biến môi trường; tag và digest trên Docker Hub; trang `sync-waves.md` ở tag v3.6.1 của Argo CD.
- Trạng thái realm: admin API qua `kubectl port-forward svc/keycloak-service 8180:8080`, token của client `keycloak-config-cli`. Mỗi lần chụp lưu bảy file đã chuẩn hóa bằng `jq -S`: realm (bỏ attribute checksum), clients, groups, client-scopes, roles, components, authentication flows. So hai lần chụp bằng `diff`.
- Số lệnh ghi: admin event của realm `commerce-hub` từ mốc trước khi sync (realm bật `adminEventsEnabled`).
- Kích hoạt Job: patch trường `operation` của Application `keycloak` (như nút Sync). Thời điểm Job xong lấy từ `kubectl get job -w --output-watch-events`, thời điểm Argo CD xong lấy từ `status.operationState.finishedAt`, cộng log của `argocd-application-controller`.
- Đăng nhập người dùng: script Python (stdlib) mô phỏng trình duyệt trên form của client `account-console` (Authorization Code + PKCE S256) qua `https://auth.lab.internal`. User thử tạo tạm bằng admin API với mật khẩu ngẫu nhiên, xóa ngay sau phép đo. Event đọc qua `GET /admin/realms/commerce-hub/events`.
- RAM và CPU của Job: `kubectl top pod` mỗi 2 s trong lúc Job chạy.

## Số đo

### Phiên bản keycloak-config-cli

| Bản | Build với client Keycloak | Ngày | Ghi chú |
|---|---|---|---|
| 6.5.1 | tối đa 26.5.5 (`6.5.1-26.5.5`) | 2026-05-22 | Không có trong ma trận test 26.6 trở lên |
| 6.6.0 | 26.8.1 (`6.6.0-26.8.1`, digest index `1fafe082…`, amd64 và arm64) | 2026-11-24 | CHANGELOG: từ 26.6.4 Keycloak trả 403 khi cập nhật role `realm-management`, bản này bỏ qua các role đó; thêm hỗ trợ 26.8.1 |

Chọn 6.6.0. Image chạy user `65534`, Java 21.0.13.

### Đăng nhập của Job

| Lần | Kết quả | Nguyên nhân |
|---|---|---|
| 1 (client mới tạo, không thêm scope) | Job lỗi sau 120 s: `Could not connect to keycloak in 120 seconds: HTTP 401 Unauthorized`. Log Keycloak vẫn cấp token cho client (dòng cảnh báo `full-scope-allowed`) | Từ 26.8.2, `AdminRoot` từ chối (401) token không có scope `kc-admin-api` khi bật `admin.audienceCheckEnabled` (mặc định `true`). Migration `MigrateTo26_8_2` chỉ gắn scope này cho `admin-cli`, `security-admin-console` và client admin tạm |
| 2 (thêm default scope `kc-admin-api`, tắt full scope, map role vào scope) | Job xong sau 7 s (công cụ chạy 2,05 s) | Token có `scope: kc-admin-api …`, `aud` gồm `http://localhost:8180/admin/realms/master` và `commerce-hub-realm` |

- `/admin/serverinfo` chỉ trả phiên bản khi người gọi có `manage-realm` trên realm `master` (`ServerInfoAdminResource.java`). Job khai `KEYCLOAK_SKIPSERVERINFO=true` và `KEYCLOAK_VERSION=26.8.2`; log ghi `Server info unavailable. Using version: 26.8.2`.
- Quyền của client sau bootstrap: 21 role của `commerce-hub-realm` (thiếu `impersonation`) cộng `default-roles-master`. Gọi admin API bằng token của nó: `GET /admin/realms/commerce-hub` 200 (104 khóa); `GET /admin/realms/master/users` và `/clients` 403; `GET /admin/realms/master` lại trả **200 với 6 khóa**: Keycloak trả bản rút gọn của realm cho mọi admin. Phép kiểm đầu tiên của script dùng endpoint này nên báo nhầm. Script giờ kiểm bằng `users` của `master`.
- Lần chạy đầu của script cũng báo "thành công" giả: lỗi 401 nằm trong `echo "$(…)"`, mà `set -e` không dừng khi lệnh lỗi nằm trong tham số. Đã sửa: gán vào biến trước rồi mới in.

### Idempotent và ghi đè

| Lần | Kích hoạt | So bảy file với lần trước | Admin event của lần chạy |
|---|---|---|---|
| 1 | Sync tay | (realm rỗng → có cấu hình) | 6: CREATE CLIENT 1, CREATE GROUP 1, UPDATE CLIENT 1, UPDATE REALM 3 |
| 2 | Sync tay, Git không đổi | **Giống hệt** | 6: UPDATE REALM 2, UPDATE CLIENT 2, UPDATE PROTOCOL_MAPPER 1, **DELETE CLIENT_SCOPE_CLIENT_MAPPING 1** |
| 3 | Auto-sync sau khi khai thêm scope `service_account` (`08c9919`) | `defaultClientScopes` của `smoke-test` có thêm `service_account` trong file, server đã có sẵn | (không đo) |
| 4 | Sync tay, Git không đổi | **Giống hệt** lần 2 | 3: UPDATE REALM 2, UPDATE CLIENT 1 |

- Lần 2: Keycloak tự gắn scope `service_account` cho client có service account, file chỉ khai `basic`. Mỗi lần chạy công cụ gỡ scope này ra rồi Keycloak gắn lại, nên trạng thái cuối giống hệt mà vẫn có lệnh xóa. Khai `service_account` trong file thì hết.
- Lần 4 vẫn có 3 lệnh ghi mà không đổi trạng thái: công cụ luôn PUT realm (hai lần: cấu hình và attribute remote state) và PUT client. "Không đổi gì" ở đây là trạng thái không đổi, không phải không có lệnh ghi.
- Cache tắt (`IMPORT_CACHE_ENABLED=false`). Nếu bật (mặc định), công cụ lưu checksum của file vào realm và bỏ qua cả lần chạy khi file không đổi, nên sửa tay sẽ không bao giờ bị ghi đè.

Ghi đè, sửa tay qua admin API (cùng lệnh Admin Console gửi) rồi sync tay:

| Trường | Sau khi sửa tay | Sau sync |
|---|---|---|
| `smoke-test.directAccessGrantsEnabled` | `true` | `false` |
| `smoke-test.standardFlowEnabled` | `true` | `false` |
| Mapper `audience-commerce-hub-api` | đã xóa | có lại (id mới) |
| Realm `failureFactor` | 30 | 5 |
| `smoke-test.description` (không khai trong file) | `sửa tay 2026-11-27` | **giữ nguyên** |

So với lần 4 (bỏ qua `id`): sáu file giống hệt, `clients.json` chỉ khác ở `description`. Công cụ chỉ quản lý trường được khai trong file.

User thêm tay vào group `ops-admin` vẫn là thành viên sau một lần Job chạy lại: công cụ không đụng tới thành viên của group khi file không khai user.

### Hook của Argo CD

Hook `PostSync`, `backoffLimit: 0`, Job tên cố định `keycloak-config-cli`.

| Chính sách xóa | Job trước đó | Job mới xong | Argo CD xong | Argo CD báo |
|---|---|---|---|---|
| `BeforeHookCreation` | Failed | 02:23:22 | 02:23:16 | **Failed** ("Job has reached the specified backoff limit", tức trạng thái của Job cũ) |
| `BeforeHookCreation` | Complete | 02:24:45 | 02:24:51 | Succeeded (đúng) |
| `BeforeHookCreation` | Complete | 02:33:16 | 02:33:10 | **Succeeded trước khi Job mới chạy xong 6 s** |
| `HookSucceeded,BeforeHookCreation`, lần chuyển tiếp | Complete (từ chính sách cũ) | chưa xong khi Argo CD báo | 02:35:50 | Succeeded quá sớm (như dòng trên) |
| `HookSucceeded,BeforeHookCreation` | không còn (đã xóa khi thành công) | 02:36:08 | 02:36:13 | Succeeded (đúng), Job bị xóa |
| `HookSucceeded,BeforeHookCreation` | không còn | 02:36:31 | 02:36:36 | Succeeded (đúng), Job bị xóa |
| `HookSucceeded,BeforeHookCreation` | không còn | (lần kiểm group) | 02:40:08 | Succeeded |

Log controller của lần 02:33: `waiting for deletion of hook`, rồi `job.batch/keycloak-config-cli created`, rồi `Reached expected number of succeeded pods`, cả ba trong giây 02:33:10. Argo CD đọc trạng thái của Job cũ cùng tên. `generateName` (cách docs Argo CD gợi ý để tạo lại hook mỗi lần) không dùng được vì kustomize 5.8 báo `missing metadata.name`.

### Token client credentials của `smoke-test` (qua `auth.lab.internal`)

| Trường | Giá trị |
|---|---|
| `alg` | `RS256` |
| `iss` | `https://auth.lab.internal/realms/commerce-hub` |
| `aud` | `commerce-hub-api` (chỉ một giá trị) |
| `azp`, `client_id` | `smoke-test` |
| `exp - iat` | 300 s |
| `realm_access`, `resource_access` | không có |
| Refresh token | không có |

Đối chứng: secret sai trả `unauthorized_client`; secret đúng mà dùng `grant_type=password` trả `unauthorized_client` ("Client not allowed for direct access grants").

### Refresh token dùng một lần

User thử đăng nhập qua form của `account-console`: access token 300 s, refresh token 1 800 s (SSO Session Idle).

| Bước | Kết quả |
|---|---|
| Refresh bằng RT1 | 200, nhận RT2 khác RT1 |
| Refresh lại bằng RT1 | 400 `invalid_grant`, "Maximum allowed refresh token reuse exceeded" |
| Refresh bằng RT2 (hợp lệ) sau đó | 400 `invalid_grant`, "Session doesn't have required client" |

Khi thấy refresh token bị dùng lại, Keycloak hủy luôn phiên của client đó, nên cả RT2 hợp lệ cũng chết.

### Brute force (BR-02)

User thử, 31 lần sai mật khẩu qua form, mỗi lần cách nhau 1,2 s (lớn hơn Quick Login Check 1 000 ms, để chỉ đo khóa theo số lần sai), sau đó một lần đúng mật khẩu.

| Đo | Kết quả |
|---|---|
| Event | `LOGIN_ERROR:invalid_user_credentials` 5; `USER_DISABLED_BY_TEMPORARY_LOCKOUT` 1 (ngay sau lần sai thứ 5); `LOGIN_ERROR:user_temporarily_disabled` 27 (26 lần sai còn lại cộng lần đúng) |
| `attack-detection` | `numFailures` 5, `numTemporaryLockouts` 1, `disabled` true, `failedLoginNotBefore - lastFailure` = **900 s** |
| Mật khẩu đúng trong lúc khóa | Bị từ chối |
| IP trong event | `10.20.0.5` (IP thật sau SNAT của `gw`, như G0-10) |

### Tài nguyên của Job

| Đo | Giá trị |
|---|---|
| RAM | 137–140 Mi (limit 384 Mi, heap mặc định của JVM 25% limit) |
| CPU | đỉnh 516m lúc khởi động JVM, sau đó dưới 10m |
| Thời gian | Job 5–7 s; công cụ tự báo 2,05 s |

## Kết luận

1. **Sai.** Phải lên 6.6.0. 6.5.1 chỉ test tới 26.5.5, và CHANGELOG 6.6.0 ghi Keycloak 26.6.4+ trả 403 cho thao tác trên role `realm-management` mà bản cũ vẫn gửi.
2. **Sai hai chỗ.** (a) Keycloak 26.8.2 bắt token gọi admin API phải có scope `kc-admin-api`. Client admin tạo tay sau khi nâng không tự có, nên 401. Đây là thay đổi bảo mật của bản vá 26.8.2, CHANGELOG của keycloak-config-cli chưa nhắc. (b) Không có `manage-realm` trên `master` thì `/admin/serverinfo` không trả phiên bản, nên phải `KEYCLOAK_SKIPSERVERINFO` kèm `KEYCLOAK_VERSION`, và nhớ đổi biến này khi nâng Keycloak.
3. **Đúng, với hai điều kiện.** Phải tắt cache. Phải khai đủ giá trị mà Keycloak tự thêm (scope `service_account`), không thì có lệnh gỡ rồi gắn lại ở mỗi lần chạy. Công cụ vẫn PUT realm và client mỗi lần, nhưng trạng thái không đổi. Ghi đè chỉ áp cho trường có trong file.
4. **Sai.** Với tên Job cố định, Argo CD 3.6.1 có lúc đọc trạng thái của Job cũ: một lần báo lỗi giả, một lần báo thành công trước khi Job chạy xong. Xóa Job ngay khi thành công (`HookSucceeded`) làm mất Job cũ ở đường thành công, nên hết đọc nhầm. Còn rủi ro ở lần sync ngay sau một lần lỗi (Job lỗi được giữ để đọc log). Đổi lại, log của lần chạy thành công mất cùng Job tới khi có Loki (ticket 14).
5. **Đúng.**
6. **Đúng, và chặt hơn dự kiến ở refresh token.** Dùng lại refresh token không chỉ bị từ chối mà còn hủy phiên client. Hai request refresh song song từ BFF sẽ đăng xuất người dùng; BFF phải tuần tự hóa refresh trong một phiên (`keycloak.md`, case C5.3).

Chưa đo: email tới Mailpit và RAM của Mailpit (Mailpit chưa cài trên `gw`, chủ repo bỏ qua ở ticket này). Chưa sửa bằng Admin Console thật mà sửa qua admin API (cùng endpoint).
