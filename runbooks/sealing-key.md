# Runbook: khóa sealing của Sealed Secrets

Seal một secret, sao lưu khóa sealing ra ngoài cụm, khôi phục khóa khi dựng lại cụm hoặc mất khóa, và quy ước `secretRevision`.

- Ticket: [G0-04](../.scratch/g0-platform/issues/04-sealed-secrets.md). Chuẩn: [gitops-argocd.md, mục "Secret"](../standards/gitops-argocd.md#secret).
- Phiên bản: Sealed Secrets **0.41.2** (chart `2.22.0`), `kubeseal` 0.41.2, cụm `homelab` Kubernetes 1.37.
- Diễn tập ngày 2026-11-14.
- Controller: Deployment `sealed-secrets-controller` trong `kube-system`, do app Argo CD `sealed-secrets` (`gitops/apps/lab/sealed-secrets.yaml`) quản lý. Đây đúng là tên và namespace mặc định của `kubeseal`, nên các lệnh dưới không cần `--controller-name` hay `--controller-namespace`.
- Docs gốc: [README Sealed Secrets](https://github.com/bitnami/sealed-secrets) (repo cũ `bitnami-labs/sealed-secrets` đã chuyển hướng về đây), các mục "Sealing key renewal", "How can I do a backup of my SealedSecrets?", "Can I decrypt my secrets offline with a backup key?".

## Mô hình trong một đoạn

- Controller giữ **cặp khóa RSA 4096 bit** trong Secret `kube-system/sealed-secrets-key*`, mang nhãn `sealedsecrets.bitnami.com/sealed-secrets-key`.
- `kubeseal` chỉ cần **cert công khai** để mã hóa. Chỉ controller giải mã được.
- **Scope `strict`** (mặc định): namespace và tên Secret được gắn vào ciphertext. Chép SealedSecret sang namespace khác, hay đổi tên, đều làm nó không giải mã được (đã thử ở G0-04 bước 5).
- **Gia hạn khóa:** cứ 30 ngày (`keyrenewperiod: 720h`), controller sinh thêm một khóa mới và giữ mọi khóa cũ. SealedSecret cũ vẫn giải mã được; secret seal mới dùng khóa mới nhất.
- **Hệ quả cho sao lưu:** sau mỗi lần gia hạn, bản sao lưu cũ **thiếu** khóa mới. Nếu chỉ còn bản sao lưu cũ, các SealedSecret seal sau ngày gia hạn sẽ không mở được.

## Seal một secret

Secret dạng rõ không được chạm đĩa. Tạo Secret bằng `--dry-run` rồi pipe thẳng sang `kubeseal`:

```bash
kubectl create secret generic <tên> -n <namespace> \
  --from-literal=<key>=<giá-trị> --dry-run=client -o yaml \
  | kubeseal --format yaml > <thư-mục>/<tên>-sealedsecret.yaml
```

- **Đặt đúng namespace và tên ngay từ đầu.** Muốn đổi một trong hai thì phải seal lại.
- **Giá trị nhạy cảm nên đọc từ file hoặc stdin** (`--from-file=key=/dev/stdin`), thay vì ghi trong dòng lệnh, để không lọt vào history của shell.
- **Trong app Argo CD**, SealedSecret mang annotation `argocd.argoproj.io/sync-wave: "-1"`, để Secret có trước workload ([gitops-argocd.md, mục "Sync waves"](../standards/gitops-argocd.md)). Ngoại lệ: Secret mật khẩu role trong app `pg-main` ở wave `1` (sau `Cluster` ở wave 0, trước `DatabaseRole` ở wave 2), theo [postgres-cnpg.md](../standards/postgres-cnpg.md) và [runbook thêm service](pg-main-them-service.md).
- **Nếu bắt buộc phải có file Secret dạng rõ trung gian**, đặt tên theo mẫu `*.plain.yaml`, `*.unsealed.yaml` hoặc `*-secret.yaml`. Các mẫu này đã nằm trong `.gitignore` của `gitops`.
- **Trước khi push**, chạy `scripts/check-no-plain-secrets.sh` trong `gitops`: phải in `OK`.

## Sao lưu khóa

**Khi nào:**

1. Ngay sau khi cài controller lần đầu.
2. Sau **mỗi** lần khóa gia hạn, tức 30 ngày kể từ lúc khóa mới nhất được tạo.
3. Sau mỗi lần khôi phục hoặc cài lại.

Xem ngày gia hạn kế tiếp:

```bash
kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key \
  --sort-by=.metadata.creationTimestamp \
  -o custom-columns=NAME:.metadata.name,CREATED:.metadata.creationTimestamp
# Khóa mới nhất + 30 ngày = lần gia hạn kế tiếp. Đặt lời nhắc trong lịch cho ngày đó + 1.
```

**Cách làm:**

```bash
cd gitops
scripts/backup-sealing-key.sh        # mặc định ghi vào ~/.commerce-hub/sealing-keys/ (700/600)
```

Script làm các việc sau:
- Lấy **mọi** khóa mang nhãn và bỏ metadata do API server sinh ra.
- Đối chiếu fingerprint SHA-256 trong file với trên cụm, và kiểm cert đang dùng để seal (`kubeseal --fetch-cert`) có nằm trong file.
- Từ chối ghi vào một thư mục thuộc repo Git.
- Không in private key ra màn hình.

**Cất bản sao lưu:**

> **Trạng thái hiện tại (lệch chuẩn có chủ đích, 2026-11-14):** bản sao lưu nằm ở dạng rõ, chỉ một bản, trong `~/.commerce-hub/sealing-keys/` trên Mac của chủ repo (thư mục `700`, file `600`, loại khỏi Time Machine, FileVault bật); chưa có bản ngoài máy. Lý do và rủi ro chấp nhận: [gitops-argocd.md, "Lệch chuẩn có chủ đích ở home lab"](../standards/gitops-argocd.md#lệch-chuẩn-có-chủ-đích-ở-home-lab). Sau mỗi lần sao lưu lại, xóa bản cũ, chỉ giữ bản mới nhất. Cách đúng chuẩn ở dưới.

Có hai cách đúng chuẩn, tùy password manager:

- **Password manager đính kèm được file** (1Password: item **Document**; Bitwarden: Secure Note có file đính kèm, cần gói Premium): làm theo các bước 1–3 ngay dưới.
- **Không đính kèm được file** (app Passwords của macOS): cất file trong ảnh đĩa mã hóa, mật khẩu trong Passwords, xem mục "Ảnh đĩa mã hóa" bên dưới.

1. Tạo một mục trong password manager tên `commerce-hub / sealing-key / <context> / <UTC stamp>`.
   - Đính kèm file `sealing-key-backup-<context>-<stamp>.yaml`.
   - Ghi vào phần ghi chú: số khóa, fingerprint SHA-256 của từng cert, và sha256 của file (script in sẵn cả ba).
2. Mở lại mục vừa tạo, kiểm sha256 của file đính kèm.
3. Xóa bản trên đĩa: `rm ~/.commerce-hub/sealing-keys/sealing-key-backup-*.yaml`.

**Ảnh đĩa mã hóa** (đã thử với dữ liệu giả ở G0-04; ảnh nén chỉ đọc khoảng 140 KB, nhập sai mật khẩu bị từ chối). Mọi lệnh có nhập mật khẩu chạy trong app Terminal riêng, không qua công cụ nào ghi lại output (transcript của trợ lý AI, log CI).

1. Sinh mật khẩu thẳng vào clipboard, không hiện ra màn hình: `openssl rand -base64 24 | pbcopy`. Dán vào một mục mới trong Passwords (Title `commerce-hub sealing-key DMG`, Notes: tên file, số khóa, fingerprint, sha256, nơi đặt ảnh đĩa). Xóa clipboard: `printf '' | pbcopy`. iCloud Keychain phải bật để mật khẩu cũng có bản ngoài Mac.
2. Gom đúng file cần cất vào một thư mục riêng rồi tạo ảnh đĩa (lệnh hỏi mật khẩu hai lần):

   ```bash
   mkdir -m 700 ~/.commerce-hub/stage
   cp ~/.commerce-hub/sealing-keys/sealing-key-backup-<context>-<stamp>.yaml ~/.commerce-hub/stage/
   hdiutil create -srcfolder ~/.commerce-hub/stage -volname commerce-hub-sealing-key \
     -encryption AES-256 -format UDZO ~/.commerce-hub/commerce-hub-sealing-key-<context>-<stamp>.dmg
   ```

3. Chép ảnh đĩa ra ngoài Mac (iCloud Drive và/hoặc USB). Mở **bản ngoài Mac** bằng Finder (bỏ tick "Remember password in my keychain"), so `shasum -a 256` của file bên trong với sha256 script đã in, rồi `diskutil eject /Volumes/commerce-hub-sealing-key`.
4. Xóa bản không mã hóa và bản tạm: file `.yaml`, thư mục `stage`, file `.dmg` trên Mac.

Đánh đổi: nếu cả ảnh đĩa (iCloud Drive) lẫn mật khẩu (iCloud Keychain) cùng ở một Apple Account, chiếm được tài khoản đó là có cả hai; Apple Account phải bật xác thực hai lớp, hoặc giữ thêm bản trên USB cất riêng.

Vì gia hạn chỉ **thêm** khóa, bản sao lưu mới nhất chứa mọi khóa còn dùng. Giữ bản mới nhất và một bản liền trước.

**Không bao giờ** đưa bản sao lưu vào Git (kể cả repo private), Slack, email hay ổ đồng bộ không mã hóa. File này mở được mọi SealedSecret trong mọi repo đã seal bằng khóa đó.

## Khôi phục

Lấy file sao lưu ra một chỗ ngoài repo, với quyền `600`. Hiện tại (lệch chuẩn ở trên) file đã nằm sẵn ở `~/.commerce-hub/sealing-keys/`; nếu đã cất theo cách đúng chuẩn thì lấy từ password manager hoặc mở ảnh đĩa mã hóa.

### A. Dựng lại cụm từ trắng (đúng thứ tự)

Controller **chỉ sinh khóa mới khi lúc khởi động không thấy khóa nào**. Vì vậy phải nạp khóa **trước** khi Argo CD dựng controller, tức là chen vào giữa hai lệnh bootstrap trong [`gitops/bootstrap/README.md`](https://github.com/hoangduoc0603/commerce-hub-gitops/blob/main/bootstrap/README.md):

```bash
# Sau lệnh bootstrap 1 và các lệnh chờ, TRƯỚC lệnh bootstrap 2:
kubectl apply -f ~/.commerce-hub/sealing-keys/sealing-key-backup-<context>-<stamp>.yaml   # namespace kube-system luôn có sẵn
# Rồi chạy lệnh bootstrap 2. Root dựng app sealed-secrets ở wave 1, controller nhận khóa có sẵn.
```

Kiểm: log controller có dòng `registered private key` cho từng khóa và **không** có dòng `New key written`. Fingerprint của `kubeseal --fetch-cert` phải trùng cert mới nhất trong bản sao lưu.

### B. Controller đã chạy và đã sinh khóa mới (quên bước A, hoặc mất khóa trên cụm đang chạy)

Đây là đường đã diễn tập ở G0-04 bước 8. **Thay** khóa mới bằng bản sao lưu, đừng giữ cả hai. Nếu giữ lại khóa mới, nó sẽ là khóa mới nhất nên được dùng để seal, trong khi nó không có trong bản sao lưu nào.

```bash
kubectl -n kube-system delete secret -l sealedsecrets.bitnami.com/sealed-secrets-key
kubectl apply -f ~/.commerce-hub/sealing-keys/sealing-key-backup-<context>-<stamp>.yaml
kubectl -n kube-system delete pod -l app.kubernetes.io/name=sealed-secrets
```

Kiểm:

```bash
kubectl -n kube-system logs deploy/sealed-secrets-controller | grep 'registered private key'
kubeseal --fetch-cert | openssl x509 -noout -fingerprint -sha256      # trùng bản sao lưu
kubectl get sealedsecrets -A                                           # cột SYNCED đều True
kubectl -n argocd get applications                                     # không app nào Degraded vì SealedSecret
```

**Lệnh `delete secret` ở trên an toàn.** Nó chỉ xóa khóa chứ không xóa Secret của ứng dụng. Secret của ứng dụng đã giải mã sẵn nên vẫn còn nguyên, và controller (mặc định không bật `skipRecreate`) sẽ tạo lại bất kỳ Secret nào bị thiếu ngay khi có khóa đúng.

**Số đo diễn tập (2026-11-14):** từ lúc bắt đầu ba lệnh khôi phục tới khi Secret thử xuất hiện lại với đúng giá trị: **1,7 s**. Pod controller khởi động và nạp khóa trong khoảng 10 ms.

### C. Không có cụm: giải mã offline từ bản sao lưu

Dùng khi cần lấy lại giá trị một secret mà chưa có cụm, ví dụ để chuyển sang hệ thống khác. Private key truyền qua process substitution nên không ghi ra đĩa:

```bash
kubeseal --recovery-unseal \
  --recovery-private-key <(yq '.items[0].data."tls.key"' sealing-key-backup-<…>.yaml | base64 -d) \
  -o yaml < <file>-sealedsecret.yaml
```

Có nhiều khóa thì truyền mỗi khóa một `--recovery-private-key`, hoặc thử lần lượt `items[i]`. Đã thử ở G0-04 bước 8: ra đúng giá trị.

## Sự cố thường gặp

| Triệu chứng | Nguyên nhân | Xử lý |
|---|---|---|
| SealedSecret `SYNCED False`, `no key could decrypt secret (<key>)`, app Argo CD `Degraded` | (1) Seal cho namespace hoặc tên khác (scope `strict`); (2) seal bằng cert của cụm khác hoặc của một lần cài trước; (3) controller mất khóa (đã sinh khóa mới) | (1), (2): seal lại đúng namespace, tên, cụm. (3): khôi phục theo mục B |
| Log controller có `New key written` ngay sau khi dựng lại cụm | Đã quên nạp khóa trước lệnh bootstrap 2 | Làm mục B, rồi sao lưu lại |
| Xóa Secret của ứng dụng nhưng nó hiện lại ngay | Controller tạo lại Secret mình sở hữu khi bị xóa (`skipRecreate: false`) | Đúng thiết kế. Muốn gỡ thì xóa SealedSecret trong Git |

## Xoay vòng giá trị secret thật

**Gia hạn khóa sealing không xoay vòng secret.** Giá trị cũ vẫn nằm trong SealedSecret cũ ở lịch sử Git, và khóa cũ vẫn mở được chúng.

Khi một secret có thể đã lộ (hoặc tới lịch xoay vòng):
1. Đổi giá trị ở hệ thống gốc (mật khẩu DB, token…).
2. Seal lại giá trị mới.
3. Tăng `secretRevision` trong cùng commit (mục dưới).

Khi **khóa sealing** có thể đã lộ:
- Mọi secret từng seal bằng khóa đó đều coi như đã lộ, và phải xoay vòng toàn bộ.
- Docs có cơ chế gia hạn sớm (`--key-cutoff-time`) và `kubeseal --re-encrypt`. Cả hai **chưa diễn tập** ở lab.

## Quy ước `secretRevision`

**Vấn đề:** pod đọc Secret qua env hoặc file lúc khởi động. Đổi SealedSecret thì Secret đổi, nhưng pod không tự rollout. Chart `app` ([helm-chart.md](../standards/helm-chart.md)) chỉ tham chiếu Secret có sẵn, nên annotation checksum của chart không thấy Secret thay đổi.

**Quy ước của dự án** (không phải khuyến nghị từ docs; chart hiện thực ở [G0-21](../.scratch/g0-platform/issues/21-chart-app-core.md)):

- `values.yaml` của mỗi service có `secretRevision`, là một số nguyên bắt đầu từ `1`. Chart chép nó vào annotation của pod template, nên đổi giá trị này thì Deployment rollout.
- **Commit nào đổi SealedSecret của một service thì tăng `secretRevision` của service đó thêm 1, trong cùng commit đó.** Một commit thì một lần rollout, và `git log` cho biết lần rollout nào do đổi secret.
- Không dùng ngày hay hash. Số nguyên tăng dần đọc được ngay, và revert commit thì giá trị quay về đúng bản cũ.
- Không tăng khi chỉ seal lại cùng giá trị (ví dụ sau `--re-encrypt`), vì không có gì mới cho pod đọc.
