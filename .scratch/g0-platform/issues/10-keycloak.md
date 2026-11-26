# 10: Keycloak production sau `edge` (bản mỏng)

Status: resolved
Blocked by: 08
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

Keycloak Operator 26.8.2 chạy 1 instance Keycloak ở chế độ production, dùng image chính thức (ghim phiên bản), DB `keycloak` trên `pg-main` (đã tạo ở ticket 08, nối thẳng `-rw`). `auth.lab.internal` qua Gateway `edge` chỉ mở `/realms/commerce-hub`, `/resources/`, `/.well-known/`. `edge` kết thúc TLS và nói HTTP với Keycloak trong cụm. Trang admin chỉ vào bằng `kubectl port-forward`. Theo [keycloak.md](../../../standards/keycloak.md), [cluster-entry.md](../../../standards/cluster-entry.md).

Ghi chú về cạnh chặn: bỏ 07, vì lý do duy nhất cần bundle của trust-manager là `BackendTLSPolicy`, nay đã hoãn sang G7.

## Mục tiêu học

- IdP sau reverse proxy: hostname, proxy kết thúc TLS, và vì sao không tin `X-Forwarded-For` do client đặt.

## Thu hẹp 2026-11-15

Theo quyết định D5 (spec G0 mục "Sửa phạm vi 2026-11-15").

- Giữ: Keycloak Operator, 1 instance chế độ production, DB `keycloak` trên `pg-main`, hostname `auth.lab.internal` qua `edge` với danh sách path công khai ở trên, realm dạng code (ticket 11).
- Hoãn tới G1: image build riêng chứa theme và `passwordBlacklist`, làm cùng luồng đăng ký nhà bán. G0 dùng image chính thức.
- Hoãn tới G7: hostname admin `kc-admin.lab.internal` (trước mắt dùng `kubectl port-forward`); re-encrypt Envoy → Keycloak cổng 8443 bằng `BackendTLSPolicy` (trước mắt `edge` kết thúc TLS, HTTP trong cụm).

Tiêu chí hoãn tới G7:

- `BackendTLSPolicy` `Accepted`; tắt TLS phía Keycloak thì `edge` trả 503.

## Tiêu chí nghiệm thu

- [x] CR `Keycloak` `Ready=True`; log không có "dev mode". (2026-11-26: `Ready=True HasErrors=False`, `Profile prod activated`, args `--verbose start`.)
- [x] `/realms/master/`, `/admin/`, `/metrics` từ ngoài cụm qua `auth.` trả 404 hoặc 403. (404 cả ba, kể cả lách bằng `..`, `%2F`, `//`.)
- [x] Keycloak chỉ nghe HTTP trong cụm, nhưng URL nó sinh ra khi gọi qua `auth.` là `https://auth.lab.internal/...` (`iss` của token kiểm ở ticket 11). (Discovery qua `auth.`: `issuer`, `authorization_endpoint`, `jwks_uri`, form action của trang đăng nhập đều `https://auth.lab.internal/realms/commerce-hub/…`.)
- [x] Đăng nhập sai với `X-Forwarded-For: 6.6.6.6`: event ghi IP khác `6.6.6.6`. (Trước sửa: `6.6.6.6`; sau `ClientTrafficPolicy`: `10.20.0.5`.)
- [x] Health `UP` và metric `keycloak_user_events` qua cổng 9000. (`keycloak_user_events_total{error,event,realm}`.)
- [x] Vào được admin console bằng `kubectl port-forward`; runbook ghi lệnh và cấu hình hostname cần cho việc này ([keycloak-admin.md](../../../runbooks/keycloak-admin.md)). **Đã xác minh:** đúng là bị redirect; `hostname-admin` chưa đủ, cần thêm `frontendUrl` của realm `master`. Câu gốc: chỉ đặt `hostname` thì admin console có thể redirect về `https://auth.lab.internal/admin`, đường `edge` chặn; có thể phải đặt `hostname-admin` trỏ về địa chỉ `port-forward`.

## Lộ trình

