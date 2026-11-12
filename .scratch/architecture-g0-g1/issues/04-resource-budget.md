# 04 Ngân sách tài nguyên home lab cho G0–G1

Type: task
Status: resolved
Blocked by: 01, 02, 03
Map: [Kiến trúc G0–G1](../map.md)

## Question

Với các lựa chọn hạ tầng đã chốt (Kafka, PostgreSQL, Keycloak, LGTM, Argo CD, Sealed Secrets...) và 6 service + shopee-sim + frontend của G1 (mỗi service tối thiểu 2 replica theo `zero-downtime.md`), tổng RAM/CPU có vừa cụm 3 node (~8–9 GB cho service theo [homelab](../../../../platform/docs/homelab-hyperv.md)) không? Nếu không vừa thì cắt ở đâu (replica, LGTM rút gọn, Kafka 1 broker ở môi trường nào) và ghi lệch chuẩn nào.

AFK: agent tự cộng từ yêu cầu tài nguyên trong tài liệu chính thức và các file `docs/standards/`.

## Answer

Chốt 2026-11-12 (người dùng): **máy giữ 32 GB. Mặc định mọi service và database chạy 1 instance, giữ số lượng thành phần hạ tầng, giảm cỡ từng thành phần** → [ADR-0004](../../../adr/0004-single-instance-by-default-on-homelab.md). Số mặc định của từng thành phần, đọc ở manifest/chart đúng tag, nằm ở [tra cứu 11/2026](../../../research/2026-11-resource-budget.md). Hầu hết thành phần **không đặt** `resources`, nên mọi con số dưới đây là ước lượng **[SL, chưa đo]** và là limit memory ta tự đặt (memory request = limit theo `helm-chart.md`).

**Vì sao phải cắt:** theo đúng cỡ trong `docs/standards/` và 2 replica, tổng khoảng 34 GiB, trong khi 3 node có 24 GiB (3 × 8 GiB). Riêng hạ tầng đã khoảng 22,7 GiB. Bảng homelab cũ (~8–9 GB cho service) sai ở ba chỗ: thiếu Keycloak, LGTM, Argo CD, Apicurio, cert-manager và các operator; tính thừa Redis (G3) và OpenSearch (G6), vốn không thuộc G0–G1.

**Ngân sách G0–G1 đã chốt (MiB):**

| Nhóm | Thành phần (limit memory) | MiB |
|---|---|---|
| Node | OS, kubelet, containerd: 3 × 800 (eviction 100Mi/node tính riêng bên dưới) | 2 400 |
| Cụm | apiserver 700, etcd 300, controller-manager 150, scheduler 60; CoreDNS 2 × 170; kube-proxy 3 × 40; Calico (node 3 × 160, typha 2 × 80, kube-controllers 64, tigera-operator 128, apiserver 128; **tắt Goldmane/Whisker**); MetalLB 64 + 3 × 64; metrics-server 200; local-path 32 | 3 118 |
| GitOps, bảo mật | Argo CD: application-controller 512, repo-server 256, server 128, redis 64, applicationset 64 (**tắt Dex**, đăng nhập thẳng bằng OIDC của Keycloak; **tắt notifications**). Sealed Secrets 64; cert-manager 3 × 64; Drain Cleaner 64 | 1 344 |
| Kafka | **3 broker × 1 024** (heap `-Xms/-Xmx` 512m); Strimzi cluster operator 384; Entity Operator topic 256 + user 256 (**phải đặt limit**, vì không có limit thì heap tính theo RAM node) | 3 968 |
| Schema Registry | Apicurio: operator 128, app 512, UI 256 (tắt nếu `spec.ui` cho phép, **chưa xác minh**) | 896 |
| PostgreSQL | `pg-main` **1 instance** 1 024 + sidecar Barman 128; CNPG operator 200; plugin Barman 64; Pooler **1 pod** 64 | 1 480 |
| Keycloak | **1 instance** 1 536 (theo `keycloak.md`); operator 450 | 1 986 |
| LGTM | Prometheus 1 024 (`auto-gomemlimit` cần limit); Alertmanager 128; prometheus-operator 128; kube-state-metrics 128; node-exporter 3 × 48; Grafana + sidecar 320; Loki monolithic 512 (**tắt chunks-cache và results-cache**, mặc định 9 830 Mi + 1 229 Mi, không vừa node); Tempo 512; OTel Collector DaemonSet 3 × 192 | 3 472 |
| **Hạ tầng** | | **18 664** |
| Ứng dụng G1 | 6 service × **1 replica × 512**; `shopee-sim` 512; frontend Next.js 256; surge 1 pod khi rollout 512; Job Flyway 256 | 4 608 |
| **Tổng** | | **23 272** |
| Còn dư | 24 576 − 23 272 − eviction 3 × 100 | **≈ 1 000** |

