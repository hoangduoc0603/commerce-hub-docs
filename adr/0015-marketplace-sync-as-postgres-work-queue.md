---
status: accepted
date: 2026-11-13
---

# ADR-0015: Đồng bộ với sàn bằng hàng đợi việc theo Shop trong PostgreSQL

`channel-connector` chạy mọi việc định kỳ với sàn (poll đơn F5.2b, kéo dữ liệu ban đầu và kéo bù F2.4a, kéo Listing F3.2a, làm mới token F2.2a) qua **một hàng đợi việc nằm trong PostgreSQL**. Bảng `sync_cursor` có một dòng cho mỗi (Shop, loại việc). G1 có ba loại `ORDER`, `LISTING`, `TOKEN`. Mỗi dòng có `checkpoint`, `next_run_at`, `lease_owner`, `lease_until`.

- Mỗi instance định kỳ gọi một hàm `SECURITY DEFINER` của role `channel_connector_lookup` (ví dụ `claim_due_syncs(n)`). Hàm lấy các dòng đã tới hạn của Shop `Active` bằng `FOR UPDATE SKIP LOCKED`, đặt lease, **commit ngay**, và chỉ trả về ID (`workspace_id`, `shop_id`, loại).
- Instance làm từng việc trong context Workspace của việc đó ([ADR-0010](0010-workspace-isolation-shared-schema-with-mandatory-rls.md)). Nó không giữ transaction trong lúc gọi sàn, và chạy song song có giới hạn (số việc tối đa mỗi instance cấu hình được).
- Xong một đơn vị việc thì ghi checkpoint, với điều kiện `lease_owner` vẫn là mình và lease chưa hết hạn, rồi đặt `next_run_at = now + chu kỳ + jitter`. TTL của lease dài hơn thời gian tối đa của một đơn vị việc, nên không có gia hạn lease.
- Checkpoint là `time_to` của cửa sổ đã xong, theo đồng hồ của connector. Checkpoint chỉ dời sau khi mọi trang của cửa sổ đã gửi Kafka và có ack ([ADR-0005](0005-kafka-from-g1-with-deliberate-dual-write.md)). Cửa sổ dài hơn một đoạn (mặc định 1 ngày, luôn ≤ 15 ngày của Shopee) thì cắt nhỏ, mỗi đoạn là một đơn vị việc.
- Làm mới token là loại việc riêng (`TOKEN`, tới hạn trước khi access token hết hạn 30 phút). Việc poll không bao giờ tự gọi refresh.

Bối cảnh và các câu hỏi đã chốt nằm ở ticket [17 channel-connector ở G1](../.scratch/architecture-g0-g1/issues/17-connector-g1.md#answer).

## Phương án đã cân nhắc

- **ShedLock, một vòng lặp cho cả cụm.** Đơn giản nhất. Bị loại vì mọi Shop gọi sàn dồn vào cùng một mốc 5 phút, một instance gánh hết, thêm instance không chia được việc, và pod chết giữa vòng thì phần còn lại của vòng phải đợi lần chạy sau. Vòng lặp vẫn cần một hàm `_lookup` để liệt kê Shop, nên cũng không đỡ được phần RLS.
- **Gán chủ cho từng Shop theo partition Kafka** (hướng "owner theo shop" ở C5.3). Bị loại ở G1 vì cần topic điều khiển và xử lý rebalance. Đây là ứng viên khi làm single-flight đầy đủ ở G3.
- **Checkpoint là `update_time` lớn nhất đã thấy.** Bị loại vì `update_time` của TikTok có thể vượt khoảng tìm kiếm (SIM-08), làm checkpoint nhảy qua những đơn chưa quét.
- **Dời checkpoint theo trang.** Bị loại vì chưa xác minh được danh sách đơn có sắp theo `update_time` hay không.
- **Mỗi việc poll tự làm mới token khi thấy sắp hết hạn.** Bị loại vì lease đặt theo (Shop, loại việc): việc `ORDER` và việc `LISTING` của cùng một Shop chạy song song có thể cùng refresh, và refresh token Shopee xoay vòng nên lần thứ hai làm Shop mất kết nối (BR-10).

## Hệ quả

- Hàm `claim_due_syncs` **ghi** cột lease ngoài context Workspace, nên role `_lookup` có quyền `UPDATE` trên `sync_cursor`. Đây là mở rộng có chủ đích của ADR-0010 (vốn chỉ nói hàm `_lookup` trả ID hoặc số đếm). Hàm chỉ chạm cột lease và vẫn chỉ trả ID.
- Mất lease mà vẫn lỡ gửi event thì vô hại: event mang trạng thái đầy đủ kèm version, bên nhận có version guard ([ADR-0009](0009-deterministic-ids-for-marketplace-entities.md), [ADR-0007](0007-stock-balance-plus-ledger-in-one-transaction.md)).
- Mỗi (Shop, loại việc) chỉ chiếm một chỗ trong pool. Shop đang kéo bù 30 ngày không làm đói Shop khác, dù G1 chưa có hàng đợi ưu tiên.
- Lịch các Shop tự rải ra theo thời điểm xong việc cộng jitter, không dồn đợt.
- BR-10 ở G1 dựa vào lease. Lease hết hạn giữa lúc refresh (GC pause dài hơn TTL) vẫn có thể sinh hai lần refresh. Fencing và thí nghiệm "tái hiện lỗi trước khi sửa" của F2.2a để G3.
- Bảng `sync_cursor` bị cập nhật liên tục (mỗi Shop vài lần mỗi 5 phút), nên cần theo dõi bloat và autovacuum khi lên 5.000 Shop (SIM-03).
- Xét lại khi: G3 thêm lệnh đẩy tồn và Redis, hoặc số đo cho thấy hàm claim là nút thắt.
