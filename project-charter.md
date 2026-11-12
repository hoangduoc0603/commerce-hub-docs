# commerce-hub: Project Charter

- Phiên bản: 1.0
- Ngày: 2026-11-12
- Trạng thái: Đã chốt

## 1. Vì sao có dự án này

commerce-hub là dự án học để luyện xây dựng một hệ thống microservice ở chất lượng production: backend, frontend, event-driven, dữ liệu, container, Kubernetes, CI/CD, observability, vận hành.

Bài toán được chọn là **SaaS quản lý bán hàng đa sàn** (multi-channel OMS) cho nhà bán trên TikTok Shop và Shopee. Lý do chọn: bài toán này tự sinh ra gần như mọi tình huống khó mà một hệ thống ecommerce thật phải xử lý:

- bán vượt tồn khi nhiều kênh cùng bán một món hàng;
- webhook trùng, mất, sai thứ tự;
- token xoay vòng, dễ mất nếu hai tiến trình cùng làm mới;
- giới hạn gọi API của bên ngoài;
- quy trình nhiều bước bất đồng bộ cần bù khi lỗi;
- tải đột biến khi flash sale;
- cô lập giữa các khách hàng dùng chung hệ thống.

**Nguyên tắc phạm vi:** nghiệp vụ chỉ cần vừa đủ để sinh ra các tình huống kỹ thuật trên. Không thêm tính năng nghiệp vụ chỉ để giống sản phẩm thương mại.

## 2. Mục tiêu và tiêu chí thành công

| Mã | Mục tiêu | Đạt khi |
|---|---|---|
| G1 | Luồng chính P0 chạy end-to-end trên cụm home lab | Một nhà bán đăng ký, kết nối 1 shop Shopee-sim và 1 shop TikTok-sim, ghép hàng, khai báo tồn. Đơn ở shop này làm số tồn ở shop kia giảm. Đơn được xử lý tới khi tải được vận đơn |
| G2 | Đúng đắn dưới lỗi | Đạt N4 (không mất đơn khi mất 100% webhook) và N5 (Oversell đo được, nằm trong cửa sổ trễ) bằng kịch bản chaos của simulator |
| G3 | Chịu tải | Đạt N6 (flash sale 500 đơn/s trong 10 phút) với số đo độ trễ và Oversell được ghi lại |
| G4 | Vận hành được | Mỗi đơn truy được bằng một trace (N12). Có dashboard SLO và runbook cho các sự cố đã gặp |
| G5 | Học có bằng chứng | Mỗi giai đoạn trong lộ trình có một bản ghi trong `experiments/`: giả thuyết, cách đo, số đo, kết luận |

## 3. Phạm vi

**Trong phạm vi**
- Toàn bộ tính năng **P0** trong [SRS](requirements/srs.md), đặc tả chi tiết đến mức kiểm thử được.
- Simulator cho TikTok Shop và Shopee, tương thích API thật, có kèm phần điều khiển chaos và bộ đếm kiểm chứng.
- Hạ tầng: cụm Kubernetes home lab, GitOps, observability.

**Có trong danh sách, làm sau:** tính năng P1 và P2 trong SRS. Chỉ liệt kê, đặc tả khi tới lượt làm.

**Ngoài phạm vi**
- Kết nối với sàn thật. Adapter được viết theo API thật, nhưng chỉ chạy với simulator.
- Thanh toán thật, hóa đơn điện tử thật, nhà mạng gửi SMS.
- Chat đa kênh, AI viết mô tả, quảng cáo, POS bán tại quầy.
- Lazada và các sàn khác. Kiến trúc vẫn phải cho phép thêm sàn mới mà không sửa lõi (N13).

## 4. Ràng buộc

