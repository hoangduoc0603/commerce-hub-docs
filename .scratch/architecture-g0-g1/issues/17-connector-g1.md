# 17 channel-connector ở G1: polling đơn và mã hóa token sàn

Type: grilling
Status: resolved
Blocked by:
Map: [Kiến trúc G0–G1](../map.md)

## Question

Hai phần của `channel-connector` mà G1 cần nhưng chưa ticket nào chốt (lộ ra ở ticket [14](14-arc42-c4.md)):

- **Polling đơn F5.2b** (N4, SIM-08): job chạy đơn instance (ShedLock?) hay chia theo Shop; lịch chạy và cửa sổ chồng lấn; checkpoint lưu ở đâu và theo khóa nào (Shop × loại dữ liệu). Thứ tự đã chốt ở ticket [08](08-g1-communication.md#answer): gửi, chờ ack, rồi mới dời checkpoint. Kéo dữ liệu ban đầu F2.4a ở G1 dùng chung cơ chế này hay riêng.
- **Mã hóa token sàn khi lưu** (N11, BR-10): khóa nằm ở đâu (Sealed Secret, KMS không có ở lab), mã hóa theo trường hay theo hàng, xoay khóa thế nào. `seller-web` đã có mẫu AES-GCM kèm `key_id` ở [ADR-0011](../../../adr/0011-nextjs-bff-with-server-side-session.md); dùng lại mẫu đó hay khác.

## Answer

Chốt 2026-11-13 (người dùng), sau hai vòng grilling (Q1–Q8). Hai ADR: [ADR-0015](../../../adr/0015-marketplace-sync-as-postgres-work-queue.md) (hàng đợi việc đồng bộ) và [ADR-0016](../../../adr/0016-marketplace-token-encryption-with-tink.md) (mã hóa token).

### Polling và kéo dữ liệu

1. **Hàng đợi việc theo Shop trong Postgres** (Q1). Bảng `sync_cursor` có một dòng cho mỗi (Shop, loại việc): `ORDER`, `LISTING`, `TOKEN`. Instance nhận việc qua hàm `_lookup` `claim_due_syncs(n)` (`FOR UPDATE SKIP LOCKED`, đặt lease, commit ngay, chỉ trả ID), rồi làm việc trong context Workspace. Không giữ transaction trong lúc gọi sàn. Mỗi instance chạy song song có giới hạn (ví dụ 16, cấu hình được). TTL của lease dài hơn một đơn vị việc, nên không có gia hạn. Checkpoint chỉ được ghi khi instance còn giữ lease. Chu kỳ `ORDER` là 5 phút (F5.2b), thêm jitter. Loại bỏ ShedLock và chia theo partition Kafka, lý do ở ADR-0015.
2. **Checkpoint** (Q2):
   - Checkpoint là `time_to` của cửa sổ đã xong, theo đồng hồ của connector. Cửa sổ kế tiếp bắt đầu từ `checkpoint − 10 phút`.
   - Checkpoint dời sau khi mọi trang của cửa sổ đã gửi và có ack (`acks=all`, ticket 08), không dời theo trang.
   - Cửa sổ dài thì cắt thành đoạn, mặc định 1 ngày, cấu hình được, phải ≤ 15 ngày. Mỗi đoạn là một đơn vị việc; đoạn xong thì checkpoint dời tới cuối đoạn.
   - Không dùng max(`update_time`), vì `update_time` của TikTok có thể vượt khoảng tìm kiếm (SIM-08).
3. **F2.4a bản G1 dùng chung cơ chế** (Q5):
   - **Order:** kết nối lần đầu thì đặt checkpoint `ORDER = now − 30 ngày`, rồi cơ chế ở mục 2 tự đuổi kịp từng đoạn. Trong lúc còn tụt lại, mỗi đoạn xong thì `next_run_at = now`. Pod chết thì chạy tiếp từ đoạn cuối đã xong (AC 60%). Kết nối lại (BR-09) giữ checkpoint cũ, nên kéo bù tự chạy.
   - **Listing:** checkpoint rỗng nghĩa là quét toàn bộ bằng `offset`. Chết giữa chừng thì quét lại từ đầu, vô hại vì upsert idempotent. Quét xong thì đặt checkpoint bằng thời điểm bắt đầu quét. Sau đó mỗi ngày quét tăng dần theo `update_time`, có chồng lấn, lấy cả item `DELETED`. Hành vi này của Shopee chưa xác minh, nên thêm giả định **AS-10** vào SRS (1.4).
   - **Tiến độ:** REST của Shop trả độ trễ checkpoint theo từng loại. Giao diện hiện "Đang đồng bộ dữ liệu cũ" khi độ trễ lớn hơn một chu kỳ.
   - **Để cho G3:** đơn mở cũ hơn 30 ngày ("bất kể thời điểm" của F2.4a), hàng đợi ưu tiên, fairness giữa Workspace, chỉ số "đối soát phát hiện thiếu" (G1 chưa có webhook nên chỉ số chưa có nghĩa), chaos test N4.
   - Lỗi tạm thời và 429 từ sàn thì lùi `next_run_at` có backoff. G1 chưa có rate limiter phân tán (Redis ở G3).

### Làm mới token (F2.2a bản G1)

4. **Làm mới token là loại việc riêng `TOKEN`** (Q4), tới hạn ở `hạn access token − 30 phút`, chạy bằng cùng cơ chế lease.
   - Việc poll chỉ đọc token. Gặp token sắp hết hạn hoặc lỗi 401 thì việc poll tự lùi lịch, không tự refresh.
   - Token mới được ghi với điều kiện `WHERE token_version = ?`.
   - Lỗi tạm thời thì backoff. Lỗi vĩnh viễn thì Shop chuyển `Disconnected`, lý do "Ủy quyền hết hạn", xóa token, và mọi dòng `sync_cursor` của Shop dừng (hàm claim chỉ lấy Shop `Active`).
   - **Để cho G3:** fencing khi lease hết hạn giữa lúc đang refresh, và thí nghiệm "tái hiện lỗi trước khi sửa" (biến thể tắt lease hoặc ép lease hết hạn).

### Mã hóa token sàn (N11)

5. **AES-256-GCM ở tầng ứng dụng, keyring từ Sealed Secret** (Q3). Loại envelope encryption (không có KMS thì không thêm an toàn), `pgcrypto` (khóa lọt vào log và DB) và Vault/OpenBao (không còn RAM). Mã hóa phòng các bản sao ngoài pod, không phòng pod connector bị chiếm.
6. **Tink 1.24.0, AEAD `AES256_GCM`** (Q6). Lệch chuẩn có chủ đích: keyset cleartext nằm trong Sealed Secret vì lab không có KMS (ghi ở ADR-0016). `seller-web` giữ cách tự viết bằng `crypto` của Node; hai bên không đọc ciphertext của nhau.
7. **Một ciphertext cho cả cặp token mỗi dòng** `shop_authorization`, kèm cột `key_id` (Q7). Các mốc hết hạn và hạn ủy quyền để dạng rõ. Associated data là `workspace_id|shop_id|shop_authorization.tokens`.
8. **Xoay khóa** (Q8):
   - Hai bước: `add-key` rồi deploy, `promote-key` rồi deploy.
   - Không cần job mã hóa lại: token tự chuyển sang khóa mới trong khoảng 7 ngày, và Shop `Disconnected` bị xóa token.
   - Gỡ khóa cũ khi metric đếm số dòng theo `key_id` về 0.
   - Xoay thủ công theo runbook, mục tiêu 90 ngày.
   - Dev dùng một keyset commit trong `platform/compose`, ghi rõ chỉ dành cho dev.

### Fact và nguồn (tra 2026-11-13)

- Tink 1.24.0 phát hành 2026-10-16 ([Maven Central](https://repo1.maven.org/maven2/com/google/crypto/tink/tink/maven-metadata.xml), [releases](https://github.com/tink-crypto/tink-java/releases)). Keyset có khóa primary, khóa cũ vẫn giải mã được, ciphertext có prefix 5 byte theo key ID ([keysets](https://developers.google.com/tink/design/keysets)). `tinkey add-key`/`promote-key`; `rotate-keyset` đã deprecated ([Tinkey](https://developers.google.com/tink/tinkey-overview)). Giới hạn 2^32 message mỗi khóa ([AEAD](https://developers.google.com/tink/aead)).
- Shopee `get_order_list` (`time_range_field=update_time`, khoảng ≤ 15 ngày, `page_size` ≤ 100, `cursor`) và `get_item_list` (`update_time_from/to`, `item_status` gồm `DELETED`): **chưa xác minh** với tài liệu chính thức, vì open.shopee.com không đọc được bằng công cụ. Nguồn thứ cấp: [ithelp 10285209](https://ithelp.ithome.com.tw/articles/10285209), [ithelp 10286031](https://ithelp.ithome.com.tw/articles/10286031). Thiết kế không dựa vào thứ tự sắp xếp của kết quả.
- Tên API `TinkJsonProtoKeysetFormat.parseKeyset` **chưa xác minh**, kiểm khi viết spec.

### Đã cập nhật

- SRS 1.4: thêm AS-10.
- Ma trận truy vết: ghi rõ phần G1 và G3 của F2.2a, F2.4a, F5.2b.
- arc42: mục 5 (`channel-connector`), mục 8.9 (mã hóa), mục 8.14 mới (đồng bộ với sàn), mục 9 (ADR-0015, ADR-0016).

## Comments
- 2026-11-13: Từ ticket [18 Gateway ở G1](18-gateway-g1.md#answer): gateway không mở route nào không cần JWT. Callback OAuth của sàn (F2.1a) về một trang của `seller-web`, trang đó `POST` `code` và `state` xuống connector qua BFF kèm Bearer. Connector kiểm `state` và lấy Workspace từ đó cùng `X-Workspace-Id`; chi tiết để spec chốt.
- 2026-11-13: Từ ticket [19 Chiến lược test G1](19-g1-test-strategy.md#answer): trình duyệt tích hợp của Claude desktop đọc được open.shopee.com (đã thử trang [API calls](https://open.shopee.com/developer-guide/16)). Spec G1 dùng nó để xác minh lại `get_order_list`, `get_item_list` và tên API Tink còn ghi "chưa xác minh" ở trên. Adapter Shopee test bằng WireMock với stub chép nguyên văn ví dụ tài liệu.
