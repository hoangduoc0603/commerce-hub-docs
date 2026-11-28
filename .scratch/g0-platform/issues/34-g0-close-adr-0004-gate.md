# 34: Cổng ADR-0004 và đóng G0

Status: ready-for-human
Blocked by: 29, 30, 32 (bỏ 16, 20 ngày 2026-11-15: Kafka, Apicurio, contract Avro sang đầu G1, spec G0 mục "Sửa phạm vi 2026-11-15")
Repos: docs, gitops
Spec: [G0](../spec.md)

## Mô tả

Đóng G0 bằng kiểm cổng, số đo và tài liệu. Kiểm tay từng điều kiện của mục "Cổng ra khỏi G0" trong spec. Đo **một lần** `kubectl top` toàn cụm khi hạ tầng G0 cộng `hello` đang chạy, so với bảng của [ADR-0004](../../../adr/0004-single-instance-by-default-on-homelab.md) và phần dự kiến cho G1; đo RSS của `hello` ở `MaxRAMPercentage=60`. Thiếu quá 1 GiB so với ngân sách G1 thì sửa ADR-0004 trước khi viết spec G1. Viết bản ghi thí nghiệm tổng của G0 (giả thuyết, cách đo, số đo, kết luận), arc42 mục 7, runbook còn thiếu, và cập nhật `docs/standards/`. Ghi rằng Deployment `hello` sẽ gỡ khỏi `gitops` khi service G1 đầu tiên lên lab.

Ghi chú về cạnh chặn: thêm 29 và 30 vì trước đây ticket này nhận chúng gián tiếp qua 31 và 33.

## Mục tiêu học

- Lập kế hoạch dung lượng bằng số đo thật, và khi nào số đo buộc phải sửa một quyết định.

## Thu hẹp 2026-11-15

Theo quyết định D9, D10 (spec G0 mục "Sửa phạm vi 2026-11-15").

- Giữ: cổng ra khỏi G0 theo danh sách mới, đo một lần `kubectl top` và RSS `hello` so với ADR-0004, tài liệu đóng G0.
- Đổi: cổng không còn chờ ticket 09, 31, 33. Hành vi trước đây smoke e2e kiểm thì nay kiểm tay.
- Hoãn tới G7: bản đo sau 24 giờ chạy tải nền; các điểm **chưa xác minh** ngoài danh sách phải đóng ở G0 (attestation, k6 trên macOS đọc root trong Keychain, giới hạn 360 phút của `timeout-minutes`, và phần còn lại của danh sách cũ trong spec).

Tiêu chí hoãn tới G7:

- `kubectl top pod -A` sau 24 giờ chạy tải nền, theo nhóm của bảng ngân sách; không pod nào OOMKilled trong 24 giờ.
- Các điểm **chưa xác minh** hoãn ở trên đã có kết quả trong `docs/standards/`.

## Tiêu chí nghiệm thu

- [ ] Cổng, kiểm tay và ghi bằng chứng vào bản ghi thí nghiệm G0:
  - [ ] Merge vào `hello` → CI push image lên GHCR → commit trong `gitops` → app `Synced/Healthy`.
  - [ ] Qua `https://hello.lab.internal`: không token trả 401 Problem Details; token client credentials của realm `commerce-hub` tạo được lời chào.
  - [ ] Request đó có trace trên Tempo (span HTTP server và span DB), log trên Loki, metric và dashboard "Service overview" có dữ liệu.
  - ~~Kafka 3 broker và Apicurio `Ready`; pipeline Avro của `contracts` chặn thay đổi phá vỡ (bằng chứng từ ticket 20).~~ Sang đầu G1 cùng ticket 15, 16, 20. (Sửa 2026-11-24, [ADR-0019](../../../adr/0019-no-contracts-repo.md): ticket 16 và 20 bỏ; đầu G1 chỉ còn Kafka, ticket 15.)
  - [ ] Vòng dev bằng `platform/compose` chạy được (bằng chứng từ ticket 32).
- [ ] `kubectl top pod -A` đo một lần, theo nhóm của bảng ngân sách; không pod nào OOMKilled lúc đo.
- [ ] RSS của `hello` dưới 90% limit (NMT summary); chốt `MaxRAMPercentage` cho G1.
- [ ] Ghi số đo so với bảng ADR-0004, nói rõ thiếu Kafka. Quyết định giữ hay sửa ADR-0004 dời tới lúc Kafka lên ở đầu G1 (sửa 2026-11-15).
- [ ] Các điểm **chưa xác minh** phải đóng ở G0 đã có kết quả trong `docs/standards/` (đã xác minh, hoặc lệch chuẩn có lý do): RSS `hello` (ticket này); span JDBC với Spring Boot 4.1 (30); ~~`nullif` với `''` (25)~~ sang G1 cùng ticket 25 (2026-11-15); đọc package GitHub Packages chéo repo bằng `GITHUB_TOKEN` (19); chart monolithic của Tempo (14); package GHCR của repo public có tự public không (17, [ADR-0017](../../../adr/0017-images-and-charts-on-ghcr.md)). UI Apicurio tắt được không (16) sang G1.
- [ ] arc42 mục 7 (deployment view) và mục 9 cập nhật; runbook bootstrap, khóa sealing, thêm service, admin realm đầy đủ.
- [ ] Bản ghi thí nghiệm G0 trong `docs/experiments/` link tới các bản ghi theo chủ đề.
- [ ] Dòng "Phase hiện tại" trong CLAUDE.md và ma trận truy vết phản ánh G0 xong.

