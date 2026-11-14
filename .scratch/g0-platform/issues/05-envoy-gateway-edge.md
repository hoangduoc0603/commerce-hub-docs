# 05: Gateway `edge` với Envoy Gateway

Status: resolved
Blocked by: 03
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

App `platform` cài CRD Gateway API v1.6.1 standard và Envoy Gateway v1.10.0, tạo `GatewayClass`, `EnvoyProxy` (1 replica, limit đặt tay) và Gateway `edge` trong namespace `edge` trên IP `10.20.0.200`. Ticket này chỉ có listener HTTP; HTTPS làm ở ticket 06. Một app thử trong namespace có nhãn cho phép gắn `HTTPRoute` và mở được từ Mac. Theo [ADR-0013](../../../adr/0013-gateway-api-envoy-gateway-shared-edge.md) và [cluster-entry.md](../../../standards/cluster-entry.md).

## Mục tiêu học

- Gateway API: tách vai trò `GatewayClass`, `Gateway`, `HTTPRoute`, và `allowedRoutes` theo nhãn namespace.

## Tiêu chí nghiệm thu

- [x] CRD có annotation `bundle-version: v1.6.1`, `channel: standard`; chart `gateway-helm` `v1.10.0`; app dùng `ServerSideApply=true`.
- [x] Service của Envoy có `EXTERNAL-IP` `10.20.0.200`.
- [x] Gateway `edge` có `Accepted` và `Programmed` là `True`.
- [x] `curl http://whoami.lab.internal` từ Mac tới được app thử qua `edge`.
- [x] `HTTPRoute` trong namespace không có nhãn không được `Accepted` (`NotAllowedByListeners`).
- [x] Health check Lua cho `Gateway` và `HTTPRoute` đọc `status.conditions`. (Dùng check có sẵn của Argo CD v3.6.1, xem bước 7.)

## Lộ trình

Duyệt ngày 2026-11-14. Chủ repo giao Claude làm cả ticket. Hiện trạng lúc lập: `root-lab`, `argocd`, `sealed-secrets` `Synced/Healthy`; `whoami.lab.internal` từ Mac đã ra `10.20.0.200` (dnsmasq, G0-02); pool MetalLB `lab-pool` `10.20.0.200-10.20.0.250`; Calico có CRD `gatewayapis.operator.tigera.io` nhưng không có CR nào, nên operator Calico không cài CRD Gateway API.

Phát hiện khi lập (tra 2026-11-14 trên chart `oci://docker.io/envoyproxy/gateway-helm:v1.10.0` và `gateway-crds-helm:v1.10.0`, Argo CD CLI v3.6.1):

- `gateway-helm` `crds.enabled=false` tắt cả CRD của Envoy Gateway (`EnvoyProxy`, `ClientTrafficPolicy`…), không chỉ CRD Gateway API (subchart `crds` gộp cả hai cùng `ValidatingAdmissionPolicy` "safe upgrade"). CRD của Envoy Gateway lấy từ `gateway-crds-helm` với chỉ `crds.envoyGateway.enabled=true`.
- `EnvoyProxy` v1.10.0 có `envoyDeployment.{replicas, container, pod, patch, strategy}` và `envoyService.annotations`; không có field cho resources của `shutdown-manager`, phải dùng `envoyDeployment.patch`.
- Argo CD v3.6.1 có sẵn health check cho `gateway.networking.k8s.io/Gateway` và `HTTPRoute` (thử offline bằng `argocd admin settings resource-overrides health`: `Accepted=False` → `Degraded`; `Programmed=False` → `Progressing`; chưa có status → `Progressing`; route `ResolvedRefs=False` → `Degraded`).

Quyết định khi duyệt: CRD Gateway API vendor từ release upstream (không lấy phần Gateway API của `gateway-crds-helm`), vì CRD độc lập với implementation và cert-manager (G0-06) cũng cần; wave 2 (CRD) / 4 (Envoy Gateway, để wave 3 cho cert-manager) / 5 (`edge`) / 6 (sandbox); gỡ `whoami` khi kết ticket.

