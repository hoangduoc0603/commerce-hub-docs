# 24: Deploy `hello` qua GitOps tới `hello.lab.internal`

Status: ready-for-human
Blocked by: 06, 22, 23
Repos: services/hello, platform, gitops, docs
Spec: [G0](../spec.md)

## Mô tả

Tracer bullet của G0: merge vào nhánh mặc định của `hello` thì job `update-gitops` (token GitHub App, ở G0 chỉ cài trên `gitops`; `e2e` thêm khi làm ticket 31 ở G7) sửa digest và tag trong values lab của `hello`. `ApplicationSet` sinh app trong project `commerce`, chart `app` kéo từ GHCR (đổi nguồn `10.20.0.5:5000/charts` của ticket 03, thêm GHCR vào `sourceRepos` của `commerce`, không dùng `insecureOCIForceHttp`; [ADR-0017](../../../adr/0017-images-and-charts-on-ghcr.md)), namespace `hello` do app `platform` tạo kèm nhãn cho phép route. `hello` mở qua `https://hello.lab.internal` (ngoại lệ chỉ có ở G0). Values lab: 1 replica, 512Mi, `MaxRAMPercentage=60`. Theo mục "Deploy qua GitOps" của [ci-cd.md](../../../standards/ci-cd.md), "Cập nhật image" của [gitops-argocd.md](../../../standards/gitops-argocd.md).

## Mục tiêu học

- Đẩy image qua GitOps: CI chỉ commit vào `gitops`, không giữ quyền vào cụm.

## Tiêu chí nghiệm thu

- [ ] Merge một thay đổi trong `hello` → commit mới trong `gitops` có tên service, SHA nguồn, link run → app `Synced/Healthy` → `curl https://hello.lab.internal/...` trả bản mới.
- [ ] Merge ba thay đổi gần nhau: ba commit `gitops` tuần tự, không job lỗi (`concurrency` và vòng `pull --rebase`).
- [ ] CI không có token Argo CD, không gọi `kubectl`.
- [ ] Rollback bằng `git revert` commit image; đo số giây tới `Healthy` ở bản cũ.
- [ ] Đo lead time: merge → image trên GHCR → commit `gitops` → `Healthy`.
- [ ] [cluster-entry.md](../../../standards/cluster-entry.md) thêm hostname `hello.` kèm ghi chú chỉ ở G0.
