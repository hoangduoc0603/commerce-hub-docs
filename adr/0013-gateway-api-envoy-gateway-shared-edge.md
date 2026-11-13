---
status: accepted
date: 2026-11-13
---

# ADR-0013: Cửa vào cụm là Gateway API với Envoy Gateway, một Gateway `edge` dùng chung

Traffic từ trình duyệt vào cụm đi qua **Gateway API** (CRD standard channel v1.6.1), hiện thực bằng **Envoy Gateway v1.10.0**. App `platform` trong repo `gitops` sở hữu CRD, Envoy Gateway, `GatewayClass envoy`, `EnvoyProxy` và một Gateway tên **`edge`** ở namespace `edge`, có listener HTTPS wildcard `*.lab.internal` và redirect HTTP sang HTTPS. Chart `app` chỉ sinh `HTTPRoute` (nhiều hostname được) gắn vào `edge`. Namespace muốn gắn route phải có nhãn do `platform` gắn (`allowedRoutes.namespaces.from: Selector`); không dùng `ReferenceGrant`. Ở lab Envoy chạy 1 replica, limit đặt tay: controller 256 Mi, Envoy 128 Mi, shutdown-manager 32 Mi. Tên `edge` để không nhầm với service `gateway` (Spring Cloud Gateway); request đi trình duyệt → `edge` → `seller-web` → `gateway` → service. Chi tiết và nguồn ở [tra cứu 11/2026](../research/2026-11-cluster-entry.md) và [cluster-entry.md](../standards/cluster-entry.md) (ticket [16](../.scratch/architecture-g0-g1/issues/16-cluster-entry.md)).

## Phương án đã cân nhắc

- **Ingress với `ingress-nginx`.** Bị loại vì từ K8s 1.37 Ingress API đã đóng băng, `ingress-nginx` không còn bản vá từ 03/2026, và Ingress không có cách chuẩn cho re-encrypt tới backend, timeout, retry.
- **Implementation khác của Gateway API.** Istio (istiod cần 2 Gi), NGINX Gateway Fabric 2.8 và Traefik 3.7 (thiếu timeout, retry, kiểm SAN), kgateway 2.5 (không cam kết K8s 1.37), Cilium (CNI của lab là Calico).
- **Mỗi app tự tạo Gateway hoặc ListenerSet.** Bị loại vì chứng chỉ và cổng rải khắp nơi, mỗi Gateway thêm một pod Envoy.

## Hệ quả

- Biên RAM của lab ([ADR-0004](0004-single-instance-by-default-on-homelab.md)) giảm khoảng 480 MiB (gồm trust-manager của [ADR-0014](0014-lab-pki-and-dns.md)), còn khoảng 520 MiB. Phải đo ở G0.
- Envoy Gateway có chu kỳ hỗ trợ ngắn: v1.10 hết hỗ trợ ngày 05/05/2027. Nâng bản là việc định kỳ, và mỗi lần nâng K8s phải kiểm lại ma trận tương thích.
- Envoy mặc định nối thêm vào `X-Forwarded-For`. Phải cấu hình số hop tin cậy và có test giả mạo header cho Keycloak ([keycloak.md](../standards/keycloak.md)).
- Đổi sang implementation khác chỉ chạm app `platform`; route của app giữ nguyên vì là API chuẩn.