Duyệt 2026-11-26. Đã chốt khi duyệt: vendor manifest operator vào `gitops` (không dùng remote base); giữ `update.strategy` mặc định `RecreateOnImageChange` (1 instance, ghi lý do lệch chuẩn trong CR); đổi admin tạm sang admin cố định có MFA ở bước 4. Sửa 2026-11-27: chủ repo chọn admin `master` chỉ dùng mật khẩu, không MFA (ghi ở mục lệch chuẩn của keycloak.md).

- [x] 1. Namespace `keycloak` (PSA `restricted`, nhãn route) và app `keycloak-operator` wave 6: vendor 4 CRD (`Prune=false,Delete=false`) và `kubernetes.yml` 26.8.2, ghim digest image operator. Kiểm: `kubectl -n keycloak rollout status deploy/keycloak-operator`; app `Synced/Healthy`. Xong 2026-11-26, gitops `1acbde0`: app Synced/Healthy sau ~50 s, pod chạy digest `f9b9a2be…`, 0 restart, PSA restricted không cảnh báo.
- [x] 2. App `keycloak` wave 8, chỉ có SealedSecret `keycloak-db` seal lại từ `pg-main-keycloak` (runbook `pg-main-them-service.md`). Kiểm: Secret `keycloak-db` có type `kubernetes.io/basic-auth`. Xong 2026-11-26, gitops `21e3166`: app Synced/Healthy, hash username và password khớp bản ở `postgres`.
- [x] 3. CR `Keycloak` production tối thiểu: image ghim digest, `db` (`sslmode=require`, `poolMaxSize: 20`), `hostname` + `strict`, `http.httpEnabled`, `proxy.headers: xforwarded`, `ingress.enabled: false`, 1,5 Gi. Kiểm: `Ready=True`; log không "dev mode"; DB `keycloak` có bảng. Xong 2026-11-26, gitops `4883a8f`: Ready=True sau 52 s (kéo image 11 s, build lại + khởi động, Quarkus "started in 4.5s"), "Profile prod activated", 0 dòng dev mode, 101 bảng, 4 kết nối đều TLS, RAM 615Mi lúc vừa lên, operator 205Mi.
- [x] 4. Admin console bằng `port-forward` (thử điểm chưa xác minh về redirect, thêm `hostname.admin` nếu cần); admin cố định có MFA, xóa admin tạm; tạo realm `commerce-hub` rỗng; runbook. Kiểm: đăng nhập được `http://localhost:8180/admin` (sửa 2026-11-27: cổng 8180 thay vì 8080, vì Spring Boot trên Mac giữ 8080). Đang làm 2026-11-26: gitops `fe424a1` (`hostname.admin: http://localhost:8180`); `frontendUrl` của master đặt bằng kcadm; realm `commerce-hub` đã tạo; trang đăng nhập và form action trên `localhost:8180`; runbook `docs/runbooks/keycloak-admin.md`. Xong 2026-11-27: realm `master` chỉ còn `kevin` (`admin`, mật khẩu; không MFA theo quyết định của chủ repo), `temp-admin` đã xóa (kiểm bằng `user_entity`).
- [x] 5. HTTPRoute `auth.lab.internal` (3 `PathPrefix`, HSTS). Kiểm: discovery 200 với `issuer` `https://auth.lab.internal/realms/commerce-hub`; `/admin/`, `/realms/master/`, `/metrics` 404. Xong 2026-11-27, gitops `2ee5a9e`: route Accepted/ResolvedRefs; discovery 200 với `issuer` đúng; HSTS có; trang đăng nhập và `/resources/` 200; `/admin/`, `/realms/master/`, `/metrics`, `/health/ready`, `/`, `/realms/`, `/realms/commerce-hubX` đều 404; lách `..` 404, `%2F` bị Envoy unescape rồi 307 sang `/realms/master/…` và 404, `//` 404, http 301 sang https.
- [x] 6. `X-Forwarded-For` đỏ → xanh: đăng nhập sai với `X-Forwarded-For: 6.6.6.6`, rồi ClientTrafficPolicy `earlyRequestHeaders.remove` trên Gateway `edge`. Kiểm: log `LOGIN_ERROR` có `ipAddress="10.20.0.5"`. Xong 2026-11-27, gitops `13a2f2a`. Đỏ: header giả cho `ipAddress="6.6.6.6"` (Quarkus ForwardedParser lấy phần tử đầu), không giả cho `10.20.0.5`. Xanh: ClientTrafficPolicy `edge` Accepted; giả `6.6.6.6`, `6.6.6.6, 7.7.7.7`, `Forwarded`, `X-Forwarded-Host` đều ghi `10.20.0.5`; `issuer`, Argo CD, `hello /livez`, trang đăng nhập không đổi.
- [x] 7. NetworkPolicy cổng HTTP chỉ từ `envoy-gateway-system`, thêm `proxy-trusted-addresses`. Kiểm: pod trong `hello` gọi `keycloak-service:8080` timeout; qua `auth.` vẫn 200. Xong 2026-11-27, gitops `8955cdc`. Đỏ: pod ở `default` đọc `/realms/master` qua `:8080` (200); port-forward kèm `6.6.6.6` ghi `6.6.6.6`. Xanh: pod `default` → 8080 timeout (`000`); pod trong ns `keycloak` → 8080 vẫn 200 (Job ticket 11); port-forward kèm header giả ghi `127.0.0.1`; qua `edge` vẫn `10.20.0.5`; cổng 9000 cố ý vẫn mở tới ticket 13.
- [x] 8. Cổng 9000: `metrics-enabled`, `event-metrics-user-enabled`, `http-metrics-histograms-enabled`, `http-max-queued-requests`. Kiểm: `/health/ready` `UP`; `/metrics` có `keycloak_user_events_total`. Xong 2026-11-27, gitops `8d98d64`: `/health/ready` UP (4 check); `keycloak_user_events_total{error="user_not_found",event="login",realm="commerce-hub"} 2.0`; 414 bucket histogram; 1 649 series; `/metrics`, `/health/ready` qua `auth.` 404; RAM lúc rảnh 508Mi, operator 226Mi.
- [x] 9. Kết ticket: số đo vào `docs/experiments/`, sửa `keycloak.md`, tick tiêu chí, ma trận truy vết, Bài học. Xong 2026-11-27: [bản ghi G0-10](../../../experiments/2026-11-g0-10-keycloak.md); sửa `keycloak.md`, `cluster-entry.md`; ma trận truy vết không có dòng cho hạ tầng G0 (F1.1b cần luồng G1 nên vẫn "Chưa làm"), không thêm dòng. Review hai trục (Standards, Spec) xong; sửa theo review: runbook bỏ bước OTP, hai mục checklist của `keycloak.md` đạt một phần thì để chưa tick, bàn giao cổng 9000 và ServiceMonitor sang ticket 13, `jwk-set-uri` nội bộ sang ticket 29, dòng "Tài nguyên" (k6) sang ticket 34.

