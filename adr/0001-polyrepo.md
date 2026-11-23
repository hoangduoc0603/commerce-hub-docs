# ADR-0001: Polyrepo, chia repo theo đơn vị phát hành

- Trạng thái: Chấp nhận
- Ngày: 2026-11-12

## Bối cảnh

commerce-hub gồm khoảng 10 service, 2 simulator và một frontend. Các phần này có thể viết bằng nhiều ngôn ngữ (ví dụ `webhook-ingress` bằng Go, `seller-web` bằng TypeScript). Mục tiêu học là làm giống một hệ thống microservice thật, nơi mỗi service có build, CI và nhịp phát hành riêng.

Phương án ban đầu là monorepo với một Gradle multi-project build. Phương án này chỉ hợp khi mọi thứ cùng là JVM, và nó che mất những bài toán mà hệ thống nhiều repo phải giải: chia sẻ contract, quản lý version, thứ tự deploy.

## Quyết định

- `commerce-hub/` là thư mục chứa, không phải Git repo.
- Một repo là một đơn vị phát hành và sở hữu, không nhất thiết là một deployable. Thứ luôn đổi và phát hành cùng nhau thì ở chung repo (ví dụ `marketplace-sim` chứa cả TikTok Shop và Shopee).
- Bốn repo cấp hệ thống: `docs`, `contracts`, `platform`, `gitops` (**sửa 2026-11-24**, [ADR-0019](0019-no-contracts-repo.md): bỏ `contracts`, còn ba repo). Service, simulator, frontend và thư viện nằm trong các thư mục nhóm `services/`, `simulators/`, `frontend/`, `libs/`, mỗi thư mục con là một repo.
- Code ứng dụng tách khỏi cấu hình deploy: repo service chỉ tạo ra image, `gitops` quyết định chạy ở đâu và cấu hình gì (theo Best Practices của Argo CD).
- Repo chỉ liên kết qua contract, artifact có version và runtime (**sửa 2026-11-24**, [ADR-0019](0019-no-contracts-repo.md): không còn repo contract; artifact có version là image, chart và reusable workflow). Không dùng đường dẫn `../` giữa repo, không dùng git submodule.
- Chia sẻ bằng chuẩn trước, thư viện sau: event envelope là schema trong `contracts`, observability dùng OpenTelemetry và W3C `traceparent`. (**Sửa 2026-11-24**, [ADR-0019](0019-no-contracts-repo.md): envelope và record event được chép vào từng service, không có schema chung.)

## Hệ quả

Được:

- Ranh giới service được ép bằng cấu trúc: service không thể import code của service khác.
- Mỗi repo chọn ngôn ngữ, build và nhịp phát hành riêng.
- Lịch sử `gitops` chỉ gồm thay đổi deploy, dễ audit và rollback.

Phải trả:

- Mất kiểm tra lúc compile xuyên service. Bù bằng kiểm tương thích schema trong CI của `contracts` (Schema Registry, `BACKWARD_TRANSITIVE` theo [ticket 09](../.scratch/architecture-g0-g1/issues/09-g1-contracts.md#answer) và [arc42 mục 8.5](../architecture/08-crosscutting-concepts.md#85-event-và-kafka); bản đầu của ADR này ghi `BACKWARD`: nâng consumer trước, producer sau), Pact cho REST, và e2e trên cụm. (**Sửa 2026-11-24**, [ADR-0019](0019-no-contracts-repo.md): không bù. Không có kiểm tương thích schema hay Pact; producer đổi field thì consumer hỏng lúc chạy, lộ qua test của consumer hoặc DLT.)
- Đổi xuyên hệ thống thành nhiều PR theo thứ tự expand/contract.
- Cấu hình build và CI lặp ở nhiều repo. Bù bằng template repo cho service, reusable workflow trong `platform`, Renovate hoặc Dependabot để nâng version.

## Phương án đã cân nhắc

- **Monorepo, Gradle multi-project**: đổi xuyên service trong một commit, phiên bản đồng nhất. Loại vì không hợp hệ thống đa ngôn ngữ và không luyện được các bài toán của polyrepo.
- **Monorepo chứa nhiều build độc lập**: giữ được đa ngôn ngữ, nhưng CI phải tự dò phần bị ảnh hưởng, và vẫn không tách được lịch sử deploy khỏi lịch sử code.
