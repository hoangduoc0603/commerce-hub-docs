# 04: Sealed Secrets và sao lưu khóa sealing

Status: resolved
Blocked by: 03
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

Secret đi vào cụm chỉ dưới dạng `SealedSecret` (scope `strict`), do Argo CD sync như mọi resource khác. Khóa sealing có bản sao ngoài cụm và đã thử khôi phục. Theo mục "Secret" của [gitops-argocd.md](../../../standards/gitops-argocd.md).

## Mục tiêu học

- Mã hóa bất đối xứng cho secret trong GitOps, và vì sao không dùng plugin giải mã lúc render.
- Vòng đời khóa sealing: gia hạn, sao lưu, khôi phục khi dựng lại cụm.

## Tiêu chí nghiệm thu

- [x] Một `SealedSecret` thử commit vào `gitops`, sync thành `Secret` trong đúng namespace; đổi namespace thì không giải mã được.
- [x] `git -C gitops grep -l '^kind: Secret$'` trả 0 file. **Đạt theo ý định, đổi phép kiểm:** lệnh nguyên văn trả 1 file (`bootstrap/argocd/upstream/install.yaml`, khung `argocd-secret` rỗng không có `data`, do argocd-server tự điền lúc chạy). Thay bằng `gitops/scripts/check-no-plain-secrets.sh` (đọc YAML, bắt Secret có `data`/`stringData` và `secretGenerator`): exit 0 trên 13 file YAML.
- [x] Runbook sao lưu và khôi phục khóa sealing, cất bản sao ngoài Git. Runbook [`runbooks/sealing-key.md`](../../../runbooks/sealing-key.md); bản sao lưu ở `~/.commerce-hub/sealing-keys/` (700/600, loại khỏi Time Machine), chỉ giữ một bản `…T160502Z.yaml` (sha256 `dbd6d32f…`, đã bỏ annotation `last-applied-configuration`). **Lệch chuẩn có chủ đích** (chủ repo quyết định 2026-11-14): dạng rõ, chưa có bản ngoài máy; ghi ở [gitops-argocd.md, "Lệch chuẩn có chủ đích ở home lab"](../../../standards/gitops-argocd.md#lệch-chuẩn-có-chủ-đích-ở-home-lab). Đường lên đúng chuẩn (ảnh đĩa mã hóa + Passwords + iCloud) đã thử với dữ liệu giả, ghi trong runbook.
- [x] Thử khôi phục: xóa controller và khóa, nạp lại bản sao, `SealedSecret` cũ vẫn giải mã được (1,7 s).
- [x] Quy ước `secretRevision` ghi trong runbook (chart dùng ở ticket 21).

## Lộ trình

Duyệt ngày 2026-11-14. Chủ repo giao Claude làm cả ticket. Hiện trạng lúc lập: Argo CD v3.6.1 tự quản lý (G0-03), `kube-system` chưa có controller, Mac chưa có `kubeseal`. Tra 2026-11-14: repo đã chuyển `bitnami-labs/sealed-secrets` → `bitnami/sealed-secrets` (HTTP 301); Helm repo `https://bitnami.github.io/sealed-secrets` (index cũ ở `bitnami-labs.github.io` rỗng); chart `2.22.0` = app `0.41.2`; Argo CD v3.6.1 có health check built-in `bitnami.com/SealedSecret`.

Quyết định khi duyệt: cài bằng Helm chart chính thức ghim `2.22.0` (không vendor `controller.yaml`: Argo CD đã chạy nên không còn lý do bootstrap bằng kubectl như G0-03; chart cho sẵn resources, `keyrenewperiod`, security context; cert-manager, Envoy Gateway cũng dùng chart); runbook ở `docs/runbooks/sealing-key.md`, link từ README `gitops`; Sealed Secrets ở wave 1 (trước cert-manager, vì `ClusterIssuer lab-ca` cần SealedSecret `lab-intermediate-ca`), sửa thứ tự wave ở spec dòng 183.

- [x] 1. `apps/lab/sealed-secrets.yaml`: project `platform`, chart `2.22.0`, `kube-system`, `fullnameOverride: sealed-secrets-controller`, memory request = limit 64Mi, `GOMEMLIMIT`, `keyrenewperiod: 720h` tường minh, wave 1; thêm helm repo vào `sourceRepos` của `platform`. Kiểm: `helm template` cùng values; `kubectl apply --dry-run=server`.
  - Kết quả: Application multi-source: chart `2.22.0` (digest gói `1ed23bb2…`, `skipCrds: true`, `valuesObject`) + `infra/sealed-secrets/` (CRD vendor từ tag `v0.41.2`, sha256 `6ccc74ae…`, patch `Prune=false,Delete=false`). Image ghim digest index đa kiến trúc `sha256:e63ec6ec…`. Chart không có value đặt env nên tự đặt `GOMEMLIMIT` = 100% limit (lệch có chủ đích, ghi trong file). `helm template`: 10 resource, args có `--key-renew-period 720h`, security context đạt `restricted`; dry-run server không lỗi.
- [x] 2. Push, root sync. Kiểm: app `Synced/Healthy`; 1 Secret nhãn `sealedsecrets.bitnami.com/sealed-secrets-key`; log controller; RAM.
  - Kết quả: push 22:40:46 (giờ VN) → `Synced/Healthy` sau 17 s. Khóa `sealed-secrets-key5gxbd`, nhãn `active`, RSA 4096, cert hạn 10 năm, fingerprint `E0:30:49:32…`; sinh trong 0,6 s. RAM 13Mi/64Mi.
- [x] 3. Cài `kubeseal` 0.41.2, `--fetch-cert`. Kiểm: `kubeseal --version`; fingerprint cert trùng `tls.crt` trên cụm.
  - Kết quả: `brew install kubeseal` → v0.41.2. Fingerprint `--fetch-cert` trùng `tls.crt` trên cụm.
- [x] 4. Sandbox: seal Secret thử, commit, sync; làm hỏng ciphertext. Kiểm: Secret giải mã đúng; bản hỏng → app `Degraded`.
  - Kết quả: app `sandbox-sealed` `Synced/Healthy` sau 11 s, Secret `demo` đúng giá trị, có `ownerReference` tới SealedSecret. SealedSecret `broken` (ciphertext sửa 8 ký tự) → app `Degraded` sau 2 s, `no key could decrypt secret (password)`: health built-in `bitnami.com/SealedSecret` của Argo CD hoạt động.
- [x] 5. Chép SealedSecret sang namespace khác. Kiểm: không sinh Secret; condition báo lỗi giải mã.
  - Kết quả: cùng ciphertext chép sang `sandbox-b/demo` và `sandbox/demo-renamed`: cả hai `no key could decrypt secret`, không sinh Secret.
- [x] 6. `.gitignore` chặn file secret dạng rõ. Kiểm: `git -C gitops grep -l '^kind: Secret$'` 0 file.
  - Kết quả: `git grep` trả 1 file (khung `argocd-secret` rỗng trong `install.yaml` vendor). Viết `scripts/check-no-plain-secrets.sh` đọc YAML thật; fixture âm bắt `kind` có ngoặc kép, Secret trong `List`, nhiều document có comment, YAML hỏng (sau review thêm `secretGenerator`, file chưa `git add`). `.gitignore`: `*.plain.yaml`, `*.unsealed.yaml`, `sealing-key-backup*`.
- [x] 7. Runbook sao lưu, lịch sao lưu sau gia hạn, quy ước `secretRevision`; sao lưu lần đầu ra ngoài Git. Kiểm: số khóa và fingerprint bản sao lưu khớp cụm; không có trong Git.
  - Kết quả: `scripts/backup-sealing-key.sh` (đối chiếu fingerprint, từ chối ghi vào repo Git, không in private key); bản sao lưu đầu `sealing-key-backup-homelab-20261114T154517Z.yaml`, 1 khóa, fingerprint khớp. Runbook [`runbooks/sealing-key.md`](../../../runbooks/sealing-key.md) viết sau bước 8 để ghi lệnh và số đo thật; `gitops/README.md` có mục Secret; `bootstrap/README.md` có bước nạp khóa trước lệnh 2 khi dựng lại cụm.
- [x] 8. Diễn tập khôi phục: xóa controller và khóa, thấy SealedSecret cũ hỏng với khóa mới, nạp bản sao lưu, restart; thử `kubeseal --recovery-unseal`. Kiểm: Secret thử được tạo lại đúng giá trị; số giây.
  - Kết quả: `--recovery-unseal` offline đúng giá trị. Mất khóa: lần xóa đầu, Secret `demo` được controller cũ (đang tắt, còn khóa trong bộ nhớ, `skipRecreate: false`) tạo lại ngay; xóa lại sau khi nó tắt hẳn thì controller mới (khóa `2F:54…`) báo `no key could decrypt`. Khôi phục (xóa khóa mới, apply bản sao, xóa pod): Secret có lại sau **1,7 s**, đúng giá trị, cert seal trở về `E0:30…`. Kiểm thêm: bản sao lưu còn `resourceVersion`, `uid` vẫn apply được (dry-run), nên sửa lý do trong script. Đường "nạp trước lệnh 2 từ cụm trắng" chưa diễn tập trọn (ghi ở ticket 34).
- [x] 9. Kết ticket: gỡ sandbox, sửa chuẩn và spec, số đo vào `docs/experiments/2026-11-g0.md`, `code-review`, Bài học.
  - Kết quả: sandbox gỡ qua Git, namespace mất sau 14 s; còn `argocd`, `root-lab`, `sealed-secrets` `Synced/Healthy`. Số đo: [bản ghi G0, mục 3](../../../experiments/2026-11-g0.md#3-sealed-secrets-scope-khôi-phục-khóa-ram). Sửa spec dòng 183 (thứ tự wave) và chuẩn `gitops-argocd.md` mục Secret. Review: xem mục Review.

## Kết quả

- Bằng chứng: [bản ghi G0, mục 3](../../../experiments/2026-11-g0.md#3-sealed-secrets-scope-khôi-phục-khóa-ram). SealedSecret đầu-cuối 11 s; scope `strict` từ chối cả đổi namespace lẫn đổi tên; mất khóa thì khôi phục trong 1,7 s; RAM 13/64 Mi.
- Commit trong `gitops` từ `a8822ea` tới `0a1094f`: app `sealed-secrets`, `infra/sealed-secrets/`, `scripts/check-no-plain-secrets.sh`, `scripts/backup-sealing-key.sh`, `.gitignore`, README. Sandbox đã gỡ khỏi Git và khỏi cụm.
- Tài liệu: runbook [`runbooks/sealing-key.md`](../../../runbooks/sealing-key.md), chuẩn [gitops-argocd.md](../../../standards/gitops-argocd.md) mục Secret, spec dòng 183.
- Ma trận truy vết: không có dòng tương ứng (ticket hạ tầng, giống G0-02, G0-03).
- Chuyển cho ticket sau:
  - Ticket 17 (CI): chạy `scripts/check-no-plain-secrets.sh` trong CI của `gitops` (review điểm 4); cơ chế báo bản mới cho chart và digest image ghim trong Application (Dependabot hiện chỉ theo dõi github-actions; review điểm 9).
  - Ticket 13 (Prometheus): cảnh báo khi khóa mới nhất cũ hơn bản sao lưu gần nhất, hoặc theo dõi ngày gia hạn (**chưa xác minh** metric nào phù hợp).
  - Ticket 34: diễn tập đường "nạp khóa giữa lệnh bootstrap 1 và 2" khi dựng lại cụm từ trắng; đo lại RAM controller khi có nhiều SealedSecret (`GOMEMLIMIT` = 100% limit, review điểm 10).
  - Ticket 06: SealedSecret `lab-intermediate-ca` theo runbook; app cert-manager wave sau 1.

## Review

`code-review` (high) trên `gitops` `d6b1b77..0a1094f` ra 10 điểm. Claude sửa 7 (commit `0a1094f`, chủ repo giao cả ticket), chuyển 3:

1. **Guard bỏ sót `secretGenerator` và mật khẩu trong values Helm.** Sửa: bắt mọi map có khóa `secretGenerator`; mật khẩu trong values ghi là giới hạn đã biết (chart chỉ nhận `existingSecret`). Khi sửa lộ thêm một đặc điểm của yq v4.54: sau `select` rỗng, `[ … ]` vẫn sinh mảng rỗng, nên `"x" + ([…] | join)` in ra cho mọi file. Đổi sang ghép với đường dẫn, xét từng document bằng `yq e`.
2. **`*-secret.yaml` trong `.gitignore` nuốt file SealedSecret đặt tên như vậy.** Sửa: bỏ mẫu này, ghi lý do.
3. **Ba chỗ ghim (chart, digest image, CRD vendor) có thể lệch nhau.** Sửa: comment "nâng cấp" ngay cạnh `targetRevision`.
4. **Guard chưa chạy tự động.** Chuyển ticket 17.
5. **Script quét index chứ không quét cây làm việc.** Sửa: `--cached --others --exclude-standard`, bỏ qua file đã xóa.
6. **Link runbook 404 khi `docs` chưa push.** Sửa: push `docs` cùng ticket.
7. **Tên context có `/` làm hỏng đường dẫn file sao lưu.** Sửa: thay ký tự lạ bằng `_`; thử với context dạng ARN của EKS.
8. **Lỗi giữa chừng để lại file sao lưu rỗng.** Sửa: `trap` xóa file nếu chưa xong. Khi thử với context chết thì lộ thêm lỗi kubectl **treo vô hạn** (không có timeout mặc định); thêm `--request-timeout=30s` cho mọi lệnh gọi cụm. Thử lại: exit 1 sau 0 s, không còn file.
9. **Không có cơ chế báo bản mới cho chart và digest.** Chuyển ticket 17.
10. **`GOMEMLIMIT` = 100% limit.** Giữ, lệch có chủ đích (chart không cho đặt), RAM đo 13/64 Mi; đo lại ở ticket 34.

## Bài học

- Phép kiểm theo chuỗi (`git grep '^kind: Secret$'`) vừa bắt nhầm vừa bắt sót. Kiểm theo cấu trúc (đọc YAML) mới trả lời đúng câu hỏi "có giá trị bí mật nào trong repo không". Và chính script kiểm cũng cần bộ fixture âm: lần sửa theo review đầu tiên báo lỗi cho mọi file vì một đặc điểm của yq.
- Khóa sealing là dữ liệu, không phải cấu hình. Thứ cần bảo vệ khỏi "commit lỡ tay" ở đây là CRD (xóa CRD thì GC xóa mọi Secret) và thứ tự lúc dựng lại cụm (nạp khóa trước khi controller khởi động). Bản sao lưu chỉ có giá trị khi đã khôi phục thử: lần diễn tập đầu bị controller cũ "cứu" Secret vì nó vẫn giữ khóa trong bộ nhớ, nên mô phỏng mất khóa phải chờ nó tắt hẳn.
- Script vận hành phải giả định lỗi: context sai thì kubectl có thể treo vô hạn, file dở có tên giống bản thật. `--request-timeout` và `trap` dọn file là hai dòng mà review và một phép thử context chết mới làm lộ ra.
- Câu chuyện kể được: "Secret trong repo GitOps public đi qua Sealed Secrets. Tôi diễn tập mất khóa: controller mới sinh khóa khác, SealedSecret cũ hỏng hết, app chuyển Degraded; nạp bản sao lưu và restart controller thì Secret có lại sau 1,7 s. Diễn tập cũng cho thấy phải nạp khóa trước khi controller khởi động lúc dựng lại cụm, nên tôi đưa bước đó vào giữa hai lệnh bootstrap."