- [x] 1. App `gateway-api-crds`1. App `gateway-api-crds` (wave 2): vendor `standard-install.yaml` v1.6.1 vào `infra/gateway-api-crds/`, patch `Prune=false,Delete=false`, `ServerSideApply=true`. Kiểm: annotation `bundle-version: v1.6.1`, `channel: standard`; app `Synced/Healthy`.
  - Kết quả: `infra/gateway-api-crds/` (bản vendor sha256 `24d931f2…`, trùng byte với phần standard trong `gateway-crds-helm` v1.10.0; 10 CRD và VAP `safe-upgrades`) + patch cho mọi CRD. Push → `Synced/Healthy` sau **22 s**. Đổi annotation `channel` sang `experimental` (dry-run server) bị VAP từ chối.
- [x] 2. App `envoy-gateway`2. App `envoy-gateway` (wave 4): `gateway-crds-helm` chỉ CRD Envoy Gateway + `gateway-helm` `crds.enabled=false`, controller 256/256 Mi, image ghim digest + Namespace `envoy-gateway-system` (Pod Security). Kiểm: `helm template` chart chính ra 0 CRD; CRD `envoyproxies` có trên cụm; controller `Ready`; RAM.
  - Kết quả: push → `Synced/Healthy` sau **40 s**; 8 CRD `gateway.envoyproxy.io`; controller ghim digest `c2243d43…`, 256/256 Mi, `GOMEMLIMIT` 230MiB. Phát hiện: `null` trong `valuesObject` (để bỏ `ttlSecondsAfterFinished` 30 của Job `certgen`) bị mất khi lưu Application, Job vẫn bị xóa sau 30 s; sửa bằng `helm.parameters` `value: "null"`. Đổi chỉ hook thì app vẫn `Synced`, auto-sync không chạy; phải `argocd app sync` tay để thử. Sau review: CRD Envoy Gateway chuyển sang vendor trong `infra/envoy-gateway/` có `Prune=false,Delete=false` (chuyển source không xóa CRD, `EnvoyProxy` giữ nguyên), Job `certgen` có resources 64Mi.
- [x] 3. App `edge`3. App `edge` (wave 5): `GatewayClass envoy` + `EnvoyProxy` (1 replica, Envoy 128 Mi, shutdown-manager 32 Mi qua `patch`, `metallb.io/loadBalancerIPs: 10.20.0.200`). Kiểm: `GatewayClass` `Accepted=True`; chưa có pod Envoy.
  - Kết quả: push → `GatewayClass envoy` `Accepted=True` sau **16 s**, chưa có pod Envoy nào. Tên field `EnvoyProxy` khớp CRD v1.10.0; shutdown-manager đặt resources qua `envoyDeployment.patch`, sau review thêm `GOMEMLIMIT` 28MiB.
- [x] 4. Namespace `edge`4. Namespace `edge` + Gateway `edge`, listener `http` (80, `*.lab.internal`, `from: Selector` nhãn `edge.lab.internal/routes: "true"`; G0-06 đổi sang `Same` + redirect và thêm `https`). Kiểm: `Accepted`/`Programmed` `True`; `EXTERNAL-IP` `10.20.0.200`; resources hai container; `curl -i http://whoami.lab.internal` → 404 của Envoy.
  - Kết quả: push → Gateway `Accepted`, `Programmed` sau **16 s**; Service `envoy-edge-edge-…` `EXTERNAL-IP` `10.20.0.200`; Envoy 128/128 Mi, shutdown-manager 32/32 Mi; pod qua Pod Security `restricted`; `curl -i http://whoami.lab.internal` → `404` từ Envoy.
