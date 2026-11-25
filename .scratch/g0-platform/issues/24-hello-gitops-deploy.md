# 24: Deploy `hello` qua GitOps tới `hello.lab.internal`

Status: resolved
Blocked by: 06, 22, 23
Repos: services/hello, platform, gitops, docs
Spec: [G0](../spec.md)

## Mô tả

Tracer bullet của G0: merge vào nhánh mặc định của `hello` thì job `update-gitops` (token GitHub App, ở G0 chỉ cài trên `gitops`; `e2e` thêm khi làm ticket 31 ở G7) sửa digest và tag trong values lab của `hello`. `ApplicationSet` sinh app trong project `commerce`, chart `app` kéo từ GHCR (đổi nguồn `10.20.0.5:5000/charts` của ticket 03, thêm GHCR vào `sourceRepos` của `commerce`, không dùng `insecureOCIForceHttp`; [ADR-0017](../../../adr/0017-images-and-charts-on-ghcr.md)), namespace `hello` do app `platform` tạo kèm nhãn cho phép route. `hello` mở qua `https://hello.lab.internal` (ngoại lệ chỉ có ở G0). Values lab: 1 replica, 512Mi, `MaxRAMPercentage=60`. Theo mục "Deploy qua GitOps" của [ci-cd.md](../../../standards/ci-cd.md), "Cập nhật image" của [gitops-argocd.md](../../../standards/gitops-argocd.md).

## Đã làm ở G0-22 (2026-11-20)

