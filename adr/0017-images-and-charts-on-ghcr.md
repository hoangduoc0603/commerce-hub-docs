---
status: accepted
date: 2026-11-15
---

# ADR-0017: Image và chart OCI trên GHCR, CI không vào lab

Image của service và chart `app` được push lên **GitHub Container Registry** (`ghcr.io/<user>/…`) thay cho registry HTTP `10.20.0.5:5000` trên VM `gw`. CI dùng `GITHUB_TOKEN` với quyền `packages: write`, chạy trên GitHub-hosted runner và **không vào tailnet**. Cụm kéo image và chart thẳng từ ghcr.io, không cần pull secret vì package để public. Argo CD khai chart dạng OCI tới ghcr.io qua HTTPS, bỏ `insecureOCIForceHttp`. Registry trên `gw` tắt. Phần "push image lên `10.20.0.5:5000` qua `tailscale/github-action`" của [ADR-0006](0006-public-repos-on-personal-account.md) bị ADR này thay.

Bối cảnh: ngày 2026-11-15 chủ repo chốt lại trọng tâm học là backend, microservices, event-driven, còn hạ tầng chỉ làm tới mức đủ dùng ([Charter](../project-charter.md) mục 1, bản 1.1). Registry nội bộ kéo theo ba việc hạ tầng không phục vụ trọng tâm đó: Tailscale OIDC trong CI (G0-17), Argo CD đọc OCI qua HTTP, và điểm **chưa xác minh** "attestation với registry HTTP".

## Phương án đã cân nhắc

- **Giữ registry HTTP trên `gw`, CI vào qua Tailscale** (ADR-0006). Bị loại. ADR-0006 loại GHCR với ba lý do. Hai lý do không còn đúng: cụm vốn đã kéo image từ internet (ngày 2026-11-15 có 43 container lấy image từ quay.io, registry.k8s.io, docker.io, ghcr.io, public.ecr.aws), và package public thì không cần pull secret. Lý do còn lại, "đi ngược quyết định dùng registry nội bộ", chỉ là chính quyết định đang được xét lại.
- **Docker Hub.** Bị loại. Gói miễn phí giới hạn số lần kéo, và cần thêm tài khoản cùng token ngoài GitHub.
- **Registry trong cụm (Harbor, Zot).** Bị loại. Tốn RAM của cụm, mà ngân sách ADR-0004 chỉ còn dư khoảng 520 MiB. CI vẫn phải vào lab.

## Hệ quả

- Ticket G0-17 thu lại thành reusable workflow build và push lên GHCR. Tailscale trong CI chỉ còn cần cho e2e, mà e2e đã xếp sang Giai đoạn 7. ACL `tag:ci` không còn dùng.
- Image và chart công khai trên internet. Chấp nhận được vì code đã public (ADR-0006) và image không chứa secret.
- Cụm phụ thuộc ghcr.io: mất internet là không kéo được image mới. Pod đang chạy vẫn chạy bình thường.
- Attestation lưu cùng registry trên GHCR, nên `gh attestation verify` sau này chạy được (phần này đã xếp sang G7).
- ~~**Chưa xác minh**, chốt ở G0-17: package do workflow của repo public tạo ra có tự public không. Nếu không, bật public một lần cho mỗi package. Với chart, cũng cần kiểm package có nối được với repo `platform` không.~~ **Đã xác minh 2026-11-16** ở G0-17: image push bằng `GITHUB_TOKEN` từ workflow của `platform` tạo package Public, tự nối với repo `platform`, và node của cụm kéo được mà không có credential (chi tiết ở [ci-cd.md](../standards/ci-cd.md), mục "Image, SBOM, provenance"). Chart OCI push cùng cách nên dự kiến giống; ticket G0-21 kiểm lại với package chart đầu tiên.
- Xét lại khi: chuyển repo sang private (cần pull secret), hoặc cần chạy lab không có internet.
