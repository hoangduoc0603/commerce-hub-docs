# Spec: Giai đoạn 0, nền tảng và service "hello" có trace

Status: ready-for-agent
Ngày: 2026-11-13, sửa phạm vi 2026-11-15 (xem mục [Sửa phạm vi 2026-11-15](#sửa-phạm-vi-2026-11-15))
Nguồn: [Map kiến trúc G0–G1](../architecture-g0-g1/map.md) (ticket 01–19 đã chốt), [C18](../../requirements-and-techniques.md#c18-lộ-trình-gợi-ý), [`docs/standards/`](../../standards/), ADR-0001..0018
Repos: docs, platform, gitops, contracts, services/hello, e2e (`libs/service-kit` bỏ từ 2026-11-15, [ADR-0018](../../adr/0018-self-contained-services-no-shared-library-yet.md))
Yêu cầu: N12 (khung). N11 (hook RLS) sang G1 và N10 (backup) hoãn tới G7, cùng từ 2026-11-15

## Problem Statement

Chủ repo đã có đủ yêu cầu (SRS), kiến trúc (arc42 mục 1–5, 8–9) và 16 ADR cho G0–G1, nhưng chưa có thứ gì chạy. Cụm home lab mới có runbook dựng tay, repo `platform`, `gitops`, `contracts` mới là khung rỗng, chưa có thư viện, template service, chart hay CI. Nếu bắt đầu code nghiệp vụ G1 ngay thì mỗi service phải tự giải lại cùng một loạt việc: build image, deploy qua GitOps, nối Keycloak, nối PostgreSQL với RLS, gửi trace. Mỗi chỗ tự giải sẽ lệch chuẩn một kiểu, và lỗi hạ tầng sẽ lẫn với lỗi nghiệp vụ.

Có ba rủi ro cụ thể chưa ai đo:

- Ngân sách RAM của ADR-0004 chỉ còn khoảng 520 MiB dư, và mọi con số trong đó là ước lượng. JVM 512 Mi với `MaxRAMPercentage` 75 có thể không đủ chỗ cho non-heap.
- Hơn hai mươi điểm trong `docs/standards/` đang gắn nhãn **chưa xác minh** (registry HTTP với attestation, ruleset trên tài khoản cá nhân, đọc package chéo repo, PDB của CloudNativePG khi chỉ có 1 instance…).
- Charter yêu cầu "chạy được mới là một nửa": mỗi artifact phải có bằng chứng đo được, mà chưa có quy trình nào sinh ra bằng chứng đó.

## Solution

Dựng nền tảng production-grade tối thiểu trên cụm home lab, rồi chứng minh nó bằng một service mỏng `hello`, cũng là template cho mọi service G1:

- Toàn bộ hạ tầng trong cụm do Argo CD quản lý từ repo `gitops`. Bootstrap bằng đúng hai lệnh tay; sau đó mọi thay đổi đi qua Git.
- Cửa vào cụm (`*.lab.internal` qua Gateway `edge`, TLS bằng CA của lab), PostgreSQL `pg-main` có backup liên tục, Kafka 3 broker cùng Apicurio, Keycloak với realm `commerce-hub` dạng code, stack LGTM với OpenTelemetry Collector.
- Đường từ code tới cụm dùng chung cho mọi repo: chart `app`, reusable workflow, ~~`libs/service-kit`~~ (bỏ 2026-11-15, ADR-0018), pipeline của `contracts`, image build một lần, deploy bằng commit vào `gitops`.
- `services/hello`: một API REST nhỏ bắt buộc JWT, ghi và đọc một bảng trong PostgreSQL. Mỗi request sinh một trace có span HTTP và span DB trên Tempo, và hiện trên một dashboard Grafana viết bằng code.
- Repo `e2e` chạy smoke test sau mỗi lần deploy, gọi `https://hello.lab.internal` qua `edge`, rồi kiểm có trace trên Tempo và có metric trên Grafana.
- Mọi điểm **chưa xác minh** của G0 được thử thật. Số đo (RAM sau 24 giờ, RSS của `hello`, kích thước image, lead time, rollout không lỗi…) ghi vào `docs/experiments/`. G0 kết thúc bằng quyết định giữ hay sửa ADR-0004 trước khi vào G1.

## User Stories

### Cụm và GitOps

1. Là người vận hành lab, tôi muốn dựng lại toàn bộ hạ tầng trong cụm từ một cụm trắng bằng đúng hai lệnh tay, để lab tái lập được và không phụ thuộc vào trí nhớ.
2. Là người vận hành lab, tôi muốn Argo CD tự quản lý chính nó từ repo `gitops`, để nâng Argo CD cũng chỉ là một commit.
3. Là người vận hành lab, tôi muốn mỗi thành phần hạ tầng là một `Application` riêng, sắp thứ tự bằng sync wave và có health check, để thành phần sau chỉ sync khi thành phần trước đã `Healthy`.
4. Là người vận hành lab, tôi muốn project `default` bị khóa và service chỉ deploy được vào namespace của chính nó, để một commit sai không tạo được tài nguyên cấp cụm.
5. Là người vận hành lab, tôi muốn thêm một service mới chỉ bằng cách thêm một thư mục values, để không phải sửa `ApplicationSet` mỗi lần.
6. Là người vận hành lab, tôi muốn cụm tự khôi phục khi ai đó sửa tay hay scale một Deployment về 0, để Git luôn là nguồn sự thật.
7. Là người vận hành lab, tôi muốn rollback một bản deploy bằng `git revert`, để lịch sử deploy và trạng thái cụm không lệch nhau.
8. Là người vận hành lab, tôi muốn secret chỉ vào Git dưới dạng `SealedSecret`, và khóa sealing có bản sao ngoài cụm, để repo public không lộ secret mà dựng lại cụm vẫn giải mã được.
9. Là người vận hành lab, tôi muốn tài nguyên giữ dữ liệu (PVC, `Cluster` của CloudNativePG, `Kafka`) không bị xóa khi lỡ xóa một `Application`, để một thao tác nhầm không mất dữ liệu.
10. Là người vận hành lab, tôi muốn đăng nhập Argo CD bằng SSO Keycloak và tắt tài khoản `admin`, để không có mật khẩu dùng chung lâu dài.

### Cửa vào cụm và PKI

11. Là developer, tôi muốn mở `https://argocd.lab.internal`, `https://grafana.lab.internal`, `https://auth.lab.internal` và `https://hello.lab.internal` từ Mac mà trình duyệt không cảnh báo TLS, để làm việc với lab giống production.
12. Là người vận hành lab, tôi muốn mọi HTTP chuyển sang HTTPS và chỉ namespace có nhãn cho phép mới gắn được route vào Gateway `edge`, để một app lạ không chiếm được hostname.
13. Là developer, tôi muốn pod JVM và pod Node tự tin CA của lab mà không sửa code, để gọi `https://*.lab.internal` từ trong cụm chạy được ngay.
14. Là người vận hành lab, tôi muốn root CA nằm ngoài cụm và có name constraints, để intermediate trong cụm có bị lộ cũng không ký được chứng chỉ cho domain thật.
15. Là người vận hành lab, tôi muốn `*.lab.internal` phân giải được từ Mac, từ pod và từ runner CI trong tailnet, để mọi client đi cùng một đường.
16. Là người vận hành lab, tôi muốn Keycloak chỉ lộ đường dẫn của realm `commerce-hub`, còn trang admin nằm ở hostname riêng, để realm `master` và `/admin` không mở ra ngoài.

### PostgreSQL

17. Là người vận hành lab, tôi muốn `pg-main` chạy PostgreSQL 18 qua CloudNativePG với 1 instance và requests bằng limits, để vừa ngân sách ADR-0004 mà vẫn đúng mô hình operator.
18. Là người vận hành lab, tôi muốn WAL được archive mỗi phút và có base backup hằng ngày lên RustFS trên `gw`, để mất cụm vẫn còn dữ liệu (N10).
19. Là developer, tôi muốn mỗi service có database riêng trên `pg-main` cùng bốn role `_owner`/`_migrator`/`_app`/`_lookup` khai báo bằng code, để thêm service không cần thao tác tay trong `psql`.
20. Là developer, tôi muốn service runtime đi qua PgBouncer `transaction` còn Job migration nối thẳng `pg-main-rw`, để Flyway giữ được advisory lock mà runtime vẫn dùng pool.
21. Là người vận hành lab, tôi muốn biết `kubectl drain` có bị PDB của CloudNativePG chặn khi chỉ có 1 instance không, và cách xử lý, để bảo trì node không bị kẹt.

### Kafka

22. Là người vận hành lab, tôi muốn Kafka 4.3.2 KRaft 3 broker qua Strimzi 1.3.1, mỗi broker 1 Gi với heap 512m, để G1 có cụm event đúng độ bền (`acks=all`, `min.insync.replicas=2`).
23. Là người vận hành lab, tôi muốn topic và user Kafka khai báo bằng CR trong `gitops`, để cấu hình topic trên lab và trên Mac giống nhau.
24. Là người vận hành lab, tôi muốn listener của Kafka bắt xác thực ngay từ G0, để G1 chỉ cần thêm `KafkaUser` cho từng service.
25. Là người vận hành lab, tôi muốn Strimzi Drain Cleaner chạy, để drain node không làm mất ISR của partition.
26. Là developer, tôi muốn Apicurio Registry 3 chạy trong cụm, không tự đăng ký schema, để mọi schema đi qua bước kiểm tương thích của `contracts`.

### Keycloak

27. Là người vận hành lab, tôi muốn Keycloak 26.8.2 chạy bằng Operator ở chế độ production với image build sẵn, DB riêng trên `pg-main`, để IdP đúng chuẩn ngay từ đầu.
28. Là người vận hành lab, tôi muốn realm `commerce-hub` là YAML trong `gitops`, áp bằng keycloak-config-cli, chạy hai lần không đổi gì và ghi đè được sửa tay, để realm tái lập được.
29. Là developer, tôi muốn có một client test dùng client credentials, có audience `commerce-hub-api`, để smoke test và k6 lấy được token hợp lệ mà không cần tài khoản người dùng cố định.
30. Là người vận hành lab, tôi muốn Keycloak gửi email qua Mailpit trên `gw`, để luồng email của G1 kiểm được mà không gửi ra ngoài.
31. Là người vận hành lab, tôi muốn Keycloak không tin `X-Forwarded-For` do client tự đặt, để chống brute force theo IP không bị qua mặt.

### Quan sát

32. Là developer, tôi muốn mỗi request vào `hello` sinh một trace có span HTTP server và span DB trên Tempo, để có khung truy vết cho N12.
33. Là developer, tôi muốn log của service là JSON có `traceId`, và từ một dòng log trên Loki mở được trace bằng một click, để gỡ lỗi không phải đoán.
34. Là developer, tôi muốn metric HTTP có histogram và exemplar trỏ về trace, để từ một điểm p99 trên dashboard nhảy được sang trace cụ thể.
35. Là developer, tôi muốn một dashboard Grafana dùng chung cho mọi service (RED cộng JVM, chọn service bằng biến), viết bằng code trong `gitops`, để service G1 có dashboard ngay khi deploy.
36. Là người vận hành lab, tôi muốn mọi thành phần LGTM có limit memory theo ngân sách, Loki tắt cache mặc định, để stack quan sát không làm node OOM.
37. Là người vận hành lab, tôi muốn biết chi phí của sampling 100% so với 0% (p99 và CPU), để quyết định có giữ 100% ở lab không.
38. Là người vận hành lab, tôi muốn số series trong Prometheus nằm trong ngân sách và không có nhãn `workspace_id`, để cardinality không nổ khi G1 thêm metric.

### Chart `app`

39. Là developer, tôi muốn một chart `app` dùng cho mọi workload, publish dạng OCI có version, để service chỉ khai báo values.
40. Là developer, tôi muốn chart mặc định 2 replica, PDB, probe tách liveness/readiness/startup, preStop và graceful shutdown, Pod Security "restricted", để zero-downtime là mặc định chứ không phải tùy chọn.
41. Là developer, tôi muốn values có JSON schema, sai kiểu hay thiếu digest image là `helm template` thất bại, để lỗi values lộ ra trước khi lên cụm.
42. Là developer, tôi muốn bật `HTTPRoute`, Job migrate `PreSync`, port thứ hai, SealedSecret và truststore chỉ bằng values, để service, simulator và `seller-web` dùng chung một chart.
43. Là developer, tôi muốn chart tự sinh NetworkPolicy ingress theo danh sách cho phép, và tự mở cho pod Envoy khi app có route, để mặc định là chặn.
44. Là developer, tôi muốn đổi ConfigMap hay SealedSecret trong `gitops` là pod tự rollout, để cấu hình mới không phải chờ restart tay.
45. Là developer, tôi muốn `ct install` chạy mọi biến thể values trên kind trong CI, để chart hỏng không tới được lab.

### CI/CD và repo

46. Là developer, tôi muốn mọi repo tạo bằng một script dùng chung (public, MIT, bảo vệ nhánh tối thiểu, secret scanning, push protection, CodeQL, Dependabot), để không repo nào thiếu một bước vệ sinh.
47. Là developer, tôi muốn repo service chỉ có workflow mỏng gọi reusable workflow của `platform` ghim theo SHA, để sửa CI một chỗ cho mọi repo.
48. Là developer, tôi muốn mọi action bên thứ ba ghim SHA 40 ký tự và mọi workflow khai `permissions` tối thiểu, để chuỗi cung ứng của CI không bị chiếm qua một tag bị dời.
49. Là developer, tôi muốn image build một lần trên runner amd64, tag bằng git SHA, quét Trivy chặn HIGH/CRITICAL có bản vá, có SBOM và attestation provenance được verify trước khi deploy, để thứ chạy trên lab đúng là thứ CI đã build.
50. Là developer, tôi muốn runner GitHub-hosted vào lab qua Tailscale bằng OIDC, node ephemeral, ACL chỉ mở đúng cổng cần, để repo public không cần runner tự host.
51. Là developer, tôi muốn job `update-gitops` sửa digest trong `gitops` bằng token của GitHub App, xếp hàng theo `concurrency` và thử lại khi push bị từ chối, để nhiều service merge cùng lúc không đè nhau.
52. Là developer, tôi muốn PR từ fork không nhận secret và không vào tailnet, để repo public an toàn.
53. Là người học, tôi muốn đo được lead time từ merge tới `Healthy` trên lab, chia theo từng khoảng, để biết khâu nào chậm.

### `contracts`

54. Là developer, tôi muốn OpenAPI của `hello` và schema `Problem` dùng chung nằm trong `contracts`, để contract có trước code.
55. Là developer, tôi muốn CI của `contracts` lint OpenAPI, chặn thay đổi phá vỡ bằng `oasdiff breaking`, kiểm Avro `BACKWARD_TRANSITIVE` với Apicurio, để thay đổi phá vỡ không merge được.
56. Là developer, tôi muốn `contracts` publish Maven và npm lên GitHub Packages chỉ từ tag `vX.Y.Z`, không ghi đè, để service phụ thuộc vào một version bất biến.
57. Là developer, tôi muốn một lệnh đăng ký schema dùng chung cho CI, Apicurio trên Mac và Apicurio trên lab, để không môi trường nào auto-register.

### `libs/service-kit`

**(sửa 2026-11-15)** Bỏ thư viện dùng chung ([ADR-0018](../../adr/0018-self-contained-services-no-shared-library-yet.md)): bỏ 58, 59, 65; 60, 61, 62 sang G1 (làm trong service đầu tiên có bảng theo Workspace); 63, 64 giữ hành vi, code nằm trong `hello`.

58. Là developer, tôi muốn convention plugin ghim Java 25, minor Spring Boot, repository và ArchUnit, để `build.gradle` của service chỉ còn phần riêng.
59. Là developer, tôi muốn luật ArchUnit của layout hexagonal chạy trong `./gradlew check` của mọi service, để `domain` không import Spring hay adapter.
60. Là developer, tôi muốn hook đầu transaction đặt `app.workspace_id` chạy đúng với cả `JdbcClient` lẫn JPA, qua PgBouncer `transaction`, để ADR-0012 được chứng minh trước khi service G1 dựa vào nó.
61. Là developer, tôi muốn một cách khai báo tường minh rằng transaction không thuộc Workspace nào, để bảng toàn cục (như `account` của `workspace` ở G1) dùng được mà không nới fail-closed.
62. Là developer, tôi muốn test catalog RLS và test hành vi qua PgBouncer phát hành dạng test-fixtures, để service nào cũng chạy được bằng một dòng.
63. Là developer, tôi muốn Problem Details (RFC 9457) có `traceId` cho mọi lỗi và `errors[]` cho lỗi validate, để client và người gỡ lỗi nối được lỗi với trace.
64. Là developer, tôi muốn sinh UUIDv7 ~~từ lib~~ (trong `hello`, sửa 2026-11-15), để ID nội bộ của mọi service cùng một cách.
65. Là developer, tôi muốn sửa lib và service cùng lúc bằng composite build, không dùng SNAPSHOT, để vòng sửa lib nhanh mà artifact vẫn bất biến.

### `services/hello` và template

66. Là developer G1, tôi muốn tạo service mới bằng "Use this template" từ `hello`, để service mới build được, CI xanh và có trace ngay từ commit đầu.
67. Là developer, tôi muốn `hello` bắt buộc JWT của realm `commerce-hub` với audience `commerce-hub-api`, trả 401 Problem Details cho token thiếu, sai `aud`, hết hạn hoặc từ realm khác, để template đúng mặc định của G1.
68. Là developer, tôi muốn tạo một lời chào và đọc lại theo ID, nhận 404 Problem Details khi ID không có và 400 kèm `errors[]` khi tên không hợp lệ, để template minh họa đủ quy ước lỗi.
69. Là developer, tôi muốn request và response của `hello` được kiểm với OpenAPI trong `contracts` ngay trong test, để code không trôi khỏi contract.
70. Là developer, tôi muốn migration của `hello` chạy bằng chính image với profile `migrate` trong Job `PreSync`, migration lỗi thì Deployment giữ bản cũ, để deploy không bao giờ chạy code mới trên schema cũ.
71. Là developer, tôi muốn image của `hello` chạy non-root, có AOT cache, và đo được thời gian khởi động có và không có cache, để chọn cấu hình bằng số.
72. Là người vận hành lab, tôi muốn biết RSS thật của `hello` ở 512 Mi với `MaxRAMPercentage=60`, để chốt giá trị cho mọi service G1.
73. Là developer, tôi muốn chạy `hello` trên Mac với profile `local` trên `platform/compose`, có thể bật profile `obs` để xem trace, để kiểm trước khi đẩy lên lab.

### Vòng dev trên Mac

74. Là developer, tôi muốn `platform/compose` dựng Kafka 1 broker, Apicurio, PostgreSQL 18 với role giống lab, PgBouncer `transaction` và Keycloak, đọc realm và topic từ bản checkout `../gitops`, để dev giống lab mà Mac không ghi vào lab.
75. Là developer, tôi muốn Testcontainers chạy cùng một lệnh `./gradlew check` trên Mac và CI, với tag image cùng major.minor như production, để test đỏ trên Mac cũng đỏ trên CI. **(sửa 2026-11-15)** Tag ghim trong test của từng service, kèm comment trỏ tới version trong `gitops` (ADR-0018).
76. Là developer, tôi muốn một job phát hiện khi tag image của compose, Testcontainers và lab lệch major.minor, để ba nơi không trôi xa nhau. **(sửa 2026-11-15)** Ở G0 job chỉ so compose với `gitops`; quét test của từng service xét lại ở G1.

### e2e

77. Là developer, tôi muốn repo `e2e` chạy smoke test tự động sau mỗi lần `update-gitops`, sau khi `argocd app wait` báo app `Synced` và `Healthy`, để biết bản vừa deploy chạy được trên lab thật.
78. Là developer, tôi muốn smoke test tự gửi `traceparent`, rồi poll Tempo tới khi thấy trace có span HTTP và span DB của `hello`, để "có trace" là một assertion chứ không phải kiểm tay.
79. Là developer, tôi muốn smoke test kiểm dashboard dùng chung tồn tại và Prometheus có metric HTTP của `hello`, để "có dashboard" cũng là assertion.
80. Là developer, tôi muốn e2e chạy thêm hằng đêm và chạy tay được, không chạy chồng lên nhau, đỏ thì có báo cáo Playwright làm artifact, để lỗi trôi dạt của lab lộ ra kể cả khi không deploy.

### Bằng chứng và tài liệu

81. Là người học, tôi muốn mỗi file `docs/standards/` liên quan có bảng bằng chứng đã điền số đo thật, ngày chạy, để chứng minh artifact đạt chuẩn chứ không chỉ chạy được.
82. Là người học, tôi muốn thấy `hello` rollout (đổi image, restart, drain node) dưới tải k6 50 req/s mà 0 request lỗi khi tạm chạy 2 replica, và một lần đối chứng âm có lỗi, để biết cấu hình zero-downtime thật sự có tác dụng.
83. Là người vận hành lab, tôi muốn `kubectl top` toàn cụm sau 24 giờ so với bảng ngân sách ADR-0004, kèm RAM của RustFS và Mailpit trên `gw`, để quyết định có phải sửa ADR-0004 trước G1 không.
84. Là người học, tôi muốn mọi điểm **chưa xác minh** thuộc G0 trong `docs/standards/` được thử và cập nhật thành đã xác minh hoặc lệch chuẩn có lý do, để G1 không dựa trên giả định.
85. Là người đọc tài liệu, tôi muốn arc42 có mục 7 (deployment view) mô tả cụm, namespace, cửa vào và `gw`, để có một chỗ nhìn được toàn bộ triển khai.
86. Là người vận hành lab, tôi muốn runbook cho bootstrap cụm, sao lưu và khôi phục khóa sealing, và thêm một service mới, để làm lại được mà không cần nhớ.
87. Là người học, tôi muốn ma trận truy vết ghi G0 xong phần khung N12, kèm link dashboard và một trace ID mẫu, để truy được từ yêu cầu tới bằng chứng.

## Implementation Decisions

### Sửa phạm vi 2026-11-15

Chủ repo chốt lại trọng tâm học ([Charter](../../project-charter.md) mục 1, bản 1.1): backend, microservices, event-driven với Java/Spring. Hạ tầng là phương tiện, chỉ làm tới mức service chạy và quan sát được. Không bỏ phần nào: phần hạ tầng sâu xếp vào Giai đoạn 7. Mục này thắng mọi dòng mâu thuẫn bên dưới và trong phần User Stories.

- **Quan sát giữ đủ** như thiết kế: Prometheus, Grafana, Loki, Tempo, Collector, dashboard dạng code (ticket 13, 14, 30). Grafana dùng tài khoản admin cục bộ (mật khẩu là SealedSecret); SSO Grafana sang G7. Ticket 13 không còn phụ thuộc ticket 11.
- **Chuẩn production hai mức** ([CLAUDE.md](../../../CLAUDE.md), mục "Chuẩn production"): code service, cấu hình Kafka, migration, contract giữ đủ quy trình (file chuẩn, checklist, số đo). Hạ tầng cài theo mặc định của chart hoặc operator, ghim phiên bản, ghi chỗ lệch; chỉ đo khi nó ảnh hưởng tới một case backend.
- **Image và chart trên GHCR** ([ADR-0017](../../adr/0017-images-and-charts-on-ghcr.md)), thay registry HTTP `10.20.0.5:5000` trên `gw`. CI push bằng `GITHUB_TOKEN`, không vào tailnet. Registry trên `gw` tắt.
- **Keycloak bản mỏng** (ticket 10): Operator, 1 instance, DB `keycloak`, `auth.lab.internal` qua `edge`, realm dạng code (11). Image build riêng (theme, `passwordBlacklist`) sang G1, cùng luồng đăng ký nhà bán. Hostname `kc-admin.` (vào admin bằng `port-forward`) và re-encrypt bằng `BackendTLSPolicy` (`edge` nói HTTP với Keycloak) sang G7.
- **Chart `app` bản mỏng** (21, 22): giữ Deployment, Service, probe, resources, securityContext, `jvm.*` và truststore, `httpRoute`, Job `PreSync`, SealedSecret, `secretRevision`, `helm lint` và `kubeconform`. Sang G7: `ct install` trên kind, JSON schema, NetworkPolicy, PDB, `topologySpreadConstraints`.
- **Image** (23): giữ build một lần, tag SHA, digest, Trivy. Sang G7: SBOM, `actions/attest`, `gh attestation verify`.
- **Xếp sang G7 toàn bộ:** ticket 09 (backup `pg-main`), 12 (SSO và RBAC cho Argo CD), 31 (smoke e2e), 33 (rollout không lỗi dưới tải), bản 24 giờ của 34. Mỗi ticket có dòng `Hoãn tới: G7`.
- **User Stories xếp sang G7:** 10, 18, 50, 52, 53, 77–80, 82; phần `kc-admin.` của 16; phần "image build sẵn" của 27 (sang G1); phần PDB của 40; 41, 43, 45; phần SBOM và attestation của 49; phần "sau 24 giờ" và RustFS của 83. Story 81 và 84 chỉ áp cho artifact thuộc mức đầy đủ.
- **Kafka, Apicurio và contract Avro sang đầu G1** (ticket 15, 16, 20; chốt với chủ repo, cùng ngày, sau khi lập lại thứ tự làm). G0 không có producer hay consumer nào, nên ba ticket này làm khi service G1 đầu tiên phát event. Cổng ra khỏi G0 bỏ dòng Kafka và Apicurio. Ticket 34 vẫn đo RAM toàn cụm, nhưng thiếu Kafka (phần tốn RAM lớn nhất), nên quyết định giữ hay sửa ADR-0004 dời tới lúc Kafka lên. Mỗi ticket có dòng `Hoãn tới: G1`.
- **Bỏ thư viện dùng chung `libs/service-kit`** ([ADR-0018](../../adr/0018-self-contained-services-no-shared-library-yet.md); chốt với chủ repo, cùng ngày, khi bắt đầu ticket 23). Chủ repo mới học Spring Boot và muốn tự cấu hình từng thứ; G0 chỉ có một service nên thư viện chung chưa có ai hưởng.
  - Service là project Spring Boot bình thường do Spring Initializr sinh (generator của IntelliJ hoặc start.spring.io), giữ mặc định, lệch thì ghi lý do tại chỗ ([spring-service.md](../../standards/spring-service.md)).
  - Layout hexagonal giữ làm quy ước, **không có ArchUnit**.
  - Problem Details, entry point 401, UUIDv7 viết trong `hello` (ticket 26, 28, 29).
  - Hook RLS, `ScopedValue`, chế độ "không thuộc Workspace" và test catalog RLS sang G1 (ticket 25, `Hoãn tới: G1`). Ở G0 `hello` chỉ có bảng toàn cục, không có RLS.
  - Tag image cho Testcontainers ghim trong test của `hello`; job so lệch tag (ticket 32) chỉ so compose với `gitops`.
  - Reusable workflow `java-library.yml` trong `platform` bị xóa; `contracts` (ticket 19) tự viết bước publish Maven. Repo `commerce-hub-service-kit` được archive; ticket 18 giữ `resolved` làm lịch sử.
- **Thứ tự làm**: xem mục [Thứ tự làm](#thứ-tự-làm) ngay dưới. Mục đó thay dòng "Thứ tự sau ticket 08" cũ (ba chuỗi song song Keycloak, deploy, code).

Phần lớn quyết định dưới đây đã chốt ở ticket 01–19 của map và ADR. Spec chỉ gom lại theo module và thêm những quyết định mới cần cho G0, đánh dấu **(mới)**. Phiên bản lấy theo dòng "Phiên bản áp dụng" của từng file `docs/standards/`.

### Thứ tự làm

Chốt 2026-11-15 với chủ repo. Đây là nơi duy nhất ghi thứ tự; ticket không có trường thứ tự riêng.

- **Số ticket là ID cố định**, không đánh số lại. Số đã nằm trong khoảng 100 commit và hơn 100 file của các repo; đổi số thì commit cũ trỏ nhầm ticket.
- **Mục tiêu là code hệ thống.** Dựng khung `hello`, đưa lên lab sớm, rồi thêm code dần; mỗi tính năng đi qua đường deploy đã chạy, nên lỗi tích hợp lộ ra khi `hello` còn ít thứ để hỏng.
- **Hạ tầng làm khi code cần tới**: mỗi ticket hạ tầng đứng ngay trước ticket code dùng nó.

Đã xong: 01–08, 17, 18 (`service-kit`, thôi dùng từ 2026-11-15). Hoãn: 09, 12, 31, 33 (G7); 15, 16, 20, 25 (G1).

| # | Ticket | `hello` có thêm gì | Chặn bởi |
|---|---|---|---|
| 1 | 23, các bước code | Repo, app chạy được, Dockerfile, số đo image trên máy | 01 |
| 2 | 17 | Reusable workflow, push lên GHCR | 01 |
| 3 | 23, các bước CI | Image trên GHCR; đóng 23 | 17 |
| 4 | 21 | Chart `app` | 17 |
| 5 | 22 | Route qua `edge`, truststore | 07, 21 |
| 6 | 24 | Khung `hello` chạy trên lab qua GitOps | 06, 22, 23 |
| 7 | 19 | OpenAPI của `hello` | 01 |
| 8 | 26 | API lời chào bằng JdbcClient và Flyway, chạy trên máy bằng `bootTestRun` | 19 |
| 9 | 27 | API có DB chạy trên lab (Job `PreSync`) | 08, 24, 26 |
| 10 | 28 | Problem Details | 19, 26 |
| 11 | 10 | Keycloak | 08 |
| 12 | 11 | Realm dạng code | 10 |
| 13 | 29 | Bắt JWT | 11, 27, 28 |
| 14 | 13 | Prometheus, Grafana | 06 |
| 15 | 14 | Collector, Tempo, Loki | 13 |
| 16 | 30 | Trace, log, metric, dashboard của `hello` | 14, 27 |
| 17 | 32 | Compose cho vòng dev trên Mac | 11, 26 |
| 18 | 34 | Đóng G0 | 29, 30, 32 |

Keycloak (10, 11) phải đứng trước 29: sau 29, mọi route của `hello` bắt JWT, nên `hello` trên lab trả 401 cho mọi request nếu chưa có realm.

### Phạm vi G0 so với G1

- G0 dựng toàn bộ hạ tầng mà G1 cần (kể cả Kafka, Apicurio, Keycloak), nhưng **không** dựng service nghiệp vụ nào. Kafka và Apicurio chỉ được chứng minh ở mức cụm và pipeline `contracts`. Chưa có producer hay consumer thật. **(sửa 2026-11-15)** Kafka, Apicurio và contract Avro sang đầu G1 (mục "Sửa phạm vi 2026-11-15").
- **(mới)** `hello` không thuộc Workspace nào. Bảng của nó là bảng toàn cục, không có `workspace_id`, nằm trong allowlist của test catalog RLS, kèm lý do ghi ngay tại chỗ (**sửa 2026-11-15:** G0 không có test catalog RLS, sang G1 cùng ticket 25, [ADR-0018](../../adr/0018-self-contained-services-no-shared-library-yet.md)). Lý do: ở G0 chưa có service `workspace`, topic `workspace.members` hay bản sao Member, nên không kiểm được `X-Workspace-Id`. Một template nhận header mà không kiểm Member sẽ dạy sai mặc định.
- **(sửa 2026-11-15)** ~~Ở G0, `libs/service-kit` module `workspace-access` chỉ có phần dữ liệu: `ScopedValue`, hook đầu transaction, chế độ "không thuộc Workspace", và test-fixtures. Filter HTTP kiểm Member, bản sao Member và interceptor consumer Kafka làm ở G1, cùng service `workspace`. Khi đó template `hello` đổi theo: lấy một bảng có `workspace_id` làm ví dụ.~~ Không còn thư viện dùng chung; toàn bộ `workspace-access` (kể cả phần dữ liệu) sang G1, viết trong service đầu tiên có bảng theo Workspace ([ADR-0018](../../adr/0018-self-contained-services-no-shared-library-yet.md)).
- **(mới)** `hello` mở ra ngoài qua `hello.lab.internal` trên Gateway `edge`. Đây là ngoại lệ chỉ có ở G0. Từ G1, chỉ `seller-web`, Keycloak và simulator ra ngoài; gateway là ClusterIP (ticket 07, 18). Khi service G1 đầu tiên lên lab, gỡ Deployment `hello` khỏi `gitops` để trả 512 Mi cho ngân sách ADR-0004. Repo `hello` vẫn là template.
- **(mới)** Môi trường duy nhất trên cụm tên là `lab`. Mỗi service một namespace trùng tên service. Namespace do app `platform` tạo, kèm nhãn cho phép gắn route vào `edge`.

### Cụm home lab (`platform`, runbook)

- Dựng theo [homelab](../../../platform/docs/homelab-hyperv.md) mục 1–8: kubeadm 1.37, Calico (tắt Goldmane, Whisker), MetalLB (`10.20.0.200` cố định cho `edge`), local-path, metrics-server; VM `gw` với Tailscale subnet router, registry HTTP `10.20.0.5:5000`, dnsmasq cho `lab.internal`, RustFS cho backup, Mailpit v1.33.1 (systemd, `MemoryMax=128M`).
- Ansible hóa các bước dựng VM nằm ngoài G0 (xem Out of Scope).

### `gitops`: bootstrap và cấu trúc

- Argo CD v3.6.1 cài bằng Kustomize overlay ghim tag; app tự quản lý có `ServerSideApply=true`. Bootstrap đúng hai lệnh: apply overlay Argo CD, rồi apply root app của môi trường `lab`.
- App-of-apps: root `Application` trỏ thư mục `lab`, chứa `AppProject`, `Application` của hạ tầng và một `ApplicationSet` (Git directory generator) cho service. Trường `project` viết cứng.
- AppProject: `default` khóa rỗng; `platform` cho hạ tầng (được tạo tài nguyên cluster-scoped, chỉ admin); `commerce` cho service (nguồn chỉ là `gitops` và registry chart, đích chỉ namespace service, cấm `ResourceQuota`, `LimitRange`, `Gateway`, `BackendTLSPolicy`).
- Thứ tự sync wave của hạ tầng: Sealed Secrets (wave 1, ngay sau app `argocd`) → CRD Gateway API → cert-manager → trust-manager, Envoy Gateway → Gateway `edge`, `ClusterIssuer lab-ca` → operator (Strimzi, CloudNativePG, Keycloak Operator) → CR dữ liệu (`Kafka`, `Cluster`, `Keycloak`) → LGTM → service. `argocd-cm` có health check Lua cho `Application` và cho CRD của operator, `Gateway`, `HTTPRoute`. **(sửa 2026-11-14, G0-04)** Sealed Secrets đứng đầu vì `ClusterIssuer lab-ca` đọc Secret `lab-intermediate-ca`, mà Secret đó sinh từ một SealedSecret; bản cũ xếp Sealed Secrets sau `lab-ca`.
- Service dùng multiple sources: chart `app` từ registry OCI qua HTTP (`insecureOCIForceHttp`, không kèm `insecure`), values từ `gitops`. `targetRevision` của chart là SemVer cụ thể.
- App service: automated sync với `prune`, `selfHeal`, retry hữu hạn, `PruneLast`, `FailOnSharedResource`; không `CreateNamespace`.
- Secret: Sealed Secrets (scope `strict`). Sao lưu khóa sealing ra ngoài cụm sau mỗi lần gia hạn (password manager), có runbook. Chart nhận `secretRevision` để rollout khi đổi secret.
- RBAC: SSO qua client `argocd` của Keycloak, `admin.enabled: false`, `policy.default: role:readonly`, quyền sync chỉ cho group admin của realm. `policy.csv` được validate trong CI của `gitops`.
- **(mới)** Tài khoản Argo CD cho `e2e`: một project role chỉ đọc trong `commerce`, token có `--expires-in`, cất ở secret của repo `e2e`. Đây là ngoại lệ có chủ đích với dòng "không tạo account cho CI" của [gitops-argocd.md](../../standards/gitops-argocd.md), đã chốt ở ticket 19. Ghi lý do vào file chuẩn đó.

### App `platform` trong `gitops`: cửa vào và PKI

- Gateway API CRD v1.6.1 standard, Envoy Gateway v1.10.0 (1 replica Envoy, limit đặt tay), cert-manager (bật Gateway API), trust-manager v0.26.0 với `Bundle` `lab-trust` sinh cả PEM lẫn truststore PKCS12.
- Gateway `edge` trong namespace `edge`: listener HTTPS wildcard `*.lab.internal`, route chuyển HTTP sang HTTPS, `allowedRoutes` theo selector nhãn namespace.
- Root CA offline (có name constraints) trên Mac; intermediate trong cụm là `ClusterIssuer lab-ca`. Root (phần công khai) được tin trên Mac qua Keychain và trên runner CI qua store của OS.
- Hostname G0: `argocd.`, `grafana.`, `auth.`, `kc-admin.`, `hello.` **(mới)**. Prometheus, Alertmanager dùng `port-forward`.

### PostgreSQL (`pg-main`)

- CloudNativePG 1.30.1 (nâng 1.31 khi ra), PostgreSQL 18 image `standard`, 1 instance, requests = limits ([ADR-0003](../../adr/0003-shared-postgres-cluster.md), [ADR-0004](../../adr/0004-single-instance-by-default-on-homelab.md)).
- Backup: plugin Barman Cloud v0.16.0, đích RustFS trên `gw`, `archive_timeout: 1min`, `ScheduledBackup` hằng ngày, giữ 14 ngày. G0 chỉ chứng minh archive WAL liên tục và có base backup thành công. Diễn tập khôi phục và đo RTO nằm ngoài G0.
- Pooler PgBouncer `transaction` 1 pod cho runtime; Flyway và Keycloak nối thẳng `pg-main-rw`.
- Mỗi service một database cộng bốn role `_owner`/`_migrator`/`_app`/`_lookup`, khai báo bằng CR của CloudNativePG trong app `platform` ([ADR-0010](../../adr/0010-workspace-isolation-shared-schema-with-mandatory-rls.md)). Mật khẩu là SealedSecret. G0 có database `keycloak` và `hello`. `hello` giữ đủ bốn role (kể cả `_lookup`) để template khớp với service G1.
- Cách xử lý PDB của CloudNativePG khi drain node mà chỉ có 1 instance: thử thật ở G0, ghi kết quả vào runbook và [ADR-0004](../../adr/0004-single-instance-by-default-on-homelab.md) nếu phải lệch.

### Kafka và Apicurio

- Strimzi 1.3.1, Kafka 4.3.2 KRaft, 3 node dual-role, mỗi broker 1 Gi với heap 512m, `default.replication.factor: 3`, `min.insync.replicas: 2`. Entity Operator (topic và user) có limit. Có Strimzi Drain Cleaner.
- Listener nội bộ bắt xác thực ngay từ G0, theo mục "Bảo mật" của [kafka.md](../../standards/kafka.md). `KafkaUser` cho từng service thêm ở G1.
- Apicurio Registry 3 qua operator, lưu trên `pg-main` hoặc theo mặc định của operator (chọn theo [kafka.md](../../standards/kafka.md)). Tắt UI nếu `spec.ui` cho phép (**chưa xác minh**, thử ở G0).
- G0 không tạo topic nghiệp vụ. Topic `perf` chỉ tạo tạm cho phép đo độ bền, xong thì xóa.

### Keycloak

- Keycloak Operator 26.8.2 (CR `v2beta1`), 1 instance, image build sẵn (chứa theme và `passwordBlacklist`), DB `keycloak` trên `pg-main`. Hostname `auth.lab.internal`, admin ở `kc-admin.lab.internal`. Re-encrypt từ Envoy tới 8443 bằng `BackendTLSPolicy` v1. Route công khai chỉ gồm `/realms/commerce-hub`, `/resources/`, `/.well-known/`.
- Realm `commerce-hub` là YAML trong `gitops`, áp bằng Job keycloak-config-cli. SMTP trỏ Mailpit `10.20.0.5:1025`.
- Client ở G0: `argocd` (SSO cho Argo CD), `grafana` (SSO cho Grafana), và **(mới)** một client test confidential chỉ bật client credentials, có mapper Audience `commerce-hub-api`, dùng cho smoke test và k6. Secret của client test là SealedSecret trong cụm và là secret của repo `e2e`. Client của `seller-web`, `admin-web`, role `platform-admin` và theme đăng ký thuộc G1 (ticket 05, 07).
- Một group admin trong realm map sang quyền admin của Argo CD và Grafana. Tài khoản admin của chủ repo tạo tay qua `kc-admin.` theo runbook. Realm-as-code không chứa user có mật khẩu.

### Quan sát (LGTM)

- Theo [observability.md](../../standards/observability.md): kube-prometheus-stack (Prometheus 1 bản, retention 15 ngày, `ServerSideApply`), Loki chart `grafana-community/loki` chế độ Monolithic (tắt chunks-cache, results-cache), Tempo monolithic retention 7 ngày, Grafana có datasource và dashboard dạng code, OTel Collector contrib dạng DaemonSet (preset `kubernetesAttributes`, `logsCollection`). Tất cả trong namespace `observability`, limit theo bảng của ticket 04.
- Chart monolithic của Tempo (repo nào sau khi chart chuyển sang grafana-community) là điểm **chưa xác minh**, chốt khi dựng.
- Liên kết Grafana: log → trace theo `traceId`, metric → trace qua exemplar.
- **(mới)** Một dashboard dùng chung "Service overview" (RED theo `http.server.requests`, JVM memory và GC, Hikari pool), chọn service bằng biến. G1 không cần dashboard riêng cho mỗi service, trừ dashboard business metric.
- **(mới)** Một service account Grafana quyền Viewer, token cất ở secret của repo `e2e`, để smoke test đọc Tempo và Prometheus qua API proxy datasource của Grafana. Không mở Tempo hay Prometheus ra `edge`.

### Chart `app` (`platform`)

- Theo [helm-chart.md](../../standards/helm-chart.md) và ticket 11: một chart cho mọi workload, publish OCI lên `10.20.0.5:5000/charts` với SemVer. Chart mặc định 2 replica; values lab đặt 1 (ADR-0004).
- Values có JSON schema; digest image bắt buộc. Có `jvm.enabled` (mặc định `true`) đặt `JAVA_TOOL_OPTIONS` với `MaxRAMPercentage` chỉnh được và truststore của trust-manager; app Node đặt `NODE_EXTRA_CA_CERTS`.
- Bật bằng values: `httpRoute.*` gắn vào `edge`; Job migrate `PreSync` (`hook-delete-policy: BeforeHookCreation`, không `ttlSecondsAfterFinished`); port thứ hai; SealedSecret; `secretRevision`.
- Endpoint OTLP trỏ vào Collector cùng node, lấy IP node qua downward API.
- NetworkPolicy ingress theo danh sách cho phép; có route thì tự mở cho pod Envoy của `edge`. Egress mở mặc định, chỉ siết khi khai báo `egress.to`.
- Pod Security "restricted", non-root, `readOnlyRootFilesystem`, PDB, `topologySpreadConstraints`, probe theo nhóm health của Actuator, preStop lớn hơn độ trễ gỡ endpoint đo được.
- Kiểm: `helm lint --strict`, `kubeconform` với K8s 1.37, `ct install` trên kind trần trong CI. Biến thể `ci/` tắt Job `PreSync` và SealedSecret.

### CI/CD (`platform` và mọi repo)

- Reusable workflow trong `platform`: `java-service`, ~~`java-library`~~, `contracts`, `update-gitops`, `chart`. **(mới)** Tách `java-library` khỏi `java-service` vì lib publish Maven từ tag và không build image. **(sửa 2026-11-15)** `java-library.yml` đã xóa cùng `service-kit` ([ADR-0018](../../adr/0018-self-contained-services-no-shared-library-yet.md)); `contracts` tự viết bước publish Maven ở ticket 19. `node-app` để G1.
- `platform` phát hành bằng release SemVer bất biến. Repo gọi ghim SHA đầy đủ kèm comment version.
- Mọi workflow: `permissions` tối thiểu, action ghim SHA, không `pull_request_target`, secret truyền tường minh, `timeout-minutes`, upload báo cáo test khi đỏ. Job push image, attestation, `update-gitops` chỉ chạy khi push vào nhánh mặc định.
- Image: build một lần trên runner amd64 bằng Buildx, tag là git SHA, ghi digest; Trivy chặn HIGH/CRITICAL đã có bản vá; SBOM của BuildKit; `actions/attest` rồi `gh attestation verify` trước khi sửa `gitops`. Nếu verify không chạy được với registry HTTP thì ghi lý do bỏ vào lệch chuẩn của [ci-cd.md](../../standards/ci-cd.md).
- Vào lab: `tailscale/github-action` với OIDC, node ephemeral. `tag:ci` chỉ tới `10.20.0.5:5000`. **(mới)** `tag:e2e` chỉ tới `10.20.0.200:443` (Gateway `edge`) và DNS `10.20.0.5:53`.
- `update-gitops`: token GitHub App (`actions/create-github-app-token`), sửa digest và tag trong values của service, commit message có tên service, SHA nguồn, link run; `concurrency` theo môi trường; vòng `pull --rebase` khi push bị từ chối; cuối cùng gửi `repository_dispatch` sang `e2e` kèm tên app và SHA. **(mới)** GitHub App được cài trên `gitops` và `e2e`; mỗi lần chạy sinh token giới hạn đúng một repo. Ghi thay đổi này vào [ci-cd.md](../../standards/ci-cd.md), vì chuẩn đang ghi "chỉ cài trên `gitops`".
- **(mới)** Một script trong `platform` tạo và cấu hình repo bằng `gh`: public, MIT, bảo vệ nhánh tối thiểu (ruleset nếu tài khoản cá nhân bật được, không thì branch protection), secret scanning, push protection, CodeQL default setup, Dependabot, policy ghim SHA ở mức repo nếu không có ở mức owner.

### `contracts`

- G0 chứa OpenAPI của `hello` và schema `Problem` dùng chung (danh mục `code` nghiệp vụ còn rỗng). Chưa có schema Avro nghiệp vụ; schema Member và sáu event thuộc G1.
- CI: lint OpenAPI → `oasdiff breaking` so với tag trước → kiểm Avro `BACKWARD_TRANSITIVE` với Apicurio trong Testcontainers → sinh code → publish Maven và npm lên GitHub Packages chỉ từ tag.
- Nhánh Avro của pipeline được chứng minh ở G0 bằng một schema thử trong PR không merge (xóa field không default thì CI đỏ).
- Sinh code OpenAPI: plugin Gradle `org.openapi.generator`. Sinh code Avro và công cụ lint OpenAPI: chọn ở ticket của `contracts`, với tiêu chí còn bảo trì, chạy với Gradle 9 và Avro 1.12. Ghi lựa chọn kèm nguồn vào [ci-cd.md](../../standards/ci-cd.md). Tên lệnh đăng ký schema chốt cùng lúc (ticket 13).
- Đọc package chéo repo bằng `GITHUB_TOKEN` (Maven từ `hello`, npm từ `e2e`) là điểm **chưa xác minh**. Không được thì dùng classic PAT `read:packages` cất ở secret.

### `libs/service-kit` (bản G0)

**(sửa 2026-11-15)** Bỏ cả mục này ([ADR-0018](../../adr/0018-self-contained-services-no-shared-library-yet.md)). Giữ nguyên văn bên dưới làm tham khảo cho G1, khi xét lại việc tách thư viện. Phần còn hiệu lực đã chuyển: Problem Details, 401, UUIDv7 vào `hello`; `workspace-access` sang G1; tag image Testcontainers ghim trong test của từng service, job so lệch chỉ so compose với `gitops`.

- Một repo, nhiều module, chung một version; tọa độ `io.github.<user>.commercehub`; publish GitHub Packages từ tag; mỗi bản gắn với một minor Spring Boot (ticket 11).
- Module có ở G0: `gradle-plugin` (convention `commercehub.spring-service`), `test-support` (luật ArchUnit, cấu hình Testcontainers, bảng tag image), `workspace-access` (phần dữ liệu, xem dưới), `web` (Problem Details, `traceId`, entry point 401), `ids` (UUIDv7).
- Module để G1: `events`; phần HTTP filter, bản sao Member, interceptor Kafka của `workspace-access`; cursor, `Idempotency-Key`, `ETag`/`If-Match` của `web`.
- `workspace-access` ở G0:
  - Workspace hiện tại giữ trong `ScopedValue`.
  - Hook `TransactionExecutionListener.afterBegin` chạy `set_config('app.workspace_id', ?, true)`, dùng được cho cả `DataSourceTransactionManager` lẫn `JpaTransactionManager` (ADR-0012).
  - Thiếu context thì ném exception. Không cho đổi Workspace khi transaction đang mở.
  - **(mới)** Có chế độ khai báo tường minh "transaction không thuộc Workspace": hook không đặt tham số, nên mọi bảng có RLS trả 0 dòng (policy dùng `nullif`). Không có chế độ nào bỏ qua RLS. `hello` dùng chế độ này; `workspace` dùng cho bảng `account` ở G1.
  - Test-fixtures: test catalog (RLS `ENABLE`/`FORCE`, policy đúng mẫu, allowlist bảng toàn cục, FK ghép, quyền sở hữu hàm, quyền của `_app`) và test hành vi qua container PgBouncer `transaction`.
- **(mới)** Nguồn tag image: production trong `gitops` là nguồn sự thật. `test-support` giữ bảng tag cho Testcontainers; compose giữ tag của nó. Một job theo lịch trong `platform` so major.minor của PostgreSQL, Kafka, Keycloak, Apicurio giữa ba nơi (đọc file của repo public qua API) và đỏ khi lệch. Job chỉ kiểm, không phải phụ thuộc lúc build, nên không trái ADR-0001.

### `services/hello` (template)

- Java 25, Spring Boot 4.1.2, Spring MVC trên virtual thread, ~~Gradle 9 Groovy DSL với convention plugin~~ project do Spring Initializr sinh (Gradle Groovy DSL), giữ mặc định theo [spring-service.md](../../standards/spring-service.md) (sửa 2026-11-15), bật "template repository" trên GitHub.
- Layout hexagonal một module: `domain`, `application` (use case cộng port), `adapter.in.web`, `adapter.out.persistence`. Persistence dùng `JdbcClient`. ~~Mẫu JPA nằm trong test của `service-kit`, không nằm trong template.~~ **(sửa 2026-11-15)** Layout là quy ước, không có ArchUnit. Mẫu JPA có ở service JPA đầu tiên của G1.
- **(mới)** API (contract trong `contracts`): tạo lời chào từ một `name` (1–50 ký tự), trả 201 với ID UUIDv7 và header `Location`; đọc lời chào theo ID trả 200, hoặc 404 Problem Details khi không có. Tiền tố `/v1`. Mọi route bắt buộc JWT, `aud` là `commerce-hub-api`, chỉ RS256.
- Bảng toàn cục duy nhất, Flyway chạy bằng profile `migrate` trong Job `PreSync` với role `_migrator`; runtime dùng `_app` qua PgBouncer.
- Quan sát: `spring-boot-starter-opentelemetry` cộng `micrometer-registry-prometheus`, không dùng OTel Java agent; resource attributes đặt tường minh (`service.name`, `service.namespace=commerce-hub`, `service.version`, `deployment.environment.name=lab`); log JSON có `traceId`; Actuator ở management port riêng.
- **(mới)** Span DB là bắt buộc. Thư viện sinh span JDBC (ứng viên `datasource-micrometer`) chạy được với Spring Boot 4.1 hay không là điểm **chưa xác minh**, chốt khi làm ticket `hello`. Lựa chọn ghi vào [observability.md](../../standards/observability.md) để mọi service dùng chung.
- Profile: `local` (compose trên Mac, OTLP `localhost:4318` khi bật `obs`, exporter `none` khi không), `migrate`, và mặc định cho lab (cấu hình qua env từ chart).
- Image: Dockerfile theo [container-image.md](../../standards/container-image.md) (layer của Spring Boot, AOT cache Java 25, uid 10001, chỉ `linux/amd64`).
- Values lab: 1 replica, memory 512Mi request = limit, `MaxRAMPercentage=60` (chốt lại sau khi đo RSS), `httpRoute` host `hello.lab.internal`.

### `platform/compose` và `platform/kind`

- Theo ticket 13: Kafka KRaft 1 broker, Apicurio 3, PostgreSQL 18 (database và bốn role cho mỗi service; G0 có `hello`), PgBouncer `transaction`, Keycloak; hai init đọc `../gitops` (keycloak-config-cli áp realm; `yq` đọc CR `KafkaTopic`); `.env.example`; profile `obs` với `grafana/otel-lgtm`. README ghi lệch ADR-0001 chỉ ở dev.
- `platform/kind`: cấu hình kind cho `ct install` trong CI.

### `e2e`

- Repo mới, Playwright (TypeScript), chạy trên GitHub-hosted runner qua Tailscale `tag:e2e`, tin root CA của lab qua store của OS.
- Kích hoạt: `repository_dispatch` từ `update-gitops`, lịch hằng đêm, `workflow_dispatch`; `concurrency: { group: e2e-lab, cancel-in-progress: false }`. Bước đầu là `argocd app wait <app> --sync --health --timeout 10m` với token chỉ đọc.
- Smoke G0 cho `hello`:
  - không token, token sai `aud` → 401 Problem Details có `traceId`;
  - token client credentials → tạo lời chào (201), đọc lại (200), ID lạ (404), tên quá dài (400 có `errors[]`);
  - test tự sinh `traceparent`, rồi dùng `expect.poll` trên Tempo (qua Grafana) tới khi trace có span server HTTP và span DB của `service.name=hello`;
  - dashboard "Service overview" tồn tại theo UID; Prometheus có `http_server_requests_seconds_count` của `hello`.
- Đỏ thì upload báo cáo Playwright (trace, video). Không tự rollback.

### Tài liệu (`docs`)

- arc42 mục 7 (deployment view): node, VM `gw`, namespace, cửa vào, luồng CI → registry → `gitops` → Argo CD.
- Runbook trong `docs/runbooks/`: bootstrap cụm từ trắng; sao lưu và khôi phục khóa sealing; thêm một service mới (database, role, values, namespace); tạo tài khoản admin trong realm.
- Cập nhật `docs/standards/`: đánh dấu checklist đã làm, đổi **chưa xác minh** thành kết quả, ghi các quyết định **(mới)** ở trên vào đúng file. Thêm `hello.` vào danh sách hostname của [cluster-entry.md](../../standards/cluster-entry.md).
- Ma trận truy vết: dòng N12 ghi G0 xong phần khung, kèm link dashboard và một trace ID mẫu.

### Cổng ra khỏi G0

- **(sửa 2026-11-15)** G0 xong khi:
  - `hello` deploy qua GitOps từ CI, image lấy từ GHCR;
  - `hello` bắt buộc JWT do realm `commerce-hub` phát;
  - mỗi request có trace trên Tempo (span HTTP và span DB), log trên Loki, metric và dashboard "Service overview";
  - ~~Kafka 3 broker và Apicurio chạy, pipeline Avro chặn được thay đổi phá vỡ;~~ sang đầu G1 (mục "Sửa phạm vi 2026-11-15");
  - vòng dev bằng `platform/compose` trên Mac chạy được;
  - đo **một lần** `kubectl top` toàn cụm và RSS của `hello`, so với bảng ADR-0004 kèm phần dự kiến cho G1. Bản đo này chưa có Kafka, nên quyết định giữ hay sửa ADR-0004 dời tới lúc Kafka lên ở đầu G1. Bản đo sau 24 giờ sang G7.
  - Bản cũ (đo sau 24 giờ, chờ 09, 31, 33) bị thay bởi danh sách này.

## Testing Decisions

### Thế nào là một test tốt ở đây

- Test hành vi nhìn từ ngoài qua seam cao nhất có thể: HTTP của service, SQL thật của PostgreSQL qua PgBouncer, cụm thật qua Gateway `edge`. Không test chi tiết cài đặt (bean nào được gọi, method private).
- Mỗi test đặt ở tầng thấp nhất chứng minh được điều nó cần (bảng phân tầng của ticket 19). e2e chỉ giữ thứ bắt buộc phải có cụm thật.
- Tên test chứa mã yêu cầu khi có (`N12_…`, `N11_…`, `BR04_…`); test hạ tầng không có mã thì đặt tên theo hành vi.
- Chờ nhất quán cuối cùng bằng `expect.poll` hoặc Awaitility, không `sleep`.
- Không đặt ngưỡng coverage.

### Bốn seam test (đã thống nhất với chủ repo)

1. **Lab thật, qua `edge`** (repo `e2e`): smoke ở mục `e2e` trên, gồm cả assertion trace (Tempo) và dashboard (Grafana, Prometheus). Đây là seam chứng minh mục tiêu G0: "service hello có trace và dashboard".
2. **Service qua HTTP** (`./gradlew check` của `hello`): MockMvc với PostgreSQL thật đi qua PgBouncer `transaction` (Testcontainers), Flyway chạy từ đầu.
   - Request và response kiểm với OpenAPI từ artifact `contracts` (ví dụ `swagger-request-validator`).
   - 401 với token thiếu, sai `aud`, hết hạn, realm khác, ký bằng khóa lạ (JWK giả trong test).
   - 404 và 400 trả Problem Details đúng dạng, có `traceId`.
   - ~~Test catalog RLS từ test-fixtures pass, với bảng của `hello` trong allowlist.~~ Sang G1 (sửa 2026-11-15).
   - ~~Luật ArchUnit pass.~~ Bỏ (sửa 2026-11-15).
   - Một test chạy migration với PostgreSQL 17.x và 18.x theo [db-migration.md](../../standards/db-migration.md).
3. ~~**Thư viện `service-kit`** (`./gradlew check` của lib):~~ **(sửa 2026-11-15)** Bỏ seam này ([ADR-0018](../../adr/0018-self-contained-services-no-shared-library-yet.md)). Test hook RLS và test catalog sang G1, chạy trong service đầu tiên có bảng theo Workspace; test Problem Details nằm ở seam 2 của `hello`; ArchUnit bỏ. Nội dung cũ:
   - Hook RLS, chạy với một mẫu `JdbcClient` và một mẫu JPA trong test: đổi Workspace trên cùng server connection của PgBouncer, truy vấn ngoài transaction trả 0 dòng, thiếu context thì ném exception, `WITH CHECK` từ chối insert sai Workspace, chế độ "không thuộc Workspace" thấy 0 dòng của bảng có RLS. Đặt tên `N11_`.
   - Test catalog tự kiểm: một schema cố ý sai (thiếu `FORCE`, policy sai mẫu, FK không ghép) phải bị bắt.
   - Luật ArchUnit tự kiểm bằng một package cố ý vi phạm.
   - Problem Details: dạng `about:blank`, `traceId`, `errors[]`.
4. **Chart `app`** (CI của `platform`): `helm lint --strict`, `kubeconform`, schema values từ chối thiếu digest, `ct install` trên kind cho mọi biến thể `ci/`.

### Hạ tầng: bằng chứng thay cho test tự động

Argo CD, cửa vào, PKI, PostgreSQL, Kafka, Keycloak, LGTM không có test tự động riêng. Mỗi thành phần chạy đúng bảng "Bằng chứng cần có" trong file `docs/standards/` tương ứng, ghi số đo và ngày vào `docs/experiments/`. Phần thuộc G0 của từng bảng:

- [gitops-argocd.md](../../standards/gitops-argocd.md): đủ cả bảng.
- [cluster-entry.md](../../standards/cluster-entry.md): đủ cả bảng; "Trust ở JVM" và "Trust ở Node" kiểm bằng `hello` và một pod Node tạm thay cho `channel-connector` và `seller-web`.
- [db-migration.md](../../standards/db-migration.md): chạy từ đầu, bất biến, PreSync chặn deploy, `lock_timeout`, tách quyền, owner đúng, ~~hai tầng N11 trong lib~~ (sang G1, sửa 2026-11-15). Phép đo khóa trên bảng 1 triệu hàng và rollback dưới tải để G1, khi có bảng thật.
- [kafka.md](../../standards/kafka.md): cụm KRaft khỏe, không mất ghi khi mất một broker, min ISR, schema CI đỏ, RAM. Các dòng KIP-848, rebalance, DLT, ACL để G1.
- [keycloak.md](../../standards/keycloak.md): production mode, issuer, đường dẫn bị chặn, giả `X-Forwarded-For`, re-encrypt, health và metric, realm idempotent, resource server (qua `hello`), refresh rotation, brute force, tài nguyên. Dòng BR-07 để G1.
- [observability.md](../../standards/observability.md): trace (phần G0), log nối trace, metric có histogram và exemplar, cardinality, chi phí tracing, tài nguyên LGTM. Header qua Kafka, PII, alert lag để G1–G2.
- [container-image.md](../../standards/container-image.md), [ci-cd.md](../../standards/ci-cd.md): đủ cả bảng, đo trên `hello`.
- [helm-chart.md](../../standards/helm-chart.md): đủ cả bảng.
- [zero-downtime.md](../../standards/zero-downtime.md): đổi image qua GitOps, restart, drain node, deploy có migration, với `hello` tạm chạy 2 replica rồi revert (ADR-0004), cộng một lần đối chứng âm. Dòng webhook và consumer Kafka để G2.

### Prior art

Chưa có code trong polyrepo, nên không có test cũ để noi theo. Mẫu gần nhất là bảng phân tầng và DoD test của [ticket 19](../architecture-g0-g1/issues/19-g1-test-strategy.md#answer), cùng các bảng "Bằng chứng cần có" trong `docs/standards/`. Test của G0 trở thành prior art cho G1: ~~test-fixtures của `service-kit`,~~ test HTTP của `hello`, smoke của `e2e`.

## Out of Scope

- Mọi service nghiệp vụ G1 (`gateway`, `workspace`, `channel-connector`, `catalog`, `inventory`, `order`), `marketplace-sim`, `seller-web`, cùng client Keycloak, theme, hostname `app.` và `shopee-sim.` của chúng.
- Schema Avro nghiệp vụ, topic nghiệp vụ, `KafkaUser` từng service, module `events`, DLT và alert DLT, giao thức consumer KIP-848.
- **(sửa 2026-11-15)** Hook RLS, `ScopedValue`, test catalog RLS (ticket 25, sang G1, [ADR-0018](../../adr/0018-self-contained-services-no-shared-library-yet.md)).
- Bản sao Member, filter HTTP kiểm `X-Workspace-Id`, interceptor Kafka của `workspace-access`; cursor, `Idempotency-Key`, `ETag`/`If-Match`.
- Diễn tập khôi phục PITR và đo RTO (N10), failover với 2 instance PostgreSQL. Từ 2026-11-15 cả archive WAL và base backup (ticket 09) cũng sang G7.
- **(2026-11-15)** Các phần xếp sang G7 ở mục [Sửa phạm vi 2026-11-15](#sửa-phạm-vi-2026-11-15): backup `pg-main`, SSO cho Argo CD và Grafana, `kc-admin.` và `BackendTLSPolicy` cho Keycloak, `ct install`, JSON schema, NetworkPolicy và PDB của chart, SBOM và attestation, Tailscale trong CI, e2e, rollout dưới tải, đo 24 giờ.
- Phép đo khóa bảng 1 triệu hàng, rollback dưới tải có migration expand/contract (cần bảng thật của G1).
- Trace xuyên Kafka (N12 phần chính, G2), quét PII trong log (cần dữ liệu người mua), SLO và alert (G7), Argo Rollouts (G7).
- Siết egress NetworkPolicy cho mọi app, service mesh, mTLS (G7).
- Redis, OpenSearch, Pact Broker, Tilt, Skaffold, Telepresence.
- Ansible hóa việc dựng VM và cụm (homelab mục 12.2). Đáng làm, nhưng không chặn G1.
- Workflow `node-app` và package npm cho frontend (G1, cùng `seller-web`).

## Further Notes

- **Thứ tự gợi ý cho `/to-tickets`**, theo phụ thuộc:
  1. Script tạo repo, GitHub App, Tailscale ACL (`tag:ci`, `tag:e2e`).
  2. Kiểm cụm và `gw` theo runbook.
  3. Bootstrap `gitops` với Argo CD và Sealed Secrets.
  4. App `platform`: cửa vào, PKI.
  5. `pg-main` và backup.
  6. Keycloak, realm và SSO cho Argo CD.
  7. LGTM.
  8. Kafka và Apicurio.
  9. Chart `app`.
  10. Reusable workflow.
  11. `contracts`.
  12. `service-kit`.
  13. `hello`.
  14. `e2e`.
  15. `platform/compose`.
  16. Đo 24 giờ, bản ghi thí nghiệm, tài liệu, cổng ADR-0004.

  Theo [issue-tracker.md](../../agents/issue-tracker.md), mỗi ticket chỉ đưa vào một khái niệm mới, nên vài bước trên sẽ tách thành nhiều ticket (ví dụ PKI tách khỏi Envoy Gateway, Barman Cloud tách khỏi `pg-main`). Ticket là `ready-for-human` và có mục "Mục tiêu học".
- Bước 9–13 phụ thuộc vào bước 3–8 chỉ ở phần deploy lên lab; phần build, test, `ct install` trên kind làm song song được.
- **(sửa 2026-11-15)** Điểm chưa xác minh phải đóng trong G0 chỉ còn: RSS `hello` ở `MaxRAMPercentage=60`; span JDBC với Spring Boot 4.1; ~~`nullif` với `''` trên connection đã từng đặt tham số~~ (sang G1 cùng ticket 25); đọc package chéo repo bằng `GITHUB_TOKEN`; chart monolithic của Tempo; UI của Apicurio tắt được không; ~~package GHCR của repo public có tự public không (ADR-0017)~~ (đã xác minh ở G0-17, 2026-11-16: có). Ruleset, policy ghim SHA và `actions.lock` đã xác minh ở G0-01; PDB của CloudNativePG đã xác minh ở G0-08. Phần còn lại của danh sách cũ dưới đây (attestation, k6 với Keychain, `timeout-minutes` 360, RAM của RustFS) sang G7.
- Danh sách cũ, **điểm chưa xác minh thuộc G0**, gom từ ticket và chuẩn: RSS `hello` ở `MaxRAMPercentage=60`; PDB của CloudNativePG khi có 1 instance; UI của Apicurio tắt được không; RAM của RustFS và Mailpit trên `gw`; chart monolithic của Tempo; span JDBC với Spring Boot 4.1; k6 trên macOS có đọc root trong Keychain không; ruleset trên tài khoản cá nhân; policy ghim SHA ở mức owner; `actions.lock`; attestation với registry HTTP; đọc package chéo repo bằng `GITHUB_TOKEN`; `nullif` với `''` trên connection đã từng đặt tham số; giới hạn 360 phút của `timeout-minutes`.
- Bản ghi thí nghiệm tổng của G0 (Charter G5: giả thuyết, cách đo, số đo, kết luận) đặt ở `docs/experiments/`, link tới các bản ghi theo chủ đề mà từng file chuẩn quy định.
- Các quyết định **(mới)** trong spec đều đổi lại được với chi phí thấp, nên không viết ADR mới. Riêng cổng ADR-0004 có thể dẫn tới sửa ADR đó.
