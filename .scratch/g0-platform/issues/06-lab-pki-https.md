# 06: PKI của lab và HTTPS trên `edge`

Status: ready-for-human
Blocked by: 04, 05
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

cert-manager (bật Gateway API) ký chứng chỉ wildcard `*.lab.internal` từ `ClusterIssuer lab-ca`, mà khóa intermediate của nó vào cụm dưới dạng `SealedSecret`. Gateway `edge` có listener HTTPS và route chuyển HTTP sang HTTPS. Argo CD mở được qua `https://argocd.lab.internal`. Thứ tự sync wave: CRD Gateway API → cert-manager → Gateway `edge`, `lab-ca`. Theo [ADR-0014](../../../adr/0014-lab-pki-and-dns.md), [cluster-entry.md](../../../standards/cluster-entry.md) và mục "App `platform`" của [gitops-argocd.md](../../../standards/gitops-argocd.md).

## Mục tiêu học

- Chuỗi tin cậy root → intermediate → leaf, và name constraints chặn gì.
- cert-manager cấp chứng chỉ cho Gateway.

## Tiêu chí nghiệm thu

- [ ] `curl -sI http://app.lab.internal` trả `301` sang `https://`.
- [ ] Safari, Chrome và `curl -v` mở `https://argocd.lab.internal` không cảnh báo; chuỗi là wildcard ← intermediate ← root.
- [ ] Thử name constraints: chứng chỉ `evil.example.com` ký từ `lab-ca` bị Chrome, Safari, `curl` từ chối (JVM, Node kiểm ở ticket 07); client nào chấp nhận thì ghi vào lệch chuẩn.
- [ ] Bootstrap lại từ cụm trắng: cert-manager không cần restart tay để thấy Gateway.
- [ ] Argo CD: `server.insecure`, `url: https://argocd.lab.internal`; CLI dùng `--grpc-web`.

## Chuyển từ G0-05

- Gateway `edge` hiện có một listener `http` với `from: Selector` (tạm, cho app thử). Ticket này đổi nó sang `from: Same` + HTTPRoute redirect trong namespace `edge`, và thêm listener `https` mang selector nhãn `edge.lab.internal/routes: "true"`.
- App `edge` ở wave 5; `ClusterIssuer lab-ca` đặt cùng wave, cert-manager ở wave 3 (đã để trống).
- Route hỏng trong app `edge` sẽ làm app `Degraded`, ghim sync của root vào revision cũ tới khi hết retry (khoảng 5 phút ở G0-05). Cần áp ngay commit sửa thì `argocd app terminate-op root-lab` rồi sync lại.