## Chuyển từ G0-05

- RAM lúc rảnh (2026-11-14): controller Envoy Gateway 56/256 Mi, Envoy 21/128 Mi, **shutdown-manager 23/32 Mi** (đã thêm `GOMEMLIMIT` 28MiB). Đo lại trong lần đo `kubectl top` của ticket này (theo dõi 24 giờ sang G7); nếu shutdown-manager OOMKilled thì nâng limit và sửa bảng ADR-0004.

## Chuyển từ G0-10

- Dòng "Tài nguyên" trong bảng "Bằng chứng cần có" của `keycloak.md` thuộc G0 (spec G0, mục Testing) nhưng G0-10 chưa đo: `kubectl top pod -n keycloak` khi chạy k6 đăng nhập 5 lượt/s trong 10 phút. Đạt khi không OOMKilled, ghi RAM và CPU thật, so với sizing (1 vCPU cho khoảng 15 lượt đăng nhập mật khẩu/s); kiểm `http-max-queued-requests=100` (giá trị khởi đầu) có trả 503 khi quá tải không.
- RAM lúc rảnh (2026-11-27, [bản ghi G0-10](../../../experiments/2026-11-g0-10-keycloak.md)): `keycloak-0` 508–591 Mi trên request = limit 1 536 Mi; operator 205–226 Mi trên 450 Mi. Bảng RAM của ADR-0004 ghi "Keycloak 1 instance + operator ~2 GB"; request thật là 1 986 Mi.

## Chuyển từ G0-11

- Mailpit chưa cài trên `gw` (2026-11-27 chỉ có dnsmasq; `platform/docs/homelab-hyperv.md` mục 8.9 mô tả cách cài). Chủ repo bỏ qua tiêu chí "email thử tới Mailpit, đo RAM Mailpit" ở G0-11. Story 83 (RAM của Mailpit trên `gw`) cần Mailpit chạy trước. Kiểm gửi email: `PUT /admin/realms/commerce-hub/users/{id}/execute-actions-email` với `["VERIFY_EMAIL"]` cho một user thử có email, rồi `curl -s http://10.20.0.5:8025/api/v1/messages`. Không dùng nút "Test connection" của realm bằng client service account: endpoint đó gửi tới email của admin đang đăng nhập.

## Chuyển từ G0-13

- RAM thành phần quan sát (2026-11-28, 25 phút sau reboot, [bản ghi G0 mục 10](../../../experiments/2026-11-g0.md)): tổng limit `observability` **2 256 Mi** so với 1 872 Mi trong bảng ticket kiến trúc 04. Lệch chính: Grafana 13 và hai sidecar 640 Mi thay vì 320 (224 + 2 × 48 OOMKilled lúc khởi động); hai config-reloader × 32 Mi không có trong bảng. Prometheus 693/1 024 Mi working set ở 96 293 series. Đo lại sau 24 giờ chạy nền rồi mới chốt ADR-0004. Phương án bớt 128 Mi: tắt sidecar datasources, khai datasource bằng file provisioning.
- cainjector của cert-manager: 15–16 Mi sau khi tắt theo dõi CRD, APIService (trước đó 58/64 Mi và một lần SIGKILL khi áp CRD của Prometheus Operator).
- Metric của etcd, scheduler, controller-manager, kube-proxy tắt (kubeadm nghe 127.0.0.1): Hoãn tới G7, nằm ngoài GitOps (static pod manifest, ConfigMap kube-proxy).

## Chuyển từ G0-14

- RAM (2026-11-28, tải 3 phút: 150 span/s, 450 dòng log/s, [bản ghi G0 mục 11](../../../experiments/2026-11-g0.md)): đỉnh Collector 110/192 Mi, Loki 151/512, Tempo 418/512 (heap về 91 MB sau 4 phút; tải G1 có thể vượt 512). 0 restart, 0 OOMKilled cho cả năm pod.
- Grafana 384 Mi bị OOMKilled 5 lần trong 6 giờ chạy rỗi (RSS 260–370 Mi): G0-14 nâng 512 Mi, GOMEMLIMIT 460 MiB (gitops `e9ceb63`). Pod Grafana và hai sidecar nay 768 Mi so với ngân sách 320.
- Tổng limit `observability` **3 984 Mi** so với khoảng 3 482 của ticket kiến trúc 04. Đo 24 giờ trước khi chốt ADR-0004; cân nhắc giới hạn ingest hoặc sampling cho Tempo ở tải G1.
