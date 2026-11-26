# Runbook: vào Admin Console của Keycloak

Admin Console và realm `master` không mở qua Gateway `edge`: route `auth.lab.internal` chỉ có `/realms/commerce-hub`, `/resources/`, `/.well-known/`. Đường vào duy nhất là `kubectl port-forward`. Hostname riêng `kc-admin.lab.internal` **Hoãn tới G7** (spec G0, mục "Sửa phạm vi 2026-11-15").

- Ticket: [G0-10](../.scratch/g0-platform/issues/10-keycloak.md) bước 4. Chuẩn: [keycloak.md](../standards/keycloak.md) mục "Hostname, TLS, reverse proxy".
- Phiên bản: Keycloak và Keycloak Operator **26.8.2**. CR: `gitops/infra/keycloak/keycloak.yaml`.
- Đo ngày 2026-11-26.

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

`frontendUrl` của `master` là **trạng thái đặt tay trong DB, không nằm trong Git.** Dựng lại DB `keycloak` thì phải đặt lại (mục kế tiếp). Ticket 11 xét đưa nó vào YAML nếu keycloak-config-cli quản lý cả `master`.

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

## Dùng `kcadm.sh` thay Admin Console

Khi trang quản trị không vào được, gọi `kcadm.sh` trong pod tới `http://localhost:8080`. Đường này không phụ thuộc hostname. Sau khi đã xóa `temp-admin`, dùng admin cố định. `kcadm` sẽ hỏi mật khẩu, nên chạy với `exec -it`:

```bash
kubectl -n keycloak exec -it keycloak-0 -- bash -c '
K=/opt/keycloak/bin/kcadm.sh; C=/tmp/kc.cfg; trap "rm -f $C" EXIT
$K config credentials --config $C --server http://localhost:8080 --realm master --user <ADMIN>
$K get realms --config $C --fields realm,enabled'
```

`kcadm` đăng nhập bằng password grant, nên không dùng được OTP. Admin hiện tại không có OTP nên chạy được. Nếu sau này bật MFA cho admin (G7, cùng hostname `kc-admin.`) thì `kcadm` bị từ chối; khi đó tự động hóa phải dùng client service account riêng (ticket 11 lo cho keycloak-config-cli).

## Sự cố

| Hiện tượng | Nguyên nhân | Cách xử lý |
|---|---|---|
| `/admin/` chuyển sang `https://auth.lab.internal/admin/…` | CR thiếu `hostname.admin` | Kiểm `kubectl -n keycloak get pod keycloak-0 -o jsonpath='{.spec.containers[0].env[?(@.name=="KC_HOSTNAME_ADMIN")].value}'` |
| Console tải được, đăng nhập bị đẩy sang `auth.lab.internal/realms/master/…` (404) | Realm `master` thiếu `frontendUrl`, ví dụ sau khi dựng lại DB | Chạy lệnh ở mục "Lần đầu dựng" |
| Trang "HTTPS required" | Không đi qua `port-forward` (request tới từ địa chỉ ngoài) | Dùng `port-forward` |
| `kcadm` báo `HTTP 401` ngay sau khi đổi `frontendUrl` | Token cũ mang `iss` cũ | Đăng nhập `kcadm` lại |
| Đổi cổng 8180 | Có hai chỗ ghi cứng | Sửa `hostname.admin` trong CR và `frontendUrl` của `master` cùng lúc |