- [x] 5. App thử `sandbox-whoami`5. App thử `sandbox-whoami` (wave 6): namespace có nhãn, Deployment non-root, Service, `HTTPRoute`. Kiểm: `curl http://whoami.lab.internal` trả tên pod; route `Accepted`, `ResolvedRefs`.
  - Kết quả: `traefik/whoami:v1.12.0` (digest), non-root, cổng 8080. Push → `200` sau **21 s**, trả tên pod; route `Accepted`, `ResolvedRefs`; `attachedRoutes` 1; hostname khác → `404`. `X-Forwarded-For: 10.20.0.5` (IP của `gw`, đúng lệch chuẩn "IP nguồn mất ở `gw`").
- [x] 6. Cùng `HTTPRoute`6. Cùng `HTTPRoute` ở namespace không nhãn. Kiểm: `Accepted=False`, `NotAllowedByListeners`.
  - Kết quả: namespace `stray` không nhãn, route `hijack` khai trùng `whoami.lab.internal`: `Accepted=False` `NotAllowedByListeners` sau 16 s; 5/5 request vẫn tới pod whoami thật; app `sandbox-stray` `Degraded`.
- [x] 7. Health Argo CD7. Health Argo CD: đọc Lua có sẵn ở tag v3.6.1, quyết định giữ hay tự viết; làm hỏng `backendRef`. Kiểm: app `Degraded` kèm message của route.
  - Kết quả: Argo CD v3.6.1 có sẵn Lua cho `GatewayClass`, `Gateway`, `HTTPRoute` (đọc ở tag v3.6.1). Quyết định: dùng check có sẵn, không viết Lua riêng (upstream bảo trì, đã xét `observedGeneration` cho route). `backendRef` sai → `ResolvedRefs=False`, app `Degraded` sau **2 s**, Envoy trả 500. `parentRef` sai tên → Envoy Gateway để nguyên status cũ, app chỉ `Progressing` (ghi vào chuẩn, chuyển G0-22 kiểm bằng schema). Revert → `200` sau 3 s.
