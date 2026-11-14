# 27: `hello` dùng `pg-main` với migration `PreSync`

Status: ready-for-human
Blocked by: 08, 24, 26
Repos: platform, gitops, services/hello, docs
Spec: [G0](../spec.md)

## Mô tả

Chart `app` có Job migrate là hook `PreSync` của Argo CD (`BeforeHookCreation`, không `ttlSecondsAfterFinished`, tắt được bằng values), chạy chính image của service với profile `migrate`. Trên lab, Job nối thẳng `pg-main-rw` bằng role `hello_migrator`; runtime nối qua Pooler bằng `hello_app`; credential là `SealedSecret`. Migration lỗi thì sync dừng, Deployment giữ bản cũ. Theo mục "Chạy migration ở đâu" của [db-migration.md](../../../standards/db-migration.md), "Sync waves, hooks" của [gitops-argocd.md](../../../standards/gitops-argocd.md).

## Mục tiêu học

- Migration như một bước của deploy (`PreSync`): thứ tự, idempotent, và cách nó chặn bản lỗi.

## Tiêu chí nghiệm thu

- [ ] Tạo lời chào qua `https://hello.lab.internal` rồi đọc lại được sau khi pod restart.
- [ ] Đẩy migration lỗi cố ý: Job `Failed`, Deployment giữ bản cũ, app báo sync lỗi; revert thì xanh lại.
- [ ] Giữ khóa bảng trong một transaction rồi sync: Job lỗi `lock timeout` trong khoảng 5 s, thử lại thành công sau khi nhả khóa.
- [ ] `\dt+`, `\dp`: bảng thuộc `hello_owner`, `hello_app` có đúng quyền DML.
- [ ] `SELECT indexrelid::regclass FROM pg_index WHERE NOT indisvalid` trả 0 hàng.
