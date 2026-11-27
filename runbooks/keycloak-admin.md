# Runbook: quản trị Keycloak (Admin Console, realm dạng code)

Admin Console và realm `master` không mở qua Gateway `edge`: route `auth.lab.internal` chỉ có `/realms/commerce-hub`, `/resources/`, `/.well-known/`. Đường vào duy nhất là `kubectl port-forward`. Hostname riêng `kc-admin.lab.internal` **Hoãn tới G7** (spec G0, mục "Sửa phạm vi 2026-11-15").

- Ticket: [G0-10](../.scratch/g0-platform/issues/10-keycloak.md) bước 4 (Admin Console), [G0-11](../.scratch/g0-platform/issues/11-realm-as-code.md) (realm dạng code, tài khoản admin trong realm). Chuẩn: [keycloak.md](../standards/keycloak.md) mục "Hostname, TLS, reverse proxy", "Realm dạng code".
- Phiên bản: Keycloak và Keycloak Operator **26.8.2**, keycloak-config-cli **6.6.0**. CR: `gitops/infra/keycloak/keycloak.yaml`; realm: `gitops/infra/keycloak/realm/commerce-hub.yaml`; Job: `gitops/infra/keycloak/keycloak-config-cli.yaml`.
- Đo ngày 2026-11-26 (Admin Console), 2026-11-27 (realm dạng code, [bản ghi G0-11](../experiments/2026-11-g0-11-realm-as-code.md)).

## Vào Admin Console

```bash
kubectl -n keycloak port-forward svc/keycloak-service 8180:8080
```

Mở <http://localhost:8180/admin/> rồi đăng nhập bằng admin của realm `master`. Mọi URL, kể cả trang đăng nhập, phải nằm trên `localhost:8180`.

- Cổng **8180** cố định, vì hai cấu hình dưới đây ghi cứng nó. Không dùng 8080, vì Spring Boot trên Mac (`hello` `bootTestRun`) giữ cổng đó.
- `port-forward` đi vào pod từ `127.0.0.1`. Realm `master` đặt `sslRequired=external`, nên coi kết nối này là nội bộ và cho dùng HTTP thường.
- `port-forward` không bị NetworkPolicy chặn.

## Vì sao cần hai cấu hình

Keycloak 26 (hostname v2, mã `HostnameV2Provider.java`) sinh mỗi URL theo một trong bốn loại:

| Loại | Giá trị | Dùng cho |
|---|---|---|
| `FRONTEND` | Attribute `frontendUrl` của realm nếu có, nếu không thì `hostname` (`https://auth.lab.internal`) | Trang đăng nhập, `iss` của token, discovery |
| `ADMIN` | `hostname-admin` nếu có, nếu không thì như `FRONTEND` | Admin Console, chuyển hướng ở `/admin/`, API quản trị |
| `BACKEND` | Như `FRONTEND` (`hostname-backchannel-dynamic=false`) | Token endpoint, JWKS gọi từ trong cụm |
| `LOCAL_ADMIN` | URL của chính request, host đổi thành `localhost` | Đường quản trị nội bộ |

Admin Console nhận `adminBaseUrl` (loại `ADMIN`) và `serverBaseUrl` (loại `FRONTEND`, nơi keycloak-js gửi người dùng đi đăng nhập), theo mã `AdminConsole.java`. Số đo theo từng cấu hình:

| Cấu hình | `/admin/` chuyển tới | `serverBaseUrl` | Kết quả |
|---|---|---|---|
| Chỉ `hostname` | `https://auth.lab.internal/admin/master/console/` | `https://auth.lab.internal` | Không vào được (edge chặn) |
| + `hostname.admin: http://localhost:8180` (CR) | `http://localhost:8180/admin/master/console/` | `https://auth.lab.internal` | Console tải được, nhưng đăng nhập bị đẩy sang `auth.` |
| + `frontendUrl=http://localhost:8180` trên realm `master` | như trên | `http://localhost:8180` | Đăng nhập và form action đều trên `localhost:8180` |

