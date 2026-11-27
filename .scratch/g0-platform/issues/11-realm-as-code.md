# 11: Realm `commerce-hub` dạng code

Status: resolved
Blocked by: 10
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

Realm `commerce-hub` là YAML trong `gitops`, áp bằng Job keycloak-config-cli. Bản G0 có: chính sách brute force theo BR-02, SMTP tới Mailpit `10.20.0.5:1025`, một client test confidential chỉ bật client credentials có mapper Audience `commerce-hub-api`, và một group admin. Secret của client là `SealedSecret`. Tài khoản admin của chủ repo tạo tay qua admin console mở bằng `kubectl port-forward` theo runbook. Client `argocd`, `grafana` cho SSO và hostname `kc-admin.` hoãn tới G7 (quyết định 2026-11-15, spec G0 mục "Sửa phạm vi 2026-11-15"). Client của `seller-web`, `admin-web` và theme đăng ký thuộc G1. Theo [keycloak.md](../../../standards/keycloak.md), [ADR-0008](../../../adr/0008-keycloak-authn-only-members-replicated-via-kafka.md).

## Mục tiêu học

- Realm dạng code: idempotent, ghi đè sửa tay.
- OAuth2 client credentials và audience trong access token.

## Tiêu chí nghiệm thu

- [x] Chạy Job hai lần liên tiếp: lần hai không đổi gì; sửa tay một client trên UI rồi sync lại thì bị ghi đè. (2026-11-27: bảy bản chụp realm, client, group, scope, role, component, flow giống hệt giữa hai lần; lần lặp vẫn có 3 lệnh PUT không đổi trạng thái. Sửa `directAccessGrantsEnabled`, `standardFlowEnabled`, mapper audience, `failureFactor` qua admin API, cùng endpoint Admin Console gọi; sync lại thì cả bốn về giá trị trong file. Trường không khai trong file thì giữ nguyên.)
- [x] Token client credentials của client test có `aud` chứa `commerce-hub-api`; `iss` là `https://auth.lab.internal/realms/commerce-hub`. (Client `smoke-test`, lấy qua `auth.`: `aud` chỉ là `commerce-hub-api`, RS256, 300 s, không refresh token, không role.)
- [ ] Email thử từ realm tới Mailpit, xem được qua API Mailpit; đo RAM Mailpit. **Bỏ qua (chủ repo, 2026-11-27):** Mailpit chưa cài trên `gw`. `smtpServer` đã khai trong realm; cách kiểm ghi ở ticket 34 mục "Chuyển từ G0-11".
- [x] 31 lần sai mật khẩu liên tiếp với user thử thì có event khóa tạm. (5 `invalid_user_credentials`, `USER_DISABLED_BY_TEMPORARY_LOCKOUT` ngay sau lần thứ 5, khóa 900 s; 26 lần sai còn lại và lần đúng mật khẩu đều `user_temporarily_disabled`.)
- [x] Refresh token dùng lại sau khi đã refresh thì nhận `invalid_grant`. ("Maximum allowed refresh token reuse exceeded"; Keycloak hủy luôn phiên client, RT mới cũng bị từ chối.)
- [x] Runbook "tạo tài khoản admin trong realm". ([keycloak-admin.md](../../../runbooks/keycloak-admin.md#tạo-tài-khoản-admin-trong-realm-commerce-hub), cùng các mục realm dạng code, client `keycloak-config-cli`, xoay secret. Các bước trên UI chưa chạy thử; user thêm vào `ops-admin` bằng API vẫn còn sau một lần Job chạy lại.)

## Lộ trình

Chủ repo giao cả ticket (`/implement`, 2026-11-27). Bước cần mật khẩu admin `master` do chủ repo chạy.

- [x] 1. SealedSecret `keycloak-config-cli` và `realm-commerce-hub` (256 bit hex, pipe thẳng sang `kubeseal`), script `scripts/bootstrap-keycloak-config-cli.sh`. gitops `772cfb6`. Chủ repo chạy script.
- [x] 2. Realm `realm/commerce-hub.yaml` (brute force BR-02, token 5 phút, refresh dùng một lần, event 7 ngày, SMTP Mailpit, client `smoke-test`, group `ops-admin`), Job keycloak-config-cli 6.6.0 hook `PostSync`. gitops `239f32a`. Job đầu lỗi 401: Keycloak 26.8.2 bắt token gọi admin API có scope `kc-admin-api`. Sửa script (`5190b6f`, `f288109`), chủ repo chạy lại; Job xong sau 7 s.
- [x] 3. Đo idempotent, ghi đè, hook. Khai scope `service_account` để lần lặp không gỡ rồi gắn lại (`08c9919`); hook `HookSucceeded,BeforeHookCreation` vì Argo CD 3.6.1 đọc trạng thái Job cũ cùng tên (`41add37`).
- [x] 4. Đo token client credentials, refresh token, brute force qua `auth.lab.internal`.
- [x] 5. Kết ticket: [bản ghi G0-11](../../../experiments/2026-11-g0-11-realm-as-code.md), runbook, `keycloak.md`, bàn giao sang ticket 29, 32, 34. Ma trận truy vết không có dòng cho hạ tầng G0, không thêm dòng.
- [x] 6. Review hai trục (Standards, Spec). Sửa: wave `-1` cho SealedSecret và ConfigMap realm, khai `clientSessionIdleTimeout`/`clientSessionMaxLifespan` (gitops `daad08f`, Job chạy lại, trạng thái không đổi); câu "log chỉ còn trong Loki" sai vì ticket 14 chưa làm; runbook ghi rõ các bước UI chưa chạy thử; `gitops-argocd.md` ghi race của hook tên cố định (Job migrate của chart `app` cùng rủi ro, chưa xử lý). Để nguyên: script bootstrap không refactor (chạy lại cần mật khẩu admin `master`); group `ops-admin` là tên kỹ thuật của Keycloak, không thêm vào GLOSSARY; BR-02 mới đo phần khóa sau 5 lần sai, chưa đo Quick Login Check và việc đăng nhập đúng đưa bộ đếm về 0.

## Bài học

- Bản vá cũng đổi hợp đồng. Keycloak 26.8.2 (bản vá của 26.8) thêm điều kiện: token gọi admin API phải có scope `kc-admin-api`. Client admin có từ trước được migration tự gắn, client tạo sau thì không, và triệu chứng chỉ là "401" chung chung. Phải đọc `AdminRoot.java` mới thấy.
- Kiểm tra cũng cần được kiểm tra. Script bootstrap hai lần báo "đạt" sai: lỗi trong `$(…)` không làm `set -e` dừng, và `GET /admin/realms/master` trả 200 bản rút gọn cho mọi admin. Một phép kiểm chỉ có giá trị khi đã thấy nó đỏ đúng lúc.
- "Idempotent" phải định nghĩa bằng số đo. Trạng thái không đổi (diff bảy bản chụp bằng 0) nhưng công cụ vẫn gửi lệnh ghi; cache mặc định thì lại bỏ qua cả lần chạy, làm mất khả năng ghi đè sửa tay. Hai mặc định của công cụ (cache bật, BeforeHookCreation của Argo CD) đều sai cho mục tiêu này, chỉ thấy khi đo.
- Refresh token dùng một lần ở Keycloak là phát hiện đánh cắp, không chỉ từ chối: dùng lại token cũ thì cả phiên client bị hủy. Đây là lý do BFF phải tuần tự hóa refresh (C5.3).
