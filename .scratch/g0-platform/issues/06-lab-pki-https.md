# 06: PKI của lab và HTTPS trên `edge`

Status: resolved
Blocked by: 04, 05
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

cert-manager (bật Gateway API) ký chứng chỉ wildcard `*.lab.internal` từ `ClusterIssuer lab-ca`, mà khóa intermediate của nó vào cụm dưới dạng `SealedSecret`. Gateway `edge` có listener HTTPS và route chuyển HTTP sang HTTPS. Argo CD mở được qua `https://argocd.lab.internal`. Thứ tự sync wave: CRD Gateway API → cert-manager → Gateway `edge`, `lab-ca`. Theo [ADR-0014](../../../adr/0014-lab-pki-and-dns.md), [cluster-entry.md](../../../standards/cluster-entry.md) và mục "App `platform`" của [gitops-argocd.md](../../../standards/gitops-argocd.md).

## Mục tiêu học

- Chuỗi tin cậy root → intermediate → leaf, và name constraints chặn gì.
- cert-manager cấp chứng chỉ cho Gateway.

## Tiêu chí nghiệm thu

- [x] `curl -sI http://app.lab.internal` trả `301` sang `https://`.
- [x] Safari, Chrome và `curl -v` mở `https://argocd.lab.internal` không cảnh báo; chuỗi là wildcard ← intermediate ← root. (Chrome, `curl -q -v`, SecTrust; Safari do chủ repo mở ngày 2026-11-15.)
- [x] Thử name constraints: chứng chỉ `evil.example.com` ký từ `lab-ca` bị Chrome, Safari, `curl` từ chối (JVM, Node kiểm ở ticket 07); client nào chấp nhận thì ghi vào lệch chuẩn. (Chrome, Safari, `curl`, SecTrust, OpenSSL đều từ chối; không client nào chấp nhận nên không có lệch chuẩn.)
- [x] Bootstrap lại từ cụm trắng: cert-manager không cần restart tay để thấy Gateway.
- [x] Argo CD: `server.insecure`, `url: https://argocd.lab.internal`; CLI dùng `--grpc-web`.

## Chuyển từ G0-05

- Gateway `edge` hiện có một listener `http` với `from: Selector` (tạm, cho app thử). Ticket này đổi nó sang `from: Same` + HTTPRoute redirect trong namespace `edge`, và thêm listener `https` mang selector nhãn `edge.lab.internal/routes: "true"`.
- App `edge` ở wave 5; `ClusterIssuer lab-ca` đặt cùng wave, cert-manager ở wave 3 (đã để trống).
- Route hỏng trong app `edge` sẽ làm app `Degraded`, ghim sync của root vào revision cũ tới khi hết retry (khoảng 5 phút ở G0-05). Cần áp ngay commit sửa thì `argocd app terminate-op root-lab` rồi sync lại.

## Lộ trình

Duyệt ngày 2026-11-14. Chủ repo giao Claude làm cả ticket. Hiện trạng lúc lập: 6 app `Synced/Healthy`; Gateway `edge` chỉ có listener `http`, 0 route; chưa có cert-manager; root CA có từ G0-02 (khóa ở `~/lab-ca`, chứng chỉ ở `platform/pki/`, đã tin trong System Keychain); cert-manager mới nhất vẫn là v1.21.3 (chart ghi tới K8s 1.36), `config.gatewayAPI.enabled` có trong values của chart v1.21.3.

Quyết định khi duyệt: (A) khóa intermediate chỉ sinh trong thư mục tạm, seal xong thì xóa; khôi phục nhờ bản sao lưu khóa sealing, xoay bằng cách sinh intermediate mới. (B) "Cụm trắng" diễn tập trên kind ở Mac (kèm đường nạp khóa sealing trước lệnh bootstrap 2). (C) SealedSecret và `ClusterIssuer` ở app riêng `lab-ca`, wave 5.

- [x] 1. `platform/scripts/lab-ca/make-intermediate.sh` (EC P-256, 730 ngày, `CA:TRUE, pathlen:0`, name constraints như root, ký bằng root, seal thẳng thành SealedSecret rồi xóa khóa rõ), test đỏ trước trong `test-constraints.sh`. Kiểm: test PASS; `openssl verify` với root.
  - Kết quả: 19 kiểm mới trong `test-constraints.sh` (tổng 36 PASS), viết đỏ trước; seal và mở offline bằng khóa sealing giả (`kubeseal --cert`, `--recovery-unseal`). Đối chứng âm: bỏ name constraints và đổi `pathlen` thì 5 FAIL đúng chỗ. Kiểm riêng ràng buộc của intermediate bằng `-partial_chain` (intermediate làm trust anchor). Chủ repo chạy thật (nhập passphrase root): intermediate hết hạn 2028-11-13, SHA-256 `C7:61:17:CC…26:36`.
