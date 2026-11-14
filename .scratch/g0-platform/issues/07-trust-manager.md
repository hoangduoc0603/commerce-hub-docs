# 07: trust-manager phân phối CA cho pod

Status: ready-for-human
Blocked by: 06
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

trust-manager v0.26.0 sinh `Bundle` `lab-trust` gồm root của lab, ra cả PEM lẫn truststore PKCS12. Một pod JVM tạm và một pod Node tạm mount bundle đó, gọi được `https://argocd.lab.internal` mà không sửa code và không tắt kiểm TLS. Đây là cơ chế chart `app` sẽ dùng ở ticket 22. Theo mục "Phân phối trust" của [cluster-entry.md](../../../standards/cluster-entry.md).

## Mục tiêu học

- Cách JVM (`javax.net.ssl.trustStore`) và Node (`NODE_EXTRA_CA_CERTS`) quyết định tin CA nào.

## Tiêu chí nghiệm thu

- [ ] Pod JVM tạm có mount truststore gọi `https://argocd.lab.internal` thành công; bỏ mount thì lỗi `PKIX`.
- [ ] Pod Node tạm với `NODE_EXTRA_CA_CERTS` gọi thành công, không đặt `NODE_TLS_REJECT_UNAUTHORIZED`.
- [ ] Hairpin: pod trên node không có Envoy gọi `https://*.lab.internal` thành công.
- [ ] JVM và Node từ chối chứng chỉ `evil.example.com` của ticket 06; kết quả ghi vào [cluster-entry.md](../../../standards/cluster-entry.md).
