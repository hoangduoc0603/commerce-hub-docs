# 02: Kiểm nền cụm home lab và `gw`

Status: resolved
Blocked by: None (can start immediately)
Repos: platform, docs
Spec: [G0](../spec.md)

## Mô tả

Cụm kubeadm 1.37 và VM `gw` ở trạng thái mà mọi ticket sau dựa vào: ba node `Ready`, Calico, MetalLB, local-path, metrics-server, registry HTTP trên `gw`, Tailscale subnet router, dnsmasq phân giải `*.lab.internal` về `10.20.0.200`, root CA offline đã tạo và được tin trên Mac. Phần nào chưa dựng thì dựng theo [homelab](../../../../platform/docs/homelab-hyperv.md) mục 1–8; chỗ runbook sai thì sửa runbook.

## Mục tiêu học

- Kiểm một cụm kubeadm từ ngoài vào: mạng, LoadBalancer, storage, DNS.
- Root CA offline có name constraints và vì sao nó không nằm trong cụm ([ADR-0014](../../../adr/0014-lab-pki-and-dns.md)).

## Tiêu chí nghiệm thu

- [x] `kubectl get nodes` từ Mac (context `homelab`) có 3 node `Ready`, đúng bản 1.37; Calico không chạy Goldmane và Whisker.
- [x] Mục 8.5 của runbook pass: Service LoadBalancer nhận IP MetalLB, PVC local-path bound.
- [x] `dscacheutil -q host -a name x.lab.internal` trên Mac trả `10.20.0.200`; pod `busybox` cũng phân giải được (bảng bằng chứng của [cluster-entry.md](../../../standards/cluster-entry.md)).
- [x] `curl http://10.20.0.5:5000/v2/` từ Mac trả 200.
- [x] Root CA nằm ngoài cụm, có name constraints `lab.internal`, được tin trong Keychain hệ thống của Mac.
- [x] `kubectl top nodes` lúc cụm trống ghi vào bản ghi thí nghiệm G0 làm mốc.

## Lộ trình

Duyệt ngày 2026-11-14. Hiện trạng lúc lập: 3 node `v1.37.2` `Ready`, MetalLB, local-path, metrics-server đã cài, registry trả 200; Goldmane và Whisker đang chạy; chưa có dnsmasq, split DNS, server block CoreDNS, root CA, `docs/experiments/`.

- [x] 1. Tắt Goldmane, Whisker (xóa CR); sửa runbook 7.3 để không tạo hai CR này. Kiểm: `kubectl get tigerastatus` và `kubectl get pods -n calico-system` không còn `goldmane`, `whisker`.
- [x] 2. Chạy mục 8.5: Service LoadBalancer và PVC. Kiểm: `curl http://<EXTERNAL-IP>` từ Mac ra trang nginx; PVC `Bound`.
- [x] 3. dnsmasq trên `gw` (8.7.1). Kiểm: `dig @10.20.0.5 x.lab.internal +short` = `10.20.0.200`; `example.com` không có IP; `/etc/resolv.conf` của `gw` không đổi.
- [x] 4. Split DNS Tailscale (8.7.2). Kiểm: `dscacheutil -q host -a name x.lab.internal` = `10.20.0.200`.
- [x] 5. Server block `lab.internal` trong CoreDNS (8.7.3). Kiểm: `nslookup auth.lab.internal` từ pod `busybox:stable` = `10.20.0.200`.
- [x] 6. Script `openssl` tạo root CA trong `platform`, `.gitignore` chặn khóa. Kiểm: `Name Constraints: critical` đủ `lab.internal`, `svc`, `svc.cluster.local`; leaf `evil.example.com` ký thử bị `openssl verify` từ chối.
- [x] 7. Tin root trên Mac (System Keychain). Kiểm: `security find-certificate` thấy root; `security verify-cert -c lab-root-ca.crt` pass.
- [x] 8. Đo mốc cụm trống vào `docs/experiments/` (`kubectl top nodes`, `kubectl top pods -A`, `free -m` trên `gw`, các dòng DNS của bảng bằng chứng cluster-entry). Kiểm: file có số và ngày đo.

## Kết quả

- Bằng chứng: [bản ghi G0, mục 1](../../../experiments/2026-11-g0.md) (mốc RAM cụm trống 5 406 MiB working set / 5 518 MiB dự kiến) và [bằng chứng cluster-entry](../../../experiments/2026-11-cluster-entry.md) (DNS từ Mac, DNS từ pod, root CA, name constraints với OpenSSL).
- Ma trận truy vết: không có dòng tương ứng. Ticket là hạ tầng, không gắn mã F/N riêng; N12 "0 (khung)" thuộc ticket `hello` có trace.
- Runbook `platform/docs/homelab-hyperv.md` sửa ở 7.3 (bỏ Goldmane/Whisker), 7.5 (dàn lại CoreDNS), 8.7.1 (`local=`, thứ tự cài), 8.7.2 (cách macOS chia DNS, cache âm), 8.7.3 (patch không tương tác, số đo reload), 8.8 (script root CA, cấm IP). Chuẩn `cluster-entry.md` sửa ở checklist dnsmasq và root CA.
- Chuyển cho ticket sau: `systemReserved` của kubelet và nhóm Node khoảng 1 100 MiB/node (ticket 34); kiểm Avast trước khi lấy bằng chứng trình duyệt (ticket 06); ghim image helper của local-path (khi đưa local-path vào GitOps).

## Bài học

- Kiểm cụm từ ngoài vào theo từng tầng (L2/ARP của MetalLB, DNS qua ba resolver khác nhau, trust store) cho thấy mỗi tầng có cách "trông như chạy" riêng: `scutil --dns` không có `lab.internal` vẫn đúng vì Tailscale chia DNS ở quad-100; `dscacheutil` sai vì cache âm 30 giờ. Kiểm bằng đúng công cụ của tầng đó, và nghi cache trước khi nghi cấu hình.
- Chỉnh operator bằng CR, không bằng thứ operator sinh ra: xóa CR `Goldmane` làm operator tự gỡ biến môi trường của Felix và rolling restart `calico-node`. Docs Calico không ghi cách tắt; quan sát `generation` và log là cách chứng minh.
- Name constraints chỉ ràng buộc loại tên được liệt kê, nên root phải cấm riêng IP SAN. Test có đối chứng âm mới tin được: lần đầu cả bộ test "đỏ giả" vì `pipefail` lấy mã thoát của `openssl verify`.
- Câu chuyện kể được: "Ngân sách RAM của lab là ước lượng. Đo cụm trống thì tổng đạt (5,4/5,5 GiB) nhưng nhóm OS vượt 40 % nếu tính working set, và kubelet không đặt `systemReserved`, nên scheduler sẽ xếp quá RAM thật khi chart đặt request = limit. Số đo này đổi ngân sách trước khi thêm Kafka và Keycloak."
