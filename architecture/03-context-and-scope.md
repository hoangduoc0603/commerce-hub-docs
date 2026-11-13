# 3. Bối cảnh và phạm vi

## 3.1 Bối cảnh nghiệp vụ (C4 Context)

```mermaid
flowchart TB
    seller["<b>Owner / Member</b><br/>[Người]<br/>Nhà bán và nhân viên. Quản lý Shop,<br/>Master SKU, tồn kho, đơn trên trình duyệt"]
    admin["<b>Platform Admin</b><br/>[Người]<br/>Đội vận hành commerce-hub.<br/>G1 chưa có giao diện"]

    hub["<b>commerce-hub</b><br/>[Hệ thống phần mềm]<br/>Gom Listing và Order từ mọi Shop,<br/>giữ một nguồn tồn kho chung,<br/>cô lập dữ liệu theo Workspace"]

    shopee["<b>Shopee</b><br/>[Hệ thống ngoài]<br/>Open API v2, OAuth.<br/>Thay bằng marketplace-sim"]
    tiktok["<b>TikTok Shop</b><br/>[Hệ thống ngoài, từ G2]<br/>Thay bằng marketplace-sim"]
    mail["<b>Hộp thư</b><br/>[Hệ thống ngoài]<br/>Mailpit nhận mọi email"]

    seller -- "Đăng ký, đăng nhập, xem đơn và tồn<br/>[HTTPS]" --> hub
    seller -- "Ủy quyền Shop trên trang của sàn<br/>[HTTPS, trình duyệt]" --> shopee
    admin -. "Lệnh quản trị (phát lại Mapping, Member)<br/>[từ trong cụm, G1]" .-> hub
    hub -- "Kéo Listing và đơn, đổi mã lấy token<br/>[HTTPS, ký HMAC]" --> shopee
    hub -. "G2" .-> tiktok
    hub -- "Email xác minh, đặt lại mật khẩu<br/>[SMTP]" --> mail

    classDef person fill:#08427b,stroke:#052e56,color:#fff
    classDef system fill:#1168bd,stroke:#0b4884,color:#fff
    classDef external fill:#999,stroke:#6b6b6b,color:#fff
    class seller,admin person
    class hub system
    class shopee,tiktok,mail external
```

| Đối tác | Trao đổi gì ở G1 | Ghi chú |
|---|---|---|
| Owner / Member | Đăng ký, xác minh email, đăng nhập (F1.1a–b); tạo, chuyển Workspace (F1.1c); kết nối Shop (F2.1a); Master SKU, ghép Listing, khai báo tồn (F3, F4.1b); xem đơn (F5.1a) | G1 chỉ có Owner qua giao diện. Member với Role khác tạo bằng fixture của test; lời mời ở G2 (ticket [05](../.scratch/architecture-g0-g1/issues/05-identity-model.md#answer)) |
| Platform Admin | Phát lại Mapping của một Workspace (catalog), phát lại Member (workspace) | G1 chỉ khai báo realm role `platform-admin` và client `admin-web`, chưa dựng ứng dụng admin. Đọc dữ liệu chéo Workspace (PA-*) nằm ngoài đích của map |
| Shopee (giả lập) | OAuth (SIM-04), làm mới token (SIM-05), ký request (SIM-06), kéo Listing (`get_item_list`, `get_model_list`), kéo đơn (SIM-08) | Sàn là nguồn sự thật của Listing và đơn. Webhook (SIM-14) và đẩy tồn (SIM-10..12) từ G2 |
| TikTok Shop (giả lập) | Chưa có | G2 thêm dialect trong cùng pod `marketplace-sim` |
| Hộp thư | Keycloak gửi email xác minh và đặt lại mật khẩu | Hàng đợi email có retry (C3) sang G2 cùng `notification` |

Ngoài phạm vi G1: hãng vận chuyển (carrier-sim, G4), webhook từ sàn (G2), người mua ảo và bộ sinh đơn (SIM-18, G2). Ở G1 đơn được tạo và chuyển trạng thái bằng admin API của simulator.

## 3.2 Bối cảnh kỹ thuật

Mọi người dùng vào lab qua Tailscale ([homelab](../../platform/docs/homelab-hyperv.md)). Từ ngoài cụm chỉ tới được ba nhóm hostname sau ([ADR-0011](../adr/0011-nextjs-bff-with-server-side-session.md), ticket [12](../.scratch/architecture-g0-g1/issues/12-shopee-sim.md#answer)). Gateway API hay Ingress, implementation nào và TLS do [ticket 16](../.scratch/architecture-g0-g1/issues/16-cluster-entry.md) chốt.

| Kênh | Từ → tới | Giao thức, định dạng |
|---|---|---|
| `app.<domain-lab>` | Trình duyệt → `seller-web` | HTTPS. Trang Next.js và `/api/*` cùng origin. Cookie `__Host-session` (`HttpOnly; Secure; SameSite=Lax`) |
| `auth.<domain-lab>` | Trình duyệt → Keycloak | HTTPS, OIDC: đăng nhập, đăng ký (`prompt=create`), link xác minh email, đặt lại mật khẩu. Chỉ mở `/realms/`, `/resources/`, `/.well-known/` ([keycloak.md](../standards/keycloak.md)) |
| `shopee-sim.<domain-lab>` | Trình duyệt → `marketplace-sim` (trang ủy quyền); `channel-connector` → `marketplace-sim` (API) | HTTPS. Shopee Open API v2 dưới `/api/v2/...`, ký HMAC kèm `timestamp`, lệch quá 5 phút thì bị từ chối (SIM-06). Connector dùng hostname này làm base URL vì Shopee phục vụ trang ủy quyền cùng host với API |
| Callback OAuth | Trang ủy quyền của sàn → `app.<domain-lab>` → gateway → `channel-connector` | HTTPS. Workspace lấy từ `state` và phiên |
| SMTP | Keycloak → Mailpit | SMTP |

Từ G2 thêm `tiktok-sim.<domain-lab>` (cùng Service của `marketplace-sim`) và một hostname cho `webhook-ingress`.

Hạ tầng phát triển và vận hành (không thuộc runtime của sản phẩm): GitHub (code, Actions, Packages), registry image trên `gw` (`10.20.0.5:5000`), RustFS trên `gw` (backup PostgreSQL), MacBook dev chạy `platform/compose` ([mục 8.12](08-crosscutting-concepts.md#812-vòng-phát-triển-và-test)).
