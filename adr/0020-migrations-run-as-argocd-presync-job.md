---
status: accepted
date: 2026-11-25
---

# ADR-0020: Migration DB chạy bằng Job hook `PreSync` của Argo CD, dùng chính image của bản sắp deploy

Mỗi service có DB chạy Flyway trong một Job là hook `PreSync` của Argo CD. Job chạy đúng image (cùng digest) của bản sắp deploy, ở profile `migrate`: nối thẳng primary `pg-main-rw` bằng role `<svc>_migrator`, `SET ROLE <svc>_owner`, `lock_timeout` 5 s, migrate xong thì JVM thoát. Job lỗi thì Argo CD dừng sync: Deployment, ConfigMap của bản mới không được áp, pod cũ vẫn phục vụ. Pod runtime không bao giờ migrate (`spring.flyway.enabled=false`) và chỉ cầm credential `<svc>_app` (DML) đi qua PgBouncer `transaction`. Chart `app` 0.3.0 (sửa ở 0.3.1) cung cấp Job này qua `migration.*`, credential của migrator là SealedSecret hook `PreSync` wave `-1` (`HookSucceeded`), chỉ tồn tại trong lúc sync. Đã chứng minh trên lab ở [G0-27](../.scratch/g0-platform/issues/27-hello-pg-main-presync.md) ([bản ghi](../experiments/2026-11-g0-27-hello-presync.md)).

## Phương án đã cân nhắc

- **Migrate lúc app khởi động** (mặc định của Spring Boot). Loại: pod runtime phải giữ quyền DDL; migration dài làm startupProbe giết pod; mọi replica cùng thử; bản mới đã chạy khi migration còn dở.
- **initContainer.** Loại: vẫn chạy theo từng pod, mỗi lần pod khởi động lại, và pod runtime vẫn mang credential migrate.
- **Job thường ở sync wave âm.** Loại: Job là bất biến, đổi image phải xóa rồi tạo lại; hook được Argo CD tạo lại ở mỗi lần sync.
- **Bước migrate trong CI trước khi ghi `gitops`.** Loại: CI phải có đường vào DB của cụm, trái nguyên tắc CI không cầm credential vào cụm ([ci-cd.md](../standards/ci-cd.md), mục "Deploy qua GitOps").

## Hệ quả

- Hook chạy ở **mọi** lần sync, kể cả sync tay và self-heal, nên migration phải idempotent (Flyway không có version chờ thì `up to date`, exit 0; đo ở G0-27: Job 4–5 s).
- Hook không nằm trong diff: commit chỉ đổi Job hay secret hook (ví dụ bật `migration.enabled`) không kích auto-sync; revert về đúng trạng thái đang chạy cũng không. Lúc đó phải sync tay. Migration mới luôn đi kèm image mới (digest đổi) nên deploy thường không gặp chuyện này.
- Migration lỗi: Job thử lại `backoffLimit` 2, Argo CD retry sync 5 lần, tổng 18 pod trong khoảng 10 phút rồi app báo sync `Failed`. Rollback là `git revert` commit image trong `gitops`; migration chưa áp thành công ở môi trường nào thì được xóa khỏi repo service dù `migration-guard` đỏ (quyết định Q2 của G0-27, [db-migration.md](../standards/db-migration.md)).
- Mọi thứ Job cần phải có trước phase Sync: secret của migrator là hook PreSync wave `-1`; ServiceAccount dùng `default` (SA do chart tạo chưa có ở lần sync đầu, review G0-27, chart 0.3.1).
- Gắn với Argo CD: `helm install` tay không chạy hook theo thứ tự. Compose trên Mac (G0-32) phải tự chạy profile `migrate` trước runtime.
- Mỗi bản deploy có thêm một pod JVM ngắn (khoảng 1 s chạy, memory bằng runtime) nằm cùng lúc với pod cũ; tính vào ngân sách RAM của [ADR-0004](0004-single-instance-by-default-on-homelab.md).