## Bài học

- Lỗ hổng `X-Forwarded-For` là thật, không phải lý thuyết. Envoy chỉ nối IP vào cuối header, còn Keycloak (Quarkus `ForwardedParser`) đọc phần tử đầu, nên client tự đặt `6.6.6.6` là event ghi `6.6.6.6`: brute force theo IP và audit bị qua mặt. Sửa ở biên bằng `ClientTrafficPolicy.headers.earlyRequestHeaders.remove`, chạy trước khi Envoy nối, sau sửa ghi `10.20.0.5`. Lớp thứ hai: NetworkPolicy (trước đó pod bất kỳ gọi thẳng 8080 được) và `proxy-trusted-addresses`. Câu chuyện phỏng vấn: vấn đề, cách làm, số đo 6.6.6.6 → 10.20.0.5.
- `iss` gắn chặt với hostname. Chỉ đặt `hostname-admin` thì Admin Console vẫn gửi người dùng đi đăng nhập theo URL `FRONTEND`, nên phải thêm `frontendUrl` cho riêng realm `master`. Ngay khi đổi, token đang cầm mất hiệu lực (`kcadm` nhận 401). Đọc `HostnameV2Provider.java` nhanh hơn đoán.
- Không tin mặc định của bên thứ ba. Operator không đặt `securityContext` nào nên PSA `restricted` từ chối pod; tag `26.8.2` bị đẩy lại sau 7 ngày; ghim digest mà không đặt `startOptimized: false` thì operator chạy `--optimized` trên image chưa build. Cả ba chỉ thấy khi đọc manifest, CRD và lịch sử registry.
