---
status: accepted
date: 2026-11-12
---

# ADR-0004: Home lab chạy một instance mặc định, chỉ scale khi làm thí nghiệm

Máy home lab có 32 GB và không nâng được. 3 node K8s có tổng 24 GiB. Ở môi trường lab, mọi service, `shopee-sim`, frontend, PostgreSQL `pg-main` và Keycloak chạy **1 instance**. Khi một thí nghiệm cần nhiều hơn thì mới tăng, ví dụ N15 cần 2 replica, failover PostgreSQL cần 2 instance. Tăng bằng một commit vào `gitops`, xong thí nghiệm thì revert. Số lượng thành phần hạ tầng giữ nguyên: Kafka 3 broker (RF 3, `min.insync.replicas` 2), đủ bộ LGTM, Argo CD, Apicurio. Để vừa RAM, cỡ của từng thành phần được hạ xuống, ví dụ Kafka 1 Gi/broker, service JVM 512 Mi. Bảng ngân sách nằm ở ticket [04 Ngân sách tài nguyên home lab](../.scratch/architecture-g0-g1/issues/04-resource-budget.md#answer). Số mặc định của từng thành phần có nguồn ở [tra cứu 11/2026](../research/2026-11-resource-budget.md).

Chart dùng chung vẫn giữ `replicaCount: 2` mặc định theo [zero-downtime.md](../standards/zero-downtime.md). Chỉ values của môi trường lab trong `gitops` đặt 1, để chỗ lệch chuẩn nằm ở một nơi dễ thấy.

## Phương án đã cân nhắc

- **Giữ 2 replica và cỡ RAM theo `docs/standards/`.** Tổng khoảng 34 GiB, vượt 24 GiB. Riêng phần hạ tầng đã khoảng 22,7 GiB.
- **Nâng máy lên 64 GB.** Người dùng loại: máy giữ 32 GB.
- **Kafka 1 broker (RF 1).** Bị loại vì cấu hình topic sẽ khác production, và lên lại 3 broker phải tăng RF bằng reassignment. Kafka 3 broker cũng là cấu hình mà các case của G2 trở đi dựa vào.
- **Tắt Loki và Tempo ngoài lúc debug.** Bị loại vì đích của G0 là trace và dashboard thường trực.

## Hệ quả

- Rollout hoặc drain node làm service, PostgreSQL và Keycloak gián đoạn. N15 chỉ chứng minh được trong thí nghiệm đã scale lên 2. Chart không render PDB khi chỉ có 1 replica ([helm-chart.md](../standards/helm-chart.md)).
- PostgreSQL 1 instance thì không có replica đồng bộ. RPO dựa vào WAL archive lên RustFS (`archive_timeout: 1min`, N10), và mất node chứa primary là mất ghi tới khi khôi phục. Drain node chứa `pg-main` bị PDB của CNPG chặn (đã thử ở G0-08 bước 8, 2026-11-15: mọi lần evict bị từ chối). Cách xử lý đã chọn là giữ PDB và tạm lên 2 instance qua Git để operator tự switchover sang node khác, rồi về 1: gián đoạn kết nối mới đo được 7,5 s thẳng `pg-main-rw`, khoảng 15 s qua Pooler. `enablePDB: false` và `nodeMaintenanceWindow` bị loại vì database ngừng suốt thời gian bảo trì. Quy trình ở runbook [pg-main-bao-tri-node.md](../runbooks/pg-main-bao-tri-node.md); không phải lệch chuẩn.
- Chỉ còn dư khoảng 520 MiB sau khi thêm cửa vào cụm ([ADR-0013](0013-gateway-api-envoy-gateway-shared-edge.md), cập nhật 2026-11-13; trước đó khoảng 1 GiB). Thí nghiệm cần thêm RAM phải tạm scale về 0 các service không liên quan. Mỗi bản ghi thí nghiệm ghi rõ đã scale gì.
- Mọi số trong ngân sách là ước lượng. Đo service "hello" và hạ tầng ở G0 (`kubectl top`, RSS JVM). Nếu JVM 512 Mi không đủ thì xét lại ADR này trước khi bắt đầu G1.
- Xét lại khi: máy có thêm RAM, hoặc số đo cho thấy ngân sách sai quá 1 GiB.