`frontendUrl` chỉ áp cho realm `master`. Realm `commerce-hub` vẫn có `issuer` là `https://auth.lab.internal/realms/commerce-hub`.

`frontendUrl` của `master` là **trạng thái đặt tay trong DB, không nằm trong Git.** Dựng lại DB `keycloak` thì phải đặt lại (mục kế tiếp). Không đưa vào YAML: lý do ở mục [Realm master và keycloak-config-cli](#realm-master-và-keycloak-config-cli).

## Lần đầu dựng, hoặc sau khi mất DB `keycloak`

Lần khởi động đầu, operator tạo Secret `keycloak-initial-admin` và đưa vào pod qua `KC_BOOTSTRAP_ADMIN_USERNAME`/`KC_BOOTSTRAP_ADMIN_PASSWORD`. Keycloak tạo user `temp-admin` khi realm `master` chưa có admin. Lúc này Admin Console chưa vào được (chưa có `frontendUrl`), nên dùng `kcadm.sh` ngay trong pod. Mật khẩu lấy từ biến môi trường của pod, không đi ra ngoài:

```bash
kubectl -n keycloak exec keycloak-0 -- bash -c '
K=/opt/keycloak/bin/kcadm.sh; C=/tmp/kc.cfg; trap "rm -f $C" EXIT
KC_CLI_PASSWORD="$KC_BOOTSTRAP_ADMIN_PASSWORD" $K config credentials --config $C --server http://localhost:8080 --realm master --user "$KC_BOOTSTRAP_ADMIN_USERNAME"
$K update realms/master --config $C -s attributes.frontendUrl=http://localhost:8180'
```

**Lệnh nào gọi sau `update` trong cùng phiên sẽ nhận `HTTP 401`.** Lý do: đổi `frontendUrl` là đổi `iss` của realm `master`, nên token mà `kcadm` đang cầm (cấp với `iss=https://auth.lab.internal/realms/master`) không còn hợp lệ. Cứ đăng nhập lại là xong. Mọi phiên Admin Console đang mở cũng bị đăng xuất vì cùng lý do. Đã gặp ngày 2026-11-26.

Kiểm:

```bash
curl -s http://localhost:8180/realms/master/.well-known/openid-configuration | jq -r .issuer        # http://localhost:8180/realms/master
curl -s http://localhost:8180/realms/commerce-hub/.well-known/openid-configuration | jq -r .issuer  # https://auth.lab.internal/realms/commerce-hub
```

Sau đó tạo admin cố định và xóa `temp-admin`, theo checklist "Đổi tài khoản admin tạm" của [keycloak.md](../standards/keycloak.md). Admin của realm `master` chỉ dùng mật khẩu, **không bật MFA**: đây là lệch chuẩn có chủ đích, chủ repo quyết định ngày 2026-11-27, lý do ở mục "Lệch chuẩn có chủ đích ở home lab" của keycloak.md.

1. Đăng nhập Admin Console bằng `temp-admin`. Lấy mật khẩu mà không in ra màn hình: `kubectl -n keycloak get secret keycloak-initial-admin -o jsonpath='{.data.password}' | base64 -d | pbcopy`.
2. Realm `master`, vào **Users → Create user**: đặt username, điền email. Tab **Credentials → Set password**, tắt *Temporary*. Tab **Role mapping → Assign role**: `admin`.
3. Đăng xuất, đăng nhập bằng user mới để chắc mật khẩu và quyền đều đúng.
4. **Users**: xóa `temp-admin`. Secret `keycloak-initial-admin` còn lại là thông tin đăng nhập chết: Keycloak chỉ tạo admin tạm khi realm `master` chưa có admin.

Kiểm (không cần đăng nhập Keycloak): `P=$(kubectl get cluster pg-main -n postgres -o jsonpath='{.status.currentPrimary}')` rồi `kubectl exec -n postgres "$P" -c postgres -- psql -d keycloak -c "select u.username from user_entity u join realm r on r.id = u.realm_id where r.name = 'master'"`. Đạt khi chỉ còn admin cố định (ngày 2026-11-27: `kevin`).

Cuối cùng, dựng lại realm `commerce-hub`: chạy script bootstrap (mục [Client keycloak-config-cli](#client-keycloak-config-cli)) rồi sync app `keycloak`. Tài khoản admin trong realm (mục [Tạo tài khoản admin trong realm](#tạo-tài-khoản-admin-trong-realm-commerce-hub)) phải tạo lại tay.

## Dùng `kcadm.sh` thay Admin Console

Khi trang quản trị không vào được, gọi `kcadm.sh` trong pod tới `http://localhost:8080`. Đường này không phụ thuộc hostname. Sau khi đã xóa `temp-admin`, dùng admin cố định. `kcadm` sẽ hỏi mật khẩu, nên chạy với `exec -it`:

```bash
kubectl -n keycloak exec -it keycloak-0 -- bash -c '
K=/opt/keycloak/bin/kcadm.sh; C=/tmp/kc.cfg; trap "rm -f $C" EXIT
$K config credentials --config $C --server http://localhost:8080 --realm master --user <ADMIN>
$K get realms --config $C --fields realm,enabled'
```

`kcadm` đăng nhập bằng password grant, nên không dùng được OTP. Admin hiện tại không có OTP nên chạy được. Nếu sau này bật MFA cho admin (G7, cùng hostname `kc-admin.`) thì `kcadm` bị từ chối. Tự động hóa không phụ thuộc chuyện này: Job keycloak-config-cli đăng nhập bằng client service account riêng (mục kế tiếp).

## Realm dạng code (keycloak-config-cli)

Realm `commerce-hub` là file `gitops/infra/keycloak/realm/commerce-hub.yaml`. Job `keycloak-config-cli` (hook `PostSync` của app `keycloak`) áp file vào Keycloak qua admin API sau **mỗi** lần sync thành công:

- Đổi file và push: ConfigMap đổi tên (hash), app `OutOfSync`, auto-sync chạy Job.
- Sửa tay trên Admin Console không làm app `OutOfSync`. Lần sync kế tiếp ghi đè **những trường có trong file**; trường không khai được giữ nguyên (đo: `description` của client không bị xóa). Muốn giữ một thay đổi thì đưa vào file.
- Chạy lại mà không đổi Git: nút **Sync** của app `keycloak` trên Argo CD, hoặc `argocd app sync keycloak`.
- Công cụ chỉ xóa client, group, role, scope do nó tạo (remote state lưu trong attribute `de.adorsys.keycloak.config.state-*` của realm). User và thành viên group không bị đụng tới.

Job thành công bị xóa ngay sau khi Argo CD đọc kết quả (`hook-delete-policy: HookSucceeded,BeforeHookCreation`, lý do ghi trong file Job). Log của lần thành công mất cùng Job tới khi Loki thu log pod (ticket 14, chưa làm). Job **lỗi** được giữ lại:

```bash
kubectl -n keycloak logs job/keycloak-config-cli | grep -v '^\s*at '
```

Job lỗi thì sync của app `keycloak` lỗi, Argo CD thử lại 5 lần (backoff tới 3 phút) rồi dừng. Sửa xong thì Sync lại.

### Realm master và keycloak-config-cli

Realm `master` **không** quản lý bằng keycloak-config-cli. Hai thứ của `master` nằm ngoài Git: attribute `frontendUrl` và client `keycloak-config-cli`. Lý do:

- Job đăng nhập vào chính realm `master`. Đổi `frontendUrl` của `master` là đổi `iss`, nên token Job đang cầm mất hiệu lực ngay giữa lần chạy (đã gặp với `kcadm`, mục "Lần đầu dựng").
- Client mà Job dùng để đăng nhập không thể do chính Job tạo ra lần đầu. Cấp cho Job quyền trên `master` để nó tự quản lý client của mình thì Job có quyền admin toàn server.
- Realm `master` chỉ để quản trị Keycloak (keycloak.md mục "Realm dạng code"), không có cấu hình ứng dụng.

### Client keycloak-config-cli

Job đăng nhập bằng client credentials của client `keycloak-config-cli` trong realm `master`:

- Confidential, chỉ bật service account, `fullScopeAllowed=false`.
- Default client scope **`kc-admin-api`**. Từ Keycloak 26.8.2 admin API trả 401 cho token không có scope này (`AdminRoot.java`). Migration 26.8.2 chỉ tự gắn nó cho `admin-cli` và `security-admin-console`, client tạo tay phải tự thêm.
- Service account có mọi role của client `commerce-hub-realm` trừ `impersonation`, tức quản trị đúng realm `commerce-hub`. Đọc user hay client của `master` bị 403. Riêng `GET /admin/realms/master` vẫn trả bản rút gọn (tên realm, vài trường hiển thị) cho mọi admin; đó là hành vi của Keycloak, không phải lỗ quyền.
- Secret: Secret `keycloak-config-cli` (key `KEYCLOAK_CLIENTSECRET`), seal trong `gitops/infra/keycloak/keycloak-config-cli.sealedsecret.yaml`.

Tạo hoặc cập nhật client (lần đầu dựng, sau khi mất DB `keycloak`, hoặc sau khi xoay secret). Cần admin realm `master`; `kcadm` hỏi mật khẩu:

```bash
cd gitops && scripts/bootstrap-keycloak-config-cli.sh <ADMIN>
```

Script đọc secret từ Secret trong cụm, đưa vào pod qua stdin (không in ra, không nằm trong tham số lệnh), tạo hoặc cập nhật client, gắn scope và role, rồi tự kiểm bằng chính client đó. Đạt khi hai dòng cuối là:

```text
realms/commerce-hub: commerce-hub
realms/master/users: 403 (đúng)
```

Sau đó Sync app `keycloak` để Job chạy.

### Xoay secret

| Secret | Bước |
|---|---|
| `keycloak-config-cli` | 1. Seal lại theo [sealing-key.md](sealing-key.md) (256 bit hex, pipe thẳng sang `kubeseal`), commit, push. Sync đầu tiên sau đó **sẽ lỗi 401** vì Keycloak còn secret cũ. 2. Chạy script bootstrap. 3. Sync lại. |
| `realm-commerce-hub` (`SMOKE_TEST_CLIENT_SECRET`) | Seal lại, commit, push. Job ghi secret mới vào client `smoke-test`. Cập nhật secret ở repo `e2e` (ticket 31). |

Lệnh seal (thay tên Secret và key):

```bash
openssl rand -hex 32 | tr -d '\n' \
  | kubectl create secret generic keycloak-config-cli -n keycloak --from-file=KEYCLOAK_CLIENTSECRET=/dev/stdin --dry-run=client -o yaml \
  | kubeseal --format yaml
```

Dán kết quả vào file `.sealedsecret.yaml` tương ứng, giữ phần comment đầu file.

## Tạo tài khoản admin trong realm `commerce-hub`

Người vận hành lab có tài khoản trong realm `commerce-hub`, thuộc group `ops-admin`. Group này khai trong file realm. Từ G7, client `argocd` và `grafana` map nó sang quyền admin của Argo CD và Grafana. Đây không phải Platform Admin (role `platform-admin`, G1). File realm không chứa user nào, nên tài khoản này tạo tay. Job không xóa nó và không gỡ nó khỏi group (đo 2026-11-27 bằng user tạo qua admin API).

Các bước UI dưới đây **chưa chạy thử** (G0-11 kiểm tương đương bằng admin API); chạy lần đầu thì sửa runbook theo màn hình thật.

1. Vào Admin Console (mục đầu), đăng nhập bằng admin realm `master`.
2. Đổi realm (góc trên bên trái) sang **commerce-hub**. **Users → Create user**:
   - *Username*, *Email* (realm cho đăng nhập bằng email), bật *Email verified*.
   - *Join groups*: chọn `ops-admin`.
3. Tab **Credentials → Set password**, tắt *Temporary*. Realm G0 chưa có `passwordPolicy` (G1); vẫn dùng mật khẩu dài, ngẫu nhiên, lưu trong trình quản lý mật khẩu.
4. Kiểm: mở <https://auth.lab.internal/realms/commerce-hub/account/> (qua `edge`), đăng nhập bằng email và mật khẩu vừa đặt. Vào được trang Account là đạt. Nhập sai 5 lần liên tiếp sẽ bị khóa 15 phút (BR-02); chờ hết 15 phút, hoặc mở khóa bằng công tắc *Temporarily locked* ở trang chi tiết user (**chưa kiểm trên UI**; API tương đương đã dùng ở G0-11: `DELETE /admin/realms/commerce-hub/attack-detection/brute-force/users/{id}`).

Kiểm không cần đăng nhập Keycloak: `P=$(kubectl get cluster pg-main -n postgres -o jsonpath='{.status.currentPrimary}')` rồi `kubectl exec -n postgres "$P" -c postgres -- psql -d keycloak -c "select u.username from user_entity u join user_group_membership m on m.user_id = u.id join keycloak_group g on g.id = m.group_id join realm r on r.id = u.realm_id where r.name = 'commerce-hub' and g.name = 'ops-admin'"`.

## Sự cố

| Hiện tượng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `/admin/` chuyển sang `https://auth.lab.internal/admin/…` | CR thiếu `hostname.admin` | Kiểm `kubectl -n keycloak get pod keycloak-0 -o jsonpath='{.spec.containers[0].env[?(@.name=="KC_HOSTNAME_ADMIN")].value}'` |
| Console tải được, đăng nhập bị đẩy sang `auth.lab.internal/realms/master/…` (404) | Realm `master` thiếu `frontendUrl`, ví dụ sau khi dựng lại DB | Chạy lệnh ở mục "Lần đầu dựng" |
| Trang "HTTPS required" | Không đi qua `port-forward` (request tới từ địa chỉ ngoài) | Dùng `port-forward` |
| `kcadm` báo `HTTP 401` ngay sau khi đổi `frontendUrl` | Token cũ mang `iss` cũ | Đăng nhập `kcadm` lại |
| Đổi cổng 8180 | Có hai chỗ ghi cứng | Sửa `hostname.admin` trong CR và `frontendUrl` của `master` cùng lúc |
| Job `keycloak-config-cli` lỗi `Could not connect to keycloak in 120 seconds: HTTP 401 Unauthorized` | Client `keycloak-config-cli` chưa có, sai secret (vừa xoay mà chưa chạy bootstrap), hoặc thiếu scope `kc-admin-api` | Chạy script bootstrap, rồi Sync |
| Job lỗi `HTTP 403` | Client thiếu role của `commerce-hub-realm` | Chạy script bootstrap (gán lại role) |
| Job lỗi biến `$(env:…)` không có | Thiếu key trong Secret `realm-commerce-hub`, hoặc SealedSecret chưa giải mã | `kubectl -n keycloak get secret realm-commerce-hub -o jsonpath='{.data}' \| jq keys` |
| Sửa tay trên Admin Console rồi mất sau một lần sync | Trường đó có trong file realm, Job ghi đè (đúng thiết kế) | Đưa thay đổi vào `realm/commerce-hub.yaml` |
| Argo CD báo hook Failed nhưng log Job mới không lỗi, hoặc báo Succeeded trước khi Job mới chạy xong | Argo CD 3.6.1 đọc trạng thái Job cũ cùng tên. Chỉ còn xảy ra ở lần sync ngay sau một Job lỗi | Sync lại |
