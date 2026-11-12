# 04 Ngân sách tài nguyên home lab cho G0–G1

Type: task
Status: open
Blocked by: 01, 02, 03
Map: [Kiến trúc G0–G1](../map.md)

## Question

Với các lựa chọn hạ tầng đã chốt (Kafka, PostgreSQL, Keycloak, LGTM, Argo CD, Sealed Secrets...) và 6 service + shopee-sim + frontend của G1 (mỗi service tối thiểu 2 replica theo `zero-downtime.md`), tổng RAM/CPU có vừa cụm 3 node (~8–9 GB cho service theo [homelab](../../../../platform/docs/homelab-hyperv.md)) không? Nếu không vừa thì cắt ở đâu (replica, LGTM rút gọn, Kafka 1 broker ở môi trường nào) và ghi lệch chuẩn nào.

AFK: agent tự cộng từ yêu cầu tài nguyên trong tài liệu chính thức và các file `docs/standards/`.

## Comments

- 2026-11-12: Từ ticket 01: bảng RAM homelab thiếu Keycloak (~1,5 GB) và LGTM (~3–4,5 GB, ước lượng). Kafka 3 node dual-role (Strimzi 1.3.1). Mỗi service tối thiểu 2 replica (`zero-downtime.md`), memory limit = request (`helm-chart.md`).
- 2026-11-12: Từ ticket 03: thêm cert-manager, Pooler PgBouncer (2 pod), sidecar Barman Cloud, RustFS trên VM `gw` (ngoài cụm); PostgreSQL `pg-main` 2 instance với requests = limits. RAM của các thành phần này **chưa xác minh**.
