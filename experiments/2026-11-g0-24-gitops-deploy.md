# Bản ghi: deploy `hello` qua GitOps (lead time, ghi đồng thời, rollback)

Ticket [G0-24](../.scratch/g0-platform/issues/24-hello-gitops-deploy.md). Bằng chứng theo các dòng "Lead time", "Không đua ghi gitops" của [ci-cd.md](../standards/ci-cd.md) và "Rollback" của [gitops-argocd.md](../standards/gitops-argocd.md). Đo ngày **2026-11-21** và **2026-11-22** (giờ UTC).

## Đường đi

Merge vào `main` của `commerce-hub-hello` → `ci` (`java-service.yml`: `check`, rồi `image` build, quét Trivy, push GHCR theo digest, gắn tag SHA) → `deploy` (`update-gitops.yml` của `platform` `v0.3.1`: token GitHub App chỉ cho repo `gitops`, sửa `image.digest`, `image.tag` trong `envs/lab/hello/values.yaml`, commit của `commerce-hub-gitops-writer[bot]`) → Argo CD v3.6.1 trên lab poll repo `gitops` (không có webhook: cụm sau tailnet) → auto-sync `svc-hello` (chart `app` 0.2.0) → pod mới Ready. CI không có credential nào của cụm.

## Giả thuyết

