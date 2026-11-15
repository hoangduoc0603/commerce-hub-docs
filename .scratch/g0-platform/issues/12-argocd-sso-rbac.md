# 12: Argo CD đăng nhập SSO, RBAC tối thiểu

Status: ready-for-human
Hoãn tới: G7 (quyết định 2026-11-15, spec G0 mục "Sửa phạm vi 2026-11-15")
Lý do: SSO và RBAC cho công cụ vận hành là hạ tầng sâu; G0 vẫn dùng tài khoản `admin` cục bộ của Argo CD, và token cho `e2e` cũng theo ticket 31 sang G7.
Blocked by: 11
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

Argo CD đăng nhập bằng OIDC của Keycloak qua client `argocd`, sau đó tắt tài khoản `admin`. Quyền mặc định là `role:readonly`; sync, override, exec chỉ cho group admin. Có thêm project role chỉ đọc trong `commerce` với token có hạn cho repo `e2e` (ngoại lệ đã chốt ở ticket 19 của map, ghi lý do vào chuẩn). CI của `gitops` validate `policy.csv`. Theo mục "RBAC và truy cập" của [gitops-argocd.md](../../../standards/gitops-argocd.md).

## Mục tiêu học

- SSO bằng OIDC cho công cụ vận hành, và RBAC theo group thay cho user cục bộ.

## Tiêu chí nghiệm thu

- [ ] Đăng nhập `https://argocd.lab.internal` bằng Keycloak, quay về đúng `url`; `admin.enabled: false`.
- [ ] `argocd admin settings rbac can role:readonly sync applications 'commerce/*'` trả `No`; `validate` chạy trong CI của `gitops` và không lỗi.
- [ ] `applicationsets` create/update/delete chỉ admin.
- [ ] Token project role chỉ đọc có `--expires-in`, chạy được `argocd app get` nhưng `sync` bị từ chối.
- [ ] [gitops-argocd.md](../../../standards/gitops-argocd.md) ghi ngoại lệ token cho `e2e`.