- [x] 8. Kết ticket8. Kết ticket: gỡ sandbox, RAM, sửa chuẩn, số đo vào `docs/experiments/`, `code-review`, Bài học.
  - Kết quả: gỡ sandbox qua Git. Phát hiện: `sandbox-stray` `Degraded` ở wave 6 làm sync của root fail và retry 5 lần trên revision cũ, nên commit gỡ chỉ được áp sau khoảng **5 phút**. Còn 6 app `Synced/Healthy`. RAM lúc rảnh: controller 56/256 Mi, Envoy 21/128 Mi, shutdown-manager 23/32 Mi. Số đo: [bản ghi G0, mục 4](../../../experiments/2026-11-g0.md#4-envoy-gateway-và-gateway-edge-cài-chặn-namespace-health-ram). Sửa chuẩn `cluster-entry.md`, `gitops-argocd.md`. Review: xem mục Review.

## Kết quả

- Bằng chứng: [bản ghi G0, mục 4](../../../experiments/2026-11-g0.md#4-envoy-gateway-và-gateway-edge-cài-chặn-namespace-health-ram) và các dòng G0-05 trong [bằng chứng cửa vào cụm](../../../experiments/2026-11-cluster-entry.md).
- Commit trong `gitops` từ `e63747e` tới `0ef3660`: app `gateway-api-crds` (wave 2), `envoy-gateway` (wave 4), `edge` (wave 5); `infra/gateway-api-crds/`, `infra/envoy-gateway/`, `infra/edge/`; `sourceRepos` của `platform` thêm `docker.io/envoyproxy`; blacklist của `commerce` thêm `EnvoyExtensionPolicy`, `EnvoyPatchPolicy`, `Backend`. Sandbox đã gỡ khỏi Git và khỏi cụm.
- Tài liệu: chuẩn [cluster-entry.md](../../../standards/cluster-entry.md) (bẫy `crds.enabled`, field `EnvoyProxy`, health có sẵn, lỗ hổng hostname, hook không được theo dõi), [gitops-argocd.md](../../../standards/gitops-argocd.md) (health Gateway API, app `Degraded` ghim root, `null` trong `valuesObject`, hook không được diff).
- Ma trận truy vết: không có dòng tương ứng (ticket hạ tầng, giống G0-03, G0-04).
- Chuyển cho ticket sau:
  - G0-06: listener `http` đổi sang `from: Same` + route redirect, thêm listener `https`; khi thêm route của Argo CD vào app `edge`, nhớ rằng route hỏng sẽ ghim sync của root (có thể `argocd app terminate-op root-lab`).
  - G0-22: ràng buộc hostname theo namespace (review điểm 1); schema kiểm `httpRoute.parentRef` (review điểm 7).
  - G0-33: Envoy 128 Mi không có overload manager; xem có OOMKilled dưới k6 không (review điểm 9). Rollout Envoy khi đổi `EnvoyProxy` (1 replica) chưa đo số request lỗi.
  - G0-34: RAM shutdown-manager (23/32 Mi lúc rảnh) và controller sau 24 giờ.

## Review

`code-review` (high) trên `gitops` `1764860..6b59d69` ra 9 điểm. Claude sửa 4 (commit `0ef3660`, chủ repo giao cả ticket), chuyển hoặc chấp nhận 5:

1. **Namespace có nhãn vẫn chiếm được hostname của nhau** (`allowedRoutes` không ràng buộc hostname). Chuyển G0-22, ghi vào chuẩn là chưa giải.
2. **`commerce` tạo được `EnvoyExtensionPolicy`** (Wasm, ext_proc chạy trong Envoy dùng chung). Sửa: blacklist thêm `EnvoyExtensionPolicy`, `EnvoyPatchPolicy`, `Backend`.
3. **CRD Envoy Gateway không có `Prune=false,Delete=false`.** Sửa: vendor bằng `helm template` vào `infra/envoy-gateway/` kèm patch.
4. **App `Degraded` ghim sync của root vào revision cũ.** Chấp nhận, ghi vào `gitops-argocd.md` cùng cách gỡ (`terminate-op`).
5. **Hook Helm (webhook, RBAC `certgen`) không được Argo CD theo dõi.** Chấp nhận (đường cài chính thức), ghi lệch chuẩn và cách dọn tay.
6. **shutdown-manager sát trần, không có `GOMEMLIMIT`.** Sửa: `GOMEMLIMIT` 28MiB qua `patch`.
7. **`parentRef` sai tên chỉ `Progressing`.** Chuyển G0-22 (schema).
8. **Job `certgen` BestEffort.** Sửa: resources 64Mi.
9. **Envoy 128 Mi không có overload manager.** Chuyển G0-33 (đo dưới tải trước khi cấu hình).

## Bài học

- Đọc chart trước khi tin docs: một value tên `crds.enabled` tắt hai nhóm CRD khác nhau. `helm template … | grep -c CustomResourceDefinition` trước khi viết Application là phép kiểm rẻ nhất để thấy điều đó.
- Mỗi lớp trung gian có thể làm mất ý định: `null` trong `valuesObject` hợp lệ với Helm nhưng biến mất khi API server lưu Application. Kiểm kết quả trên cụm (Job có bị xóa sau 30 s không), không chỉ kiểm bản render.
- `allowedRoutes` trả lời câu hỏi "namespace nào được gắn", không trả lời câu hỏi "ai sở hữu hostname nào". Mục tiêu "app lạ không chiếm được hostname" cần cả hai, và review mới chỉ ra phần thứ hai.
- Health chặt có giá: một route hỏng ở wave cuối ghim sync của root vào revision cũ khoảng 5 phút, kể cả khi commit sửa đã push.
- Câu chuyện kể được: "Cửa vào cụm là Gateway API với Envoy Gateway, dựng hoàn toàn qua GitOps theo wave CRD → controller → Gateway trong khoảng 1 phút rưỡi. Tôi thử một namespace lạ khai trùng hostname: Gateway từ chối với `NotAllowedByListeners`, traffic vẫn tới app thật. Review chỉ ra rằng giữa các namespace hợp lệ thì vẫn chiếm được hostname của nhau, nên tôi đưa ràng buộc hostname theo namespace vào thiết kế chart."