1. Phần CI (push → commit `gitops`) ổn định quanh 3 phút; phần lớn là build và push image.
2. Khoảng "commit `gitops` → sync" bị chặn trên bởi chu kỳ poll của Argo CD: docs ghi 120 s + tối đa 60 s jitter ([FAQ 3.6](https://argo-cd.readthedocs.io/en/release-3.6/faq/)), tức tối đa khoảng 180 s.
3. Ba lần merge sát nhau cho ba commit `gitops` tuần tự, không run bị hủy (`concurrency.queue: max`).
4. Rollback bằng `git revert` mất cỡ một chu kỳ poll cộng thời gian rollout.

## Cách đo

- Lead time: [`2026-11-g0-24-gitops-deploy/lead-time.sh`](2026-11-g0-24-gitops-deploy/lead-time.sh). Mỗi lần một commit rỗng (`--allow-empty`) push vào `hello`, lần sau chỉ push khi pod của lần trước đã Ready. Mốc lấy từ nguồn: `completedAt` của job `ci / check` và `ci / image / publish` (image đã có tag trên GHCR), giờ commit `gitops` của bot, `deployedAt` trong `status.history` của Application, `lastTransitionTime` của điều kiện `Ready` của pod chạy đúng digest. Chỉ mốc push là giờ máy.
- Không bấm Refresh trên Argo CD ở mọi lần đo.
- Thời điểm refresh định kỳ đọc từ log `argocd-application-controller` (dòng `Refreshing app status (comparison expired …)` và `Initiated automated sync`).
- Cấu hình liên quan đều mặc định: `argocd-cm` không đặt `timeout.reconciliation` hay `timeout.reconciliation.jitter`; repo-server không đặt `--revision-cache-expiration` (mặc định 3m0s theo [trang lệnh repo-server](https://argo-cd.readthedocs.io/en/release-3.6/operator-manual/server-commands/argocd-repo-server/)).

## Kết quả

### Lead time (2026-11-22, 4 lần nối tiếp)

| Lần | Commit `hello` | Push → `check` xong | → image trên GHCR | → commit `gitops` | → Argo CD sync | → pod Ready | **Tổng** |
|---|---|---|---|---|---|---|---|
| 1 | `ffd1cf8` | 58 s | 106 s | 7 s | 333 s | 5 s | **509 s** |
| 2 | `e45ddd3` | 52 s | 110 s | 18 s | 163 s | 6 s | **349 s** |
| 3 | `4b057e3` | 49 s | 89 s | 8 s | 157 s | 6 s | **309 s** |
| 4 | `bf343f8` | 51 s | 102 s | 10 s | 312 s | 6 s | **481 s** |

- Push → commit `gitops` (phần CI): 146–180 s, trung vị 167 s. Giả thuyết 1 đúng.
- Commit `gitops` → sync: 157–333 s, trung vị 238 s. **Giả thuyết 2 sai**: hai lần vượt xa 180 s.
- Sync → pod Ready: 5–6 s (image đã có trên node không cần kéo; JVM có AOT cache).
- Tổng: 309–509 s, trung vị 415 s (khoảng 7 phút). Hơn nửa là chờ Argo CD.
- Hai lần riêng lẻ đo ngày 2026-11-21: `28e0a67` tổng 177 s (commit `gitops` → sync 19 s), `293756a` commit `gitops` → sync 127 s.

### Vì sao Argo CD thấy commit chậm hơn chu kỳ poll

Khoảng cách giữa hai lần refresh định kỳ của `svc-hello` trong log (15:03–16:30 ngày 22, 31 lần): **120–251 s**, dài hơn mức "120 s + tối đa 60 s" của docs.

Quan trọng hơn: lần refresh đầu tiên sau commit thường **không thấy** commit mới:

| Lần | Commit `gitops` | Refresh sau commit | Thấy commit ở |
|---|---|---|---|
| Rollback (bước 5) | 15:53:29 | 15:54:12 (+43 s) bỏ lỡ | 15:57:33 (+244 s) |
| 1 | 16:04:32 | 16:06:09 (+97 s) bỏ lỡ | 16:10:04 (+332 s) |
| 2 | 16:13:31 | (refresh 16:13:31 cùng giây) | 16:16:14 (+163 s) |
| 3 | 16:19:08 | 16:19:43 (+35 s) bỏ lỡ | 16:21:44 (+156 s) |
| 4 | 16:24:55 | 16:25:24 (+29 s), 16:27:25 (+150 s) bỏ lỡ | 16:30:07 (+312 s) |
| Ba merge (bước 4) | 15:48:08 | 15:49:35 (+87 s) | thấy ngay |

Giải thích phù hợp với số liệu (**chưa xác minh** bằng log repo-server): repo-server cache kết quả phân giải `main` → SHA (`git ls-remote`) trong 3 phút (`--revision-cache-expiration`); refresh nào rơi vào lúc cache còn hạn thì dùng SHA cũ, không thấy commit mới. Lần 4 bỏ lỡ hai refresh liền trong khoảng 3 phút sau một lần phân giải. Cache còn có thể được nạp lại bởi ApplicationSet `services-lab`, vốn cũng poll repo `gitops` (giả thuyết). Docs 3.6 không nói refresh định kỳ có bỏ qua cache này không; `argocd-cm` lại ghi thời hạn cache revision git bằng `timeout.reconciliation`, mâu thuẫn với mặc định 3m0s của cờ. Hệ quả đo được: chậm nhất khoảng một cache (180 s) cộng một chu kỳ refresh (tới 251 s), tức khoảng 7 phút.

Cách rút ngắn, chưa làm ở G0 (hạ tầng mức tối thiểu; deploy vài phút không chặn case backend nào): webhook GitHub → Argo CD cần một đường từ internet vào cụm; giảm `timeout.reconciliation` hoặc `--revision-cache-expiration` thì tăng số lần gọi GitHub. Xét lại ở G7 cùng phần vận hành.

### Ba merge sát nhau (2026-11-22, AC2)

Ba commit rỗng push lúc 15:44:48, 15:44:50, 15:44:53 (ba run riêng, đều `success`, không run `cancelled`):

| Lần | Image xong | Job `deploy` | Commit `gitops` |
|---|---|---|---|
| `cb080e9` | 15:47:18 | 15:47:22 → 15:47:40 | `f17cc66` |
| `8fd52f5` | 15:47:25 | 15:47:43 → 15:47:53 | `b95c2d8` |
| `09328fa` | 15:47:29 | 15:47:56 → 15:48:14 | `2342cb8` |

Job `deploy` chạy nối tiếp (lần 2 chờ 18 s sau khi image xong), commit đúng thứ tự, mỗi commit `2 2`. Argo CD sync thẳng `2342cb8` (bỏ qua hai revision giữa). Giả thuyết 3 đúng. Vòng thử lại khi push bị từ chối không phải dùng (một repo ghi); hai ca bị từ chối đã thử ở máy trên bản sao bare của `gitops`.

Chạy lại riêng job `deploy` của run cũ (`28e0a67`) bằng `gh run rerun --job`: attempt 2 chỉ chạy `deploy`, dùng lại output `digest`, kết thúc `success` với notice "`28e0a67…` cũ hơn `09328fa…` … bỏ qua", `gitops` không có commit mới.

### Rollback (2026-11-22, AC4)

`git revert 2342cb8` thành `8015472` (về `8fd52f5`), push 15:53:29 → sync 15:57:34 (+245 s) → kéo image 2,9 s (chưa từng chạy trên node) → pod Ready 15:57:40 (**+251 s**) → pod bản mới tắt hẳn (preStop 10 s, tắt êm), app `Healthy` chỉ còn digest cũ 15:58:05 (**+279 s**). Giả thuyết 4 đúng về dạng, nhưng "một chu kỳ poll" thực tế là 245 s (xem mục trên). Lần đo lead time 1 (`ffd1cf8`) sau đó deploy đè lên bản rollback, đúng như dự kiến: rollback trong `gitops` là biện pháp tạm.

### Lỗi gặp khi làm

- `update-gitops` `v0.3.0` ghi bằng `yq -i`; `yq` 4.54.3 trên runner `ubuntu-24.04` xóa mọi dòng trống của values (commit `e0ff6d7`: `2 7`), `yq` 4.54.1 trên máy thì giữ. Sửa ở `v0.3.1`: `awk` ghi hai dòng, `yq` chỉ đọc lại, `numstat` phải `2 2`.
- Khi đo: API báo run `completed` (và `gh run watch` trả về) lúc job `publish` của workflow lồng còn chạy, hai lần trong năm. Script chờ chính commit `gitops` thay vì tin trạng thái run. Nguyên nhân **chưa xác minh**.

## Kết luận

- CI đẩy được image tới `gitops` trong khoảng 3 phút mà không giữ credential nào của cụm; Argo CD tự kéo.
- Lead time toàn đường 5–8,5 phút, trong đó chờ Argo CD 2,5–5,5 phút và dao động mạnh vì poll cộng cache revision, không phải 3 phút như docs gợi ý.
- Ghi đồng thời và thứ tự ghi đều đúng nhờ `queue: max` và chặn "SHA cũ hơn".
- Rollback bằng `git revert` khoảng 4–5 phút, cùng nguyên nhân chờ.