| Loại | Ràng buộc |
|---|---|
| Nhân lực | Một người làm, ngoài giờ |
| Hạ tầng | Một máy bàn (i9-10900, 32 GB RAM) chạy cụm kubeadm trên Hyper-V, truy cập qua Tailscale ([homelab](../platform/docs/homelab-hyperv.md)). Không dùng cloud trả phí |
| Công nghệ nền | Java 25, Spring Boot 4.1.x, Kafka 4.x, PostgreSQL 17+, Next.js + TypeScript (xem Phần C của [tài liệu kỹ thuật](requirements-and-techniques.md)) |
| Tổ chức mã nguồn | Polyrepo ([ADR-0001](adr/0001-polyrepo.md)) |
| Thị trường | Việt Nam: VND, tiếng Việt, múi giờ Asia/Ho_Chi_Minh. Dữ liệu lưu UTC và có trường tiền tệ |

## 5. Mô hình phát triển (SDLC)

**Lặp và tăng dần.** Yêu cầu được phân tích theo bề rộng một lần cho toàn hệ thống, nhưng chỉ đặc tả chi tiết phần P0. Mỗi increment đi đủ một vòng:

```
Yêu cầu (chi tiết phần sắp làm) → Thiết kế (ADR, contract) → Code → Test → Deploy (GitOps) → Vận hành, đo → Bản ghi thí nghiệm
```

| Phase | Đầu ra chính | Nơi lưu |
|---|---|---|
| 1. Lập kế hoạch | Charter này | `docs/project-charter.md` |
| 2. Yêu cầu | SRS, domain model, luồng người dùng, ma trận truy vết, glossary | `docs/requirements/`, `docs/GLOSSARY.md` |
| 3. Thiết kế | Kiến trúc (arc42 + C4), ADR, contract (Avro, AsyncAPI, OpenAPI) | `docs/architecture/`, `docs/adr/`, repo `contracts` |
| 4. Code | Repo service, simulator, frontend | `services/`, `simulators/`, `frontend/` |
| 5. Test | Unit, integration (Testcontainers), contract (Pact), e2e, tải (k6), chaos | Trong từng repo, `load-tests/` |
| 6. Deploy | Helm values, image tag, Argo CD Application | repo `gitops` |
| 7. Vận hành | Dashboard, SLO, runbook, postmortem | `docs/runbooks/`, `docs/experiments/` |

Increment bám theo lộ trình C18. P0 được giao qua giai đoạn 0 đến 4. Thứ tự cụ thể nằm trong [ma trận truy vết](requirements/traceability.md).

**Definition of Ready** cho một yêu cầu: có mã, có tiêu chí nghiệm thu, đã ghi các giả định chưa xác minh, đã biết service nào sở hữu nó.

**Definition of Done** cho một increment:
- Tiêu chí nghiệm thu có test tự động.
- Chạy trên cụm home lab qua GitOps.
- Có metric và trace cho luồng mới.
- Cập nhật ma trận truy vết.
- Ghi ADR nếu có quyết định khó đảo ngược.

## 6. Rủi ro

| Rủi ro | Ảnh hưởng | Cách giảm |
|---|---|---|
| Phạm vi phình to vì nghiệp vụ ecommerce rất rộng | Không bao giờ xong P0 | Chỉ làm P0. P1/P2 phải có lý do kỹ thuật mới được kéo lên |
| Simulator khác xa sàn thật | Học sai, adapter vô dụng | Simulator theo tài liệu chính thức (SIM-01). Chỗ chưa xác minh được thì ghi giả định và cho chỉnh bằng cấu hình |
| Tài liệu sàn thay đổi theo tháng | Thông tin trong SRS lỗi thời | Ghi ngày tra cứu, tra lại trước khi viết từng adapter |
| Một máy bàn không đủ tài nguyên khi chạy thử tải | Không đo được N6 | Đo ở quy mô nhỏ hơn và ghi rõ giới hạn. Có thể tách simulator và k6 sang máy khác |
| Làm hạ tầng quá lâu trước khi có tính năng | Mất động lực | Giai đoạn 0 kết thúc bằng một service "hello" có trace, không làm hạ tầng hoàn hảo trước |

## 7. Bên liên quan

| Vai trò | Người |
|---|---|
| Chủ dự án, kiến trúc sư, lập trình viên, vận hành | Chủ repo |
| Trợ lý phân tích, thiết kế, review | Claude |