Theo quyết định Q1 của [ticket 22](22-chart-app-edge.md#quyết-định-khi-lập-lộ-trình-2026-11-20): release thử của chart `app` chính là `hello`, nên phần gitops của ticket này đã có sẵn. Ticket này còn lại job `update-gitops`, đo lead time, rollback và các tiêu chí bên dưới.

- App `namespaces` (project `platform`, wave 8) tạo namespace `hello` có nhãn PSS restricted, `edge.lab.internal/routes`, `trust.lab.internal/inject`.
- Project `commerce` có `ghcr.io/hoangduoc0603/charts` trong `sourceRepos`; chart OCI public nên không cần repository Secret.
- ApplicationSet `services-lab` kéo chart `app` 0.2.0 từ GHCR.
- `envs/lab/hello/values.yaml`: image `16efc28` theo digest **ghi tay**, 1 replica, 512Mi, `MaxRAMPercentage=60`, route `hello.lab.internal`. Job `update-gitops` sẽ sửa `image.digest` và `image.tag` trong file này.
- `svc-hello` `Synced/Healthy`; `curl https://hello.lab.internal/livez` trả 200, `/` trả 404 của Spring.

## Mục tiêu học

- Đẩy image qua GitOps: CI chỉ commit vào `gitops`, không giữ quyền vào cụm.

## Tiêu chí nghiệm thu

- [x] Merge một thay đổi trong `hello` → commit mới trong `gitops` có tên service, SHA nguồn, link run → app `Synced/Healthy` → digest image của pod `hello` khớp digest trong commit `gitops` đó, và `curl https://hello.lab.internal/` qua `edge` nhận 404 JSON do Spring trả (TLS, route và pod đều thông). Sửa 2026-11-15: ở vị trí này `hello` mới là khung, chưa có endpoint nào (API có từ ticket 26, Actuator ở management port không mở qua `edge`); không thêm endpoint tạm vì nó không có trong contract. Từ ticket 27, `curl` gọi API thật.
- [x] Merge ba thay đổi gần nhau: ba commit `gitops` tuần tự, không job lỗi (`concurrency` và vòng thử lại khi push bị từ chối). Sửa 2026-11-22: vòng thử lại lấy nhánh mới nhất rồi làm lại thay đổi, không `pull --rebase` (rebase xung đột khi commit tới trước sửa đúng hai dòng đó, ví dụ một `git revert`).
- [x] CI không có token Argo CD, không gọi `kubectl`.
- [x] Rollback bằng `git revert` commit image; đo số giây tới `Healthy` ở bản cũ.
- [x] Đo lead time: merge → image trên GHCR → commit `gitops` → `Healthy`.
- [x] [cluster-entry.md](../../../standards/cluster-entry.md) thêm hostname `hello.` kèm ghi chú chỉ ở G0. Đã có từ G0-22 (mục "Hostname và UI vận hành": `hello.` **chỉ ở G0**, gỡ khi service G1 đầu tiên lên lab); dòng checklist đó gồm cả các hostname G1 nên để chưa tick.

## Quyết định khi lập lộ trình (2026-11-20)

- **Q1. Chặn ghi bản cũ hơn bản đang chạy.** `concurrency.queue: max` xếp run theo lúc bắt đầu chờ, không theo thứ tự merge: `ci` của merge trước chạy chậm hơn thì `deploy` của nó ghi sau và lab chạy bản cũ. `update-gitops` so SHA mới với `image.tag` hiện có bằng compare API (`gh api repos/<owner>/<repo>/compare/<tag cũ>...<sha mới> --jq .status`); `behind` thì bỏ qua và ghi notice. Loại: chấp nhận rủi ro rồi tự nhìn digest.
- **Q2. GitHub App đã có**: `commerce-hub-gitops-writer`, tạo 2026-11-20. Bước 1 chỉ còn kiểm quyền, chỗ cài và lưu credential vào `hello`.
- Đã kiểm 2026-11-20: `actions/create-github-app-token` `v3.4.0` (`f418cff399f7aef4c2f0ad47e25ca7a6abbdd6fc`), input `client-id` (thay `app-id`, deprecated từ v3.1), `permission-contents`, output `app-slug`, token thu hồi ở bước post. `concurrency.queue: max` giữ tới 100 run chờ, FIFO, không đi với `cancel-in-progress: true` ([Control concurrency](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-workflow-concurrency)). Runner `ubuntu-24.04` có `yq 4.54.3`.

## Lộ trình

- [x] 1. Kiểm App `commerce-hub-gitops-writer` (Contents RW, Metadata R, tắt webhook, chỉ cài trên `commerce-hub-gitops`); lưu Client ID làm variable, private key làm secret của repo `hello`; cất file `.pem` ra khỏi workspace. Kiểm: `gh variable list`, `gh secret list -R hoangduoc0603/commerce-hub-hello`; trang Installations chỉ có repo `gitops`.
- [x] 2. Viết `platform/.github/workflows/update-gitops.yml` (`workflow_call`): token App, chặn bản cũ hơn (Q1), `yq` sửa digest và tag, bỏ qua khi không đổi, commit có service, SHA nguồn, link run, push qua vòng `pull --rebase` 5 lần. Kiểm: chạy đoạn shell trên bản clone `gitops` ở máy (không push), `git show` chỉ đổi 2 dòng, comment còn nguyên; `actionlint` sạch.
- [x] 3. Release `platform` `v0.3.0`; `hello` thêm job `deploy` (ghim SHA, `needs: ci`, chỉ push vào `main`, `concurrency: { group: gitops-lab, queue: max }`), merge một thay đổi. Kiểm: commit `gitops` mới; `svc-hello` `Synced/Healthy`; `imageID` của pod khớp digest trong commit; `curl https://hello.lab.internal/` trả 404 JSON (AC1); workflow không có `kubectl`/`argocd` (AC3).
- [x] 4. Merge ba thay đổi sát nhau; thêm một phép thử ép thứ tự ngược (Q1). Kiểm: ba commit `gitops` tuần tự, không job đỏ, không run bị hủy (AC2); bản cũ hơn bị bỏ qua kèm notice.
- [x] 5. `git revert` commit image trong `gitops`. Kiểm: số giây từ push tới `Healthy` ở digest cũ (AC4).
- [x] 6. Đo lead time, ghi `docs/experiments/`, tick mục tương ứng trong `ci-cd.md`, `gitops-argocd.md`, `cluster-entry.md` (AC5, AC6).

## Ghi chép khi làm

- **Bước 3 (2026-11-21).** `platform` `v0.3.0` ghi values bằng `yq -i`: `yq` 4.54.3 trên runner xóa mọi dòng trống (commit `e0ff6d7` của `gitops` đổi 2+/7−), trong khi phép thử ở bước 2 chạy `yq` 4.54.1 trên máy giữ nguyên. Release notes 4.54.2/4.54.3 không nhắc dòng trống; nguyên nhân chính xác **chưa xác minh**. Sửa ở `v0.3.1`: `awk` thay đúng hai dòng trong khối `image:`, `yq` chỉ đọc lại để kiểm, `git diff --numstat` phải là `2 2`; `tag` luôn trong ngoặc kép. Commit tay `288b87f` trả lại dòng trống. Bài học: công cụ có sẵn trên runner không ghim phiên bản, thử ở máy không chứng minh được hành vi trên runner.
- **AC1, AC3 (lần deploy `28e0a67`, run 44918192725).** Commit `gitops` `7114188` của `commerce-hub-gitops-writer[bot]`, `numstat` `2 2`; `svc-hello` `Synced Healthy` ở revision `7114188`; pod `imageID` `…@sha256:369499aa…8478` khớp dòng `Image:` của commit; `curl https://hello.lab.internal/` trả `HTTP/2 404`, `content-type: application/json`. `grep` không thấy `kubectl`/`argocd` ngoài comment trong workflow của `hello` và `platform`; `hello` chỉ có secret `GITOPS_APP_PRIVATE_KEY`.
- Mốc thời gian của lần deploy đó (UTC): push 15:15:12 → image trên GHCR 15:17:29 → commit `gitops` 15:17:44 → Argo CD sync xong 15:18:03 → pod Ready 15:18:09. Lần `293756a`: commit `gitops` 08:49:20 → sync 08:51:27. Đo lại có hệ thống ở bước 6.
- **AC2 (2026-11-22).** Ba commit rỗng `cb080e9`, `8fd52f5`, `09328fa` push lúc 15:44:48, 15:44:50, 15:44:53 (ba lần push, ba run 45040001755, 45040005048, 45040008669), cả ba `success`, không run nào `cancelled`. Job `deploy` chạy nối tiếp nhờ `queue: max`: 15:47:22→15:47:40, 15:47:43→15:47:53, 15:47:56→15:48:14; image của lần 2 xong 15:47:25 nhưng `deploy` của nó chờ tới khi lần 1 xong. Ba commit `gitops` theo đúng thứ tự: `f17cc66` (cb080e9), `b95c2d8` (8fd52f5), `2342cb8` (09328fa), mỗi commit `2 2`. Argo CD sync thẳng `2342cb8` lúc 15:49:36 (bỏ qua hai revision giữa), pod chạy `sha256:4aba4c2a…1a23` khớp commit. Vòng thử lại khi push bị từ chối không được dùng tới (chỉ một repo ghi); đã thử ở máy ở bước 2.
- **Q1 (2026-11-22).** Chạy lại riêng job `deploy` của run 44918192725 (`28e0a67`) bằng `gh run rerun --job`: attempt 2 chỉ chạy `deploy`, các job `ci` được chép từ attempt 1 (thời điểm giữ nguyên ngày 21) và output `digest` được dùng lại. Kết quả `success` kèm notice "`28e0a67…` cũ hơn `09328fa…` đang có trong `envs/lab/hello/values.yaml`; bỏ qua.", `gitops` không có commit mới.
- **AC4 (2026-11-22).** `git revert 2342cb8` trong `gitops` thành commit `8015472` (tác giả chủ repo, `2 2`, `tag` về `8fd52f5`, digest `sha256:6564e944…cfbe`), push 15:53:29, không bấm Refresh. Argo CD thấy revision mới và sync lúc 15:57:34 (+245 s); node kéo image 2,9 s (image của `8fd52f5` chưa từng chạy vì Argo CD bỏ qua `b95c2d8` ở bước 4); pod mới Ready 15:57:40 (**+251 s**, từ đây traffic đi vào bản cũ); pod cũ hết (preStop 10 s, rồi tắt êm) và app `Healthy` chỉ còn digest cũ lúc 15:58:05 (**+279 s**). `curl` qua `edge` vẫn 404 JSON. Gần như toàn bộ thời gian là Argo CD chưa thấy commit: 245 s lớn hơn mức 120 s + jitter mà tôi dự kiến; nguyên nhân **chưa xác minh**, đo thêm ở bước 6.
- **Giới hạn đã biết của Q1 với rollback.** Sau revert, `gitops` trỏ `8fd52f5`. Chạy lại job `deploy` của run `09328fa` sẽ thấy `09328fa` mới hơn `8fd52f5` và ghi lại đúng bản vừa rollback; Q1 chỉ so thứ tự commit trong `hello`, không biết bản nào bị chủ động gỡ. Lần merge kế tiếp vào `hello` cũng deploy đè bản rollback. Rollback trong `gitops` là biện pháp tạm; sửa thật là revert hoặc sửa trong `hello`. Chưa chặn ở G0.
- **AC5 (2026-11-22).** Bốn lần deploy nối tiếp bằng commit rỗng, script [`lead-time.sh`](../../../experiments/2026-11-g0-24-gitops-deploy/lead-time.sh), bản ghi [thí nghiệm](../../../experiments/2026-11-g0-24-gitops-deploy.md). Push → commit `gitops` 146–180 s (trung vị 167 s); commit `gitops` → sync 157–333 s (trung vị 238 s); sync → pod Ready 5–6 s; tổng 309–509 s (trung vị 415 s). Chờ Argo CD dài hơn mức "120 s + 60 s jitter" của docs: refresh định kỳ cách nhau 120–251 s, và lần refresh đầu sau commit thường vẫn thấy SHA cũ (4/6 lần), phù hợp với cache revision 3 phút của repo-server; **chưa xác minh** bằng log repo-server. Chưa rút ngắn ở G0, xét lại ở G7. Lần đo 1 deploy đè bản rollback của bước 5 (lab hiện chạy `bf343f8`, commit `gitops` `4690d52`).
- Khi đo, API báo run `completed` (và `gh run watch` trả về) trong lúc job `publish` của workflow lồng còn chạy, hai lần trong năm run; script chờ chính commit `gitops`. Nguyên nhân **chưa xác minh**.
- Kết ticket (2026-11-22): `./gradlew check` của `hello` xanh; `actionlint` sạch ở `hello` và `platform` (`platform` cần `-ignore 'unexpected key "queue"'`); `gitops/scripts/check-no-plain-secrets.sh` OK trên 58 file YAML. Ma trận truy vết: không có dòng tương ứng (ticket hạ tầng, như G0-03..08).
- `code-review` (mức medium, `platform` `v0.2.1..v0.3.1`, `hello/ci.yml`): 4 nit, không có lỗi chặn. (1) Q1 không bảo vệ rollback khỏi re-run job `deploy` (đã ghi là giới hạn chấp nhận ở G0); (2) `ci / dependency-graph` lỗi thì `deploy` bị bỏ qua dù image đã lên GHCR; (3) kiểm `numstat` đúng `2 2` sẽ chặn nhầm khi digest không đổi (chưa xảy ra được vì nhãn `revision`, `created`); (4) vòng thử lại coi mọi lỗi push (kể cả 403) là "bị từ chối".

## Bài học

- Phép thử ở máy không chứng minh hành vi trên runner: `yq -i` 4.54.1 trên Mac giữ dòng trống, 4.54.3 trên `ubuntu-24.04` xóa hết, và release notes không nhắc. Công cụ có sẵn trong image runner không ghim được phiên bản, nên không giao việc ghi file cho nó; ghi bằng `awk` hai dòng, dùng `yq` chỉ để đọc lại, và chặn bằng `numstat` để công cụ nào lỡ đổi thêm thì job dừng thay vì commit.
- Hai cơ chế chống ghi đè không thay nhau: `concurrency` (`queue: max`, vì mặc định chỉ giữ một run chờ và run thứ ba hủy run thứ hai) xếp hàng trong một repo, còn vòng "lấy main mới rồi làm lại" lo các repo khác cùng ghi. Thêm vào đó, xếp hàng theo lúc bắt đầu chờ không bảo đảm thứ tự merge, và "Re-run" một run cũ là đường deploy lùi thật; so SHA bằng compare API chặn được cả hai, nhưng không biết bản nào đã bị rollback chủ động.
- Chỗ vấp khi đo: "120 s + 60 s jitter" trong docs Argo CD không phải độ trễ thật. Log controller cho thấy refresh cách nhau tới 251 s và lần refresh đầu sau commit thường vẫn thấy SHA cũ (phù hợp cache revision 3 phút của repo-server), nên chờ Argo CD là 157–333 s, hơn nửa lead time. API GitHub cũng có lúc báo run `completed` khi job lồng còn chạy; script đo phải chờ chính kết quả (commit `gitops`), không tin trạng thái.
- Câu chuyện kể được: "CI của service không có credential nào vào cụm: nó build image một lần, rồi dùng token GitHub App ngắn hạn chỉ ghi được repo `gitops` để commit digest; Argo CD trên lab tự kéo. Ba merge sát nhau ra ba commit đúng thứ tự nhờ hàng đợi `concurrency`, re-run một run cũ bị chặn vì SHA cũ hơn bản đang chạy, rollback là một `git revert` (khoảng 4 phút). Lead time 5–8 phút, trong đó phần lớn là chu kỳ poll và cache revision của Argo CD vì cụm không nhận webhook từ internet."