- [x] 2. App `cert-manager` (wave 3): CRD vendor v1.21.3 `Prune=false,Delete=false`, chart `crds.enabled=false`, `config.gatewayAPI.enabled: true`, 3 × 64 Mi, image ghim digest, namespace do `platform` tạo. Kiểm: `Synced/Healthy`; log có gateway-shim; RAM.
  - Kết quả: push → `Synced/Healthy` sau **15 s**; log `starting controller ... gateway-shim`. Tắt `startupapicheck` (hook chạy lại mỗi sync, không chặn wave sau); Lease ở namespace `cert-manager`. RAM 37 / 46 / 15 Mi.
- [x] 3. App `lab-ca` (wave 5): SealedSecret `lab-intermediate-ca` + `ClusterIssuer lab-ca`. Kiểm: `ClusterIssuer` `Ready=True`; health Argo CD.
  - Kết quả: push → `ClusterIssuer` `Ready` (`Signing CA verified`) sau khoảng 30 s; Secret trên cụm có intermediate ← root.
- [x] 4. Gateway `edge`: annotation `cert-manager.io/cluster-issuer`, listener `https`. Kiểm: `Certificate` `Ready`; `openssl s_client -showcerts`; `curl -v https://x.lab.internal` không lỗi TLS.
  - Kết quả: push → `Certificate lab-wildcard-tls` `Ready` sau **3 s** (ECDSA P-256, 90 ngày). Envoy gửi leaf ← intermediate; cert-manager tách root sang `ca.crt`. Gộp luôn đổi listener `http` sang `from: Same` (lúc đó 0 route gắn vào).
- [x] 5. Listener `http` `from: Same` + HTTPRoute redirect 301. Kiểm: `curl -sI http://app.lab.internal` → `301`.
  - Kết quả: `301`, `location` giữ host, path, query.
- [x] 6. Argo CD qua `edge`: `server.insecure`, `url`, nhãn namespace `argocd`, HTTPRoute trong app `edge`. Kiểm: trình duyệt, `curl -v`, `argocd login --grpc-web`.
  - Kết quả: Chrome 157, `curl -q -v`, SecTrust không cảnh báo; `argocd version --grpc-web` ra `v3.6.1`. Thêm patch NetworkPolicy `argocd-server` chỉ cho Envoy vào (pod lạ bị chặn, port-forward vẫn được); `rollout restart` một lần cho `server.insecure`. Sau review: HSTS và tắt timeout request trên route.
- [x] 7. Name constraints: `Certificate` tạm `evil.example.com` từ `lab-ca`, phục vụ bằng `openssl s_server` trên Mac. Kiểm: Chrome, Safari, `curl` từ chối; giữ PEM cho G0-07.
  - Kết quả: cert-manager cấp `evil.example.com`, `localhost` trong 1 s. Từ chối: Chrome `NET::ERR_CERT_INVALID`, SecTrust "violates name constraints", curl lỗi 60, OpenSSL `permitted subtree violation`; đối chứng `nc-control.lab.internal` qua được. Phát hiện `~/.curlrc` có `-k`: mọi bằng chứng `curl` chạy `-q`. Không giữ PEM cho G0-07 (manifest `Certificate` ở bản ghi, cấp lại trong 1 s).
- [x] 8. Bootstrap lại từ cụm trắng (kind). Kiểm: cert-manager `restartCount` 0, Certificate của `edge` sinh ra không cần thao tác tay; thời gian từng wave.
  - Kết quả: kind v1.37.0, đúng runbook kèm nạp khóa sealing. CRD 17:13:25 trước cert-manager 17:17:13, 0 restart; Certificate `edge` `Ready` ở giây 360 không thao tác tay; lần đầu diễn tập trọn đường khôi phục khóa sealing từ cụm trắng. `gateway-api-crds` mất 218 s mới `Healthy` (reconcile định kỳ, nguyên nhân chưa xác minh).
