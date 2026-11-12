# Chuẩn: Triển khai không gián đoạn (zero-downtime)

- Ngày tra: 2026-11-12
- Phiên bản áp dụng: Kubernetes 1.37 (kube-proxy, Calico, MetalLB), Spring Boot 4.1.2, Spring for Apache Kafka 4.1.2, Apache Kafka 4.x, k6 v2.3.0
- Phạm vi: Deployment của mọi service Spring Boot (render từ chart [`spring-service`](helm-chart.md)), cấu hình `application.yaml` phần shutdown/probe, và thí nghiệm chứng minh yêu cầu **N15** (SRS: deploy, kể cả migration DB, không mất webhook và không lỗi request). Liên quan: **N16** (kill pod không làm sai sổ cái, không mất/nhân đôi Reservation)

## Checklist

### Rolling update
- [ ] `replicas >= 2` cho mọi service nhận traffic (HTTP hoặc webhook). Một replica thì lúc thay pod không còn ai phục vụ.
- [ ] `strategy.rollingUpdate.maxSurge: 1`, `maxUnavailable: 0`. Pod cũ chỉ bị tắt khi pod mới đã available, nên số pod phục vụ không bao giờ giảm. [Kubernetes – Deployments: Max Unavailable, Max Surge](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#max-unavailable)
- [ ] `minReadySeconds: 10`. Pod mới phải Ready liên tục 10 s mới được tính là available, chặn trường hợp pod Ready rồi crash ngay. [Kubernetes – Deployments: Min Ready Seconds](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#min-ready-seconds)
- [ ] Giữ `progressDeadlineSeconds` (mặc định 600) lớn hơn `minReadySeconds`; CI hoặc Argo CD theo dõi `kubectl rollout status`. Rollout kẹt được báo `ProgressDeadlineExceeded` thay vì treo im lặng. [Kubernetes – Deployments: Progress Deadline Seconds](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/#progress-deadline-seconds)

### Probe và nhóm health của Actuator
- [ ] Actuator chạy ở cổng quản trị riêng (`management.server.port: 8081`, không mở qua Ingress) và `management.endpoint.health.probes.add-additional-paths: true`, để probe gọi `/livez` và `/readyz` trên **cổng chính 8080**. Probe ở cổng quản trị có thể pass trong khi cổng chính không nhận kết nối. [Spring Boot – Kubernetes Probes](https://docs.spring.io/spring-boot/reference/actuator/endpoints.html#actuator.endpoints.kubernetes-probes)
- [ ] `readinessProbe` → `/readyz` (`periodSeconds: 5`, `failureThreshold: 2`, `timeoutSeconds: 2`). Readiness chỉ lên `ACCEPTING_TRAFFIC` khi startup xong, nên pod mới không nhận request quá sớm. [Spring Boot – Application lifecycle and probe states](https://docs.spring.io/spring-boot/reference/actuator/endpoints.html#actuator.endpoints.kubernetes-probes.lifecycle)
- [ ] `livenessProbe` → `/livez` (`periodSeconds: 10`, `failureThreshold: 3`, `timeoutSeconds: 2`) và **không** đưa DB, Kafka hay API ngoài vào nhóm liveness. Một hệ thống ngoài hỏng sẽ làm Kubernetes khởi động lại mọi instance cùng lúc. [Spring Boot – Checking external state with Kubernetes probes](https://docs.spring.io/spring-boot/reference/actuator/endpoints.html#actuator.endpoints.kubernetes-probes.external-state)
- [ ] Nhóm readiness mặc định cũng không chứa hệ thống dùng chung; chỉ thêm (qua `management.endpoint.health.group.readiness.include`) khi chấp nhận mọi pod rời khỏi Service khi hệ thống đó sập, và ghi lý do. [Spring Boot – Kubernetes Probes](https://docs.spring.io/spring-boot/reference/actuator/endpoints.html#actuator.endpoints.kubernetes-probes.external-state)
- [ ] `startupProbe` → `/livez`, `periodSeconds: 5`, `failureThreshold: 24` (tối đa 120 s). Liveness chỉ bắt đầu sau khi startup probe pass, nên khởi động chậm trên VM lab không bị kill. Đặt `failureThreshold × periodSeconds` phủ thời gian khởi động xấu nhất đã đo. [Kubernetes – Configure startup probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-startup-probes)

### Graceful shutdown
- [ ] Không tắt graceful shutdown: `server.shutdown` mặc định là `graceful` ở Spring Boot 4.1. Khi dừng, Tomcat ngừng nhận request mới ở tầng mạng và cho request đang chạy hoàn tất. [Spring Boot – Graceful shutdown](https://docs.spring.io/spring-boot/reference/web/graceful-shutdown.html), [Application properties](https://docs.spring.io/spring-boot/appendix/application-properties/index.html)
- [ ] `spring.lifecycle.timeout-per-shutdown-phase: 20s` (mặc định 30 s), lớn hơn request chậm nhất đã đo (p99.9) và lớn hơn `shutdownTimeout` của Kafka listener. Thời gian chờ này áp cho **mỗi** phase `SmartLifecycle`, không phải tổng. [Application properties](https://docs.spring.io/spring-boot/appendix/application-properties/index.html)
- [ ] Ứng dụng là PID 1 (`ENTRYPOINT` dạng exec) để nhận SIGTERM. [Docker – Best practices: ENTRYPOINT](https://docs.docker.com/build/building/best-practices/#entrypoint), xem [`container-image.md`](container-image.md)

### preStop và gỡ endpoint
- [ ] `lifecycle.preStop.sleep.seconds: 10` (handler `sleep` có sẵn, GA từ Kubernetes 1.34, không cần shell trong image). Khi xóa pod, việc gỡ endpoint khỏi EndpointSlice chạy **song song** với preStop/SIGTERM; kube-proxy, Calico và Ingress controller cần thời gian để cập nhật. Nếu không chờ, request vẫn được định tuyến tới pod đã đóng cổng. [Kubernetes – Pod termination](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination), [Spring Boot – Kubernetes container lifecycle](https://docs.spring.io/spring-boot/how-to/deployment/cloud.html#howto.deployment.cloud.kubernetes.container-lifecycle), [Kubernetes – Feature gates (PodLifecycleSleepAction)](https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/)
- [ ] Đo lại độ trễ gỡ endpoint trên cụm lab (mục Bằng chứng); nếu 10 s chưa đủ thì tăng, không đoán. Spring Boot chỉ đưa 10 s làm ví dụ và ghi giá trị đúng tùy hệ thống. [Spring Boot – Kubernetes container lifecycle](https://docs.spring.io/spring-boot/how-to/deployment/cloud.html#howto.deployment.cloud.kubernetes.container-lifecycle)
- [ ] `terminationGracePeriodSeconds: 60` ≥ preStop (10) + tổng các phase shutdown có việc thật (web 20 + Kafka listener 20) + dự phòng. Thời gian chờ được đếm **từ trước** preStop; hết hạn thì SIGKILL. [Kubernetes – Container lifecycle hooks](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/#hook-handler-execution), [Spring Boot – Kubernetes container lifecycle](https://docs.spring.io/spring-boot/how-to/deployment/cloud.html#howto.deployment.cloud.kubernetes.container-lifecycle)
- [ ] Kiểm hành vi với kết nối keep-alive: Service L4 (kube-proxy, MetalLB) cân bằng theo **kết nối**, nên kết nối cũ vẫn bám pod đang tắt. Spring Boot ghi rằng kết nối persistent có thể làm việc từ chối request mới diễn ra khác. Client nội bộ phải retry request idempotent khi kết nối bị đóng. [Spring Boot – Graceful shutdown](https://docs.spring.io/spring-boot/reference/web/graceful-shutdown.html)

### PodDisruptionBudget
- [ ] Có PDB `maxUnavailable: 1` cho service ≥ 2 replica (render bởi chart, xem [`helm-chart.md`](helm-chart.md)). PDB bảo vệ trước gián đoạn tự nguyện như `kubectl drain`, vốn dùng Eviction API. [Kubernetes – Disruptions](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/)
- [ ] Hiểu đúng phạm vi: rolling update của Deployment **không** bị PDB giới hạn; an toàn rollout đến từ `maxUnavailable: 0` của Deployment. Xóa pod trực tiếp cũng bỏ qua PDB. [Kubernetes – Disruptions: PDB](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/#pod-disruption-budgets)

### Consumer Kafka khi shutdown
- [ ] Giữ `stopImmediate: false` (mặc định): khi container listener dừng, nó xử lý hết số record của lần poll trước rồi mới dừng, sau đó commit offset (`ackMode: BATCH` mặc định, commit đồng bộ). [Spring for Apache Kafka – Listener container properties](https://docs.spring.io/spring-kafka/reference/kafka/container-props.html)
- [ ] `max.poll.records` × thời gian xử lý một record < `shutdownTimeout` (mặc định 10 s) < `timeout-per-shutdown-phase`. Nếu không, `stop()` hết thời gian chờ và record đã xử lý có thể chưa được commit. [Spring for Apache Kafka – Listener container properties](https://docs.spring.io/spring-kafka/reference/kafka/container-props.html)
- [ ] Consumer phải idempotent: rebalance khi pod rời và vào group, cùng việc commit không kịp, đều có thể giao lại record (at-least-once). Đây là điều kiện của N16 và BR-20. Thiết kế chi tiết ở [`kafka.md`](kafka.md).
- [ ] Chọn giao thức group (`group.protocol=consumer` của KIP-848, GA từ Kafka 4.0, hay `classic` mặc định của client) ở [`kafka.md`](kafka.md). Giao thức mới rebalance tăng dần nên rollout ít làm gián đoạn partition khác. [Apache Kafka – Consumer Rebalance Protocol](https://kafka.apache.org/41/operations/consumer-rebalance-protocol/)

### Schema DB khi rollout
- [ ] Trong lúc rollout, bản cũ và bản mới chạy song song trên cùng schema. Mọi migration phải tương thích ngược theo expand/contract; quy trình, công cụ và cách chạy migration nằm ở [`db-migration.md`](db-migration.md). N15 tính cả deploy có migration.

## Lựa chọn và phương án đã loại

| Quyết định | Chọn | Loại | Lý do | Nguồn |
|---|---|---|---|---|
| Chiến lược deploy | RollingUpdate, `maxSurge: 1`, `maxUnavailable: 0` | Mặc định 25%/25%; Recreate; blue-green/canary (Argo Rollouts) | Mặc định cho phép giảm pod phục vụ; Recreate có downtime. Blue-green tốn gấp đôi RAM, cụm lab không đủ | [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/) |
| Chờ gỡ endpoint | `preStop.sleep` | `preStop.exec: sleep`; chỉ dựa vào graceful shutdown | `exec` cần shell trong image; Spring Boot ghi không nên chỉ dựa vào graceful shutdown | [Spring Boot – Kubernetes container lifecycle](https://docs.spring.io/spring-boot/how-to/deployment/cloud.html#howto.deployment.cloud.kubernetes.container-lifecycle) |
| Cổng probe | `/livez`, `/readyz` trên cổng chính | `/actuator/health/*` trên cổng quản trị | Probe phải đi cùng hạ tầng web với traffic thật | [Spring Boot – Kubernetes Probes](https://docs.spring.io/spring-boot/reference/actuator/endpoints.html#actuator.endpoints.kubernetes-probes) |
| Nội dung liveness | Chỉ trạng thái nội bộ | Có DB/Kafka | Tránh khởi động lại dây chuyền | Như trên |
| Kafka khi dừng | `stopImmediate: false` + consumer idempotent | `stopImmediate: true` | Ít record bị giao lại hơn; idempotent vẫn bắt buộc | [Listener container properties](https://docs.spring.io/spring-kafka/reference/kafka/container-props.html) |

## Lệch chuẩn có chủ đích ở home lab

- **2 replica, 3 node**, control plane cũng nhận pod. Mất một node trong lúc rollout có thể chỉ còn 1 pod phục vụ; chấp nhận vì cụm lab chỉ còn khoảng 8–9 GB RAM cho service.
- **`maxSurge: 1`** làm rollout chậm khi có nhiều replica. Với 2 replica, khác biệt không đáng kể.
- **Đo tải ở quy mô nhỏ** (cùng máy bàn chạy cụm, k6 chạy từ Mac qua Tailscale). Đường mạng qua Tailscale thêm độ trễ, nên N15 chỉ chấm theo **số request lỗi**, không chấm theo latency trong thí nghiệm này. Giới hạn đã ghi ở rủi ro của Charter.

## Bằng chứng cần có

Ghi vào `docs/experiments/YYYY-MM-zero-downtime-<service>.md`: phiên bản image cũ/mới, cấu hình, lệnh, kết quả k6, và timeline.

**Kịch bản tải** (k6, `constant-arrival-rate` khoảng 50 req/s trong 5 phút, đi đúng đường production: Ingress hoặc Gateway trên IP MetalLB):

```js
export const options = {
  scenarios: { rollout: { executor: 'constant-arrival-rate', rate: 50, timeUnit: '1s',
                          duration: '5m', preAllocatedVUs: 50 } },
  thresholds: { http_req_failed: ['rate==0'], checks: ['rate==1'] },
};
```

k6 thoát với mã khác 0 khi threshold không đạt. [k6 – Thresholds](https://grafana.com/docs/k6/latest/using-k6/thresholds/)

| Tình huống (chạy trong lúc k6 đang chạy) | Lệnh | Tiêu chí đạt |
|---|---|---|
| Đổi image qua GitOps | Sửa digest trong `gitops/envs/<env>/<service>/values.yaml`, Argo CD sync; `kubectl rollout status deploy/<svc>` | `http_req_failed` = 0, `checks` = 100% |
| Restart không đổi image | `kubectl rollout restart deploy/<svc>` | Như trên |
| Drain node | `kubectl drain k8s-w1 --ignore-daemonsets --delete-emptydir-data`, rồi `kubectl uncordon k8s-w1` | Như trên; drain không bị chặn quá `progressDeadlineSeconds` |
| Deploy có migration DB | Theo [`db-migration.md`](db-migration.md) | Như trên |
| Webhook trong lúc deploy | Simulator gửi webhook liên tục trong cả 4 tình huống trên | Bộ đếm Simulator: 0 lần giao webhook thất bại, 0 webhook thiếu (N15) |
| Consumer Kafka | Đếm message vào/ra của topic liên quan trong lúc rollout | Không mất message; message giao lại không sinh hiệu ứng trùng (N16) |

Số đo phụ, để chỉnh giá trị thay vì đoán:

- **Độ trễ gỡ endpoint**: `kubectl get endpointslices -l kubernetes.io/service-name=<svc> -w -o wide` cùng lúc `kubectl delete pod <pod>`; ghi khoảng từ lúc xóa tới khi endpoint chuyển `ready=false`. preStop phải lớn hơn khoảng này cộng thời gian Ingress/kube-proxy cập nhật.
- **Thời gian shutdown thật**: khoảng cách giữa log bắt đầu và kết thúc graceful shutdown của Spring Boot; phải nhỏ hơn `terminationGracePeriodSeconds - preStop`. Không có pod nào kết thúc với exit code 137 (`kubectl get pod -o jsonpath='{..lastState.terminated.exitCode}'`).
- **Thời gian khởi động**: từ lúc pod được tạo tới Ready; dùng để chỉnh `startupProbe`.
- **Đối chứng âm**: chạy lại một lần với `preStop` bỏ đi và `maxUnavailable: 25%`; kỳ vọng thấy request lỗi. Không thấy lỗi thì tải chưa đủ để phát hiện vấn đề.

## Nguồn

- Kubernetes 1.37: [Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/), [Pod lifecycle – Termination](https://kubernetes.io/docs/concepts/workloads/pods/pod-lifecycle/#pod-termination), [Container lifecycle hooks](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/), [Feature gates](https://kubernetes.io/docs/reference/command-line-tools-reference/feature-gates/), [Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/), [Disruptions](https://kubernetes.io/docs/concepts/workloads/pods/disruptions/), [Configure PDB](https://kubernetes.io/docs/tasks/run-application/configure-pdb/)
- Spring Boot 4.1.2: [Kubernetes Probes và lifecycle](https://docs.spring.io/spring-boot/reference/actuator/endpoints.html#actuator.endpoints.kubernetes-probes), [Graceful shutdown](https://docs.spring.io/spring-boot/reference/web/graceful-shutdown.html), [Deploying to the cloud – Kubernetes](https://docs.spring.io/spring-boot/how-to/deployment/cloud.html), [Application properties](https://docs.spring.io/spring-boot/appendix/application-properties/index.html)
- [Spring for Apache Kafka 4.1.2 – Listener container properties](https://docs.spring.io/spring-kafka/reference/kafka/container-props.html)
- [Apache Kafka – Consumer Rebalance Protocol](https://kafka.apache.org/41/operations/consumer-rebalance-protocol/), [Kafka 4.0.0 release announcement](https://kafka.apache.org/blog/2025/03/18/apache-kafka-4.0.0-release-announcement/)
- [k6 – Thresholds](https://grafana.com/docs/k6/latest/using-k6/thresholds/), [k6 releases](https://github.com/grafana/k6/releases)
- [Docker – Build best practices](https://docs.docker.com/build/building/best-practices/)