**Lệch chuẩn đã ghi** (sửa ở chỗ lệch, trỏ về ADR-0004):
- [zero-downtime.md](../../../standards/zero-downtime.md), [helm-chart.md](../../../standards/helm-chart.md): lab chạy 1 replica. Chart vẫn mặc định 2, values lab trong `gitops` đặt 1.
- [kafka.md](../../../standards/kafka.md): broker 1 Gi, heap 512m, tổng Kafka khoảng 3 GiB thay vì 4,5 GB.
- [observability.md](../../../standards/observability.md): ngân sách LGTM khoảng 3,4 GiB với các limit ở bảng trên.
- Ticket [03 PostgreSQL trên cụm home lab](03-postgres-on-cluster.md): `pg-main` chạy 1 instance thay vì 2. Chỉ dựng instance thứ hai khi làm thí nghiệm failover.
- [Homelab](../../../../platform/docs/homelab-hyperv.md): bảng RAM được thay bằng bảng này.

**CPU không phải ràng buộc.** Node có 16 vCPU. Request ước tính khoảng 8 core [SL].

**Kafka 1 broker ở môi trường nào:** không dùng trên cụm. Môi trường dev chạy trên Mac (nếu có) thì do ticket [13](13-dev-loop.md) quyết. Cụm lab không còn RAM để chạy thêm bản sao môi trường.

**Rủi ro lớn nhất:** JVM 512 Mi. Với 512 Mi, `MaxRAMPercentage=75` chỉ để lại khoảng 128 Mi non-heap, mà metaspace của một service Spring Boot có JPA và Kafka đã cỡ 100–150 Mi [SL]. Nhiều khả năng phải hạ xuống khoảng 50–60%. Spec G0 phải có bước đo RSS service "hello" và `kubectl top` toàn cụm sau 24 giờ. Thiếu quá 1 GiB thì xét lại ADR-0004 trước khi bắt đầu G1.

**Ngoài cụm:** VM `gw` (2 GB) giờ chạy thêm RustFS, cạnh registry và Tailscale. RAM của RustFS **chưa xác minh**, cần đo khi dựng G0.

## Comments

- 2026-11-12: Từ ticket 01: bảng RAM homelab thiếu Keycloak (~1,5 GB) và LGTM (~3–4,5 GB, ước lượng). Kafka 3 node dual-role (Strimzi 1.3.1). Mỗi service tối thiểu 2 replica (`zero-downtime.md`), memory limit = request (`helm-chart.md`).
- 2026-11-12: Từ ticket 03: thêm cert-manager, Pooler PgBouncer (2 pod), sidecar Barman Cloud, RustFS trên VM `gw` (ngoài cụm); PostgreSQL `pg-main` 2 instance với requests = limits. RAM của các thành phần này **chưa xác minh**.
- 2026-11-12: Từ ticket [12 Kiến trúc shopee-sim](12-shopee-sim.md#answer): `shopee-sim` 512 Mi đổi tên thành `marketplace-sim`. Ở G2 tiktok-sim chạy chung pod này, nên không tốn thêm RAM. Simulator dùng thêm một database `marketplace_sim` trên `pg-main`.