- [x] 9. Kết ticket: `code-review`, số đo vào `docs/experiments/`, sửa chuẩn, Bài học.
  - Kết quả: số đo ở [bản ghi G0, mục 5](../../../experiments/2026-11-g0.md#5-pki-của-lab-và-https-trên-edge-cấp-chứng-chỉ-chuỗi-tin-cậy-name-constraints-cụm-trắng); sửa chuẩn `cluster-entry.md`, `gitops-argocd.md`, ADR-0014 (mục chưa xác minh), runbook homelab 8.8. Review: xem mục Review. Safari do chủ repo kiểm tay: `argocd.lab.internal` không cảnh báo, `localhost:7443` bị từ chối.

## Kết quả

- Bằng chứng: [bản ghi G0, mục 5](../../../experiments/2026-11-g0.md#5-pki-của-lab-và-https-trên-edge-cấp-chứng-chỉ-chuỗi-tin-cậy-name-constraints-cụm-trắng) và các dòng G0-06 trong [bằng chứng cửa vào cụm](../../../experiments/2026-11-cluster-entry.md).
- `platform`: `6465c1e` (script + test), `dbe77f7` (sửa theo review), `510bf6a` (runbook).
- `gitops`: `69e2fac` (cert-manager wave 3), `8347625` (lab-ca wave 5), `aa623f7` (listener HTTPS), `869286b` (`http-to-https`), `9cd1a5b` (Argo CD qua `edge`), `74472df` (HSTS, timeout). 8 app `Synced/Healthy`.
- Ma trận truy vết: không có dòng tương ứng (ticket hạ tầng, như G0-03..05).
- Chuyển cho ticket sau:
  - G0-07: cấp lại `Certificate` `evil.example.com` theo manifest trong bản ghi để thử JVM, Node; trust-manager wave 4, cài vào namespace `cert-manager` đã có.
  - G0-12: SSO dùng `url: https://argocd.lab.internal`; cookie OIDC có `Secure` (scheme https), cookie đăng nhập local thì không (đã bù bằng HSTS).
  - G0-13: NetworkPolicy `argocd-server` chưa mở cổng metrics 8083.
  - G0-22: chart `app` thêm HSTS và `timeouts.request` theo route; HSTS hiện chỉ có ở route `argocd`.
  - G0-34 (hoặc ticket riêng): vì sao app chỉ có CRD đợi tới reconcile định kỳ mới `Healthy` (218 s ở cụm trắng); RAM cert-manager sau 24 giờ.

## Review

`code-review` (high) trên `gitops` `0ef3660..74472df^` và `platform` `94a5624..6465c1e` ra 9 điểm. Claude sửa 5 (chủ repo giao cả ticket), bỏ qua 3, áp 1 cho commit sau:

1. **Cookie đăng nhập local của Argo CD thiếu `Secure`** khi `server.insecure` (đã đọc `server.go`@v3.6.1), không có HSTS nên lộ qua `http://` trước 301. Sửa: HSTS trên route `argocd`.
2. **Route `argocd` chịu timeout request 15 s** của Envoy, cắt stream của UI và `--grpc-web`. Sửa: `timeouts.request: 0s` (chưa đo việc cắt trên cụm).
3. **`kubeseal` seal theo context kubectl hiện tại.** Sửa: `LAB_KUBE_CONTEXT` mặc định `homelab`.
4. **Đổi `argocd-cmd-params-cm` cần restart tay.** Bỏ qua, đã ghi runbook.
5. **Subject intermediate chỉ có tháng**, xoay khẩn cấp cùng tháng trùng DN. Sửa: thêm ngày giờ.
6. **Test dùng `date -j` (chỉ BSD).** Sửa: `openssl x509 -checkend`.
7, 8. **Lặp code trong test và values cert-manager.** Bỏ qua (rõ ràng hơn gọn).
9. **Commit thiếu mã yêu cầu N11** (CLAUDE.md). Áp từ các commit sửa review.

Ghi chú: một lần chạy `test-constraints.sh` ngay sau khi sửa báo FAIL ở bước `make-root.sh` (OpenSSL không đọc được passphrase); không lặp lại được trong 4 lần chạy sau, nguyên nhân chưa rõ.

## Bài học

- Chứng chỉ được **cấp** không có nghĩa là được **tin**: cert-manager ký `evil.example.com` trong 1 s; ranh giới thật nằm ở client, và mã lỗi `ERR_CERT_INVALID` (khác `AUTHORITY_INVALID`) cho thấy Chrome đã dựng xong chuỗi tới root rồi mới loại vì name constraints.
- Kiểm công cụ đo trước khi tin số đo: `~/.curlrc` có `-k` làm mọi `curl` "xanh" giả, kể cả với tên sai. Phép đối chứng âm (tên sai phải hỏng) bắt được ngay.
- Câu chuyện kể được: "Lab dùng CA hai tầng có name constraints, root offline, intermediate seal vào Git; tôi chứng minh bằng chứng chỉ thật do cert-manager cấp cho tên lạ rằng Chrome, Safari, curl đều từ chối, và dựng lại cụm từ trắng trên kind để chứng minh thứ tự wave cho chứng chỉ tự sinh ở giây 360 mà không cần thao tác tay."

