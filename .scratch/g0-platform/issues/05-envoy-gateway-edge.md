# 05: Gateway `edge` với Envoy Gateway

Status: ready-for-human
Blocked by: 03
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

App `platform` cài CRD Gateway API v1.6.1 standard và Envoy Gateway v1.10.0, tạo `GatewayClass`, `EnvoyProxy` (1 replica, limit đặt tay) và Gateway `edge` trong namespace `edge` trên IP `10.20.0.200`. Ticket này chỉ có listener HTTP; HTTPS làm ở ticket 06. Một app thử trong namespace có nhãn cho phép gắn `HTTPRoute` và mở được từ Mac. Theo [ADR-0013](../../../adr/0013-gateway-api-envoy-gateway-shared-edge.md) và [cluster-entry.md](../../../standards/cluster-entry.md).

## Mục tiêu học

- Gateway API: tách vai trò `GatewayClass`, `Gateway`, `HTTPRoute`, và `allowedRoutes` theo nhãn namespace.

## Tiêu chí nghiệm thu

- [ ] CRD có annotation `bundle-version: v1.6.1`, `channel: standard`; chart `gateway-helm` `v1.10.0`; app dùng `ServerSideApply=true`.
- [ ] Service của Envoy có `EXTERNAL-IP` `10.20.0.200`.
- [ ] Gateway `edge` có `Accepted` và `Programmed` là `True`.
- [ ] `curl http://whoami.lab.internal` từ Mac tới được app thử qua `edge`.
- [ ] `HTTPRoute` trong namespace không có nhãn không được `Accepted` (`NotAllowedByListeners`).
- [ ] Health check Lua cho `Gateway` và `HTTPRoute` đọc `status.conditions`.
