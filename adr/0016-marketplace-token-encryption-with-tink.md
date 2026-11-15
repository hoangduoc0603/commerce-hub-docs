---
status: accepted
date: 2026-11-13
---

# ADR-0016: Mã hóa token sàn bằng Tink AEAD, keyset cleartext trong Sealed Secret

`channel-connector` mã hóa token sàn khi lưu (N11) ở tầng ứng dụng bằng **Google Tink 1.24.0**, primitive AEAD `AES256_GCM`.

- Mỗi dòng `shop_authorization` có **một ciphertext cho cả cặp** access token và refresh token, vì hai token luôn được ghi cùng lúc. Các mốc hết hạn và hạn ủy quyền để dạng rõ, vì scheduler cần truy vấn chúng ([ADR-0015](0015-marketplace-sync-as-postgres-work-queue.md)).
- Associated data là `workspace_id|shop_id|shop_authorization.tokens`. Ciphertext bị chép sang dòng của Shop hay Workspace khác thì giải mã thất bại.
- Dòng có thêm cột `key_id` (ID của khóa primary lúc mã hóa) để đếm số dòng theo khóa. Tink tự chọn khóa giải mã theo prefix của ciphertext, nên cột này chỉ dùng cho vận hành.
- Keyset (JSON, cleartext) nằm trong Sealed Secret ở `gitops`, mount vào pod connector. `platform/compose` commit một keyset ghi rõ **chỉ dùng cho dev**: nó chỉ bảo vệ token giả của simulator.
- **Xoay khóa** bằng `tinkey`, chạy thủ công theo runbook, mục tiêu 90 ngày:
  1. `add-key` (chưa primary), rồi deploy.
  2. `promote-key`, rồi deploy.
  3. Gỡ khóa cũ khi số dòng mang `key_id` cũ về 0.

  Không cần job mã hóa lại: token được ghi lại sau mỗi lần refresh (Shopee 4 giờ, TikTok tối đa 7 ngày), còn Shop `Disconnected` bị xóa token ngay khi ngắt.

Mã hóa ở đây phòng các bản sao nằm ngoài pod: dump DB, backup Barman và WAL trên RustFS, log của PostgreSQL, credential của Job migration (đọc được mọi Workspace theo [ADR-0010](0010-workspace-isolation-shared-schema-with-mandatory-rls.md)). Nó **không** phòng được trường hợp pod connector bị chiếm, vì pod cầm khóa.

Bối cảnh ở ticket [17 channel-connector ở G1](../.scratch/architecture-g0-g1/issues/17-connector-g1.md#answer).

## Lệch chuẩn có chủ đích

Tink khuyên không lưu keyset dạng cleartext, mà bọc keyset bằng KEK trong KMS ngoài ([Tink, Key management](https://developers.google.com/tink/key-management-overview), tra 2026-11-13). Lab không có KMS, và không còn RAM cho Vault hay OpenBao ([ADR-0004](0004-single-instance-by-default-on-homelab.md)). Lớp bảo vệ keyset vì thế chỉ là Sealed Secret trong Git cộng Secret của Kubernetes. Mức này ngang với mọi credential khác của cụm.

## Phương án đã cân nhắc

- **Tự viết bằng JCA** (AES/GCM/NoPadding, định dạng `v1.<key_id>.<nonce>.<ct>`, giống `seller-web` làm bằng `crypto` của Node, [ADR-0011](0011-nextjs-bff-with-server-side-session.md)). Bị loại vì đây là crypto tự ráp, dễ sai ở chỗ dùng lại nonce, quên kiểm `key_id`, xoay khóa. Tink đã có sẵn keyset, prefix, associated data và CLI xoay khóa. `seller-web` giữ cách của nó, vì hai bên không bao giờ đọc ciphertext của nhau.
- **Envelope encryption** (data key cho mỗi dòng, bọc bằng master key, C5.3). Bị loại vì chỉ có lợi khi master key nằm trong KMS và không rời KMS. Ở lab, master key nằm chung Secret với mọi thứ, nên chỉ thêm độ phức tạp.
- **`pgcrypto`.** Bị loại vì khóa đi trong câu SQL nên lọt vào log và `pg_stat_statements`, và DB, thứ đang cần phòng, lại có khóa.
- **Vault Transit hoặc OpenBao.** Bị loại ở G1 vì là thêm một thành phần mà RAM không còn chỗ.
- **Mã hóa từng trường.** Bị loại vì hai token luôn đi cùng nhau; một ciphertext thì chỉ có một nonce và một `key_id`.

## Hệ quả

- AES-GCM với nonce ngẫu nhiên 96 bit có giới hạn 2^32 lần mã hóa cho mỗi khóa ([Tink, AEAD](https://developers.google.com/tink/aead); NIST SP 800-38D). Token chỉ được ghi lại mỗi lần refresh nên còn rất xa giới hạn này, nhưng vẫn là lý do để xoay khóa định kỳ.
- Có metric đếm số dòng theo `key_id`. Gỡ một khóa khi metric của nó còn khác 0 thì Shop mang khóa đó mất token.
- Tên API đọc keyset JSON của Tink (`TinkJsonProtoKeysetFormat.parseKeyset` với `InsecureSecretKeyAccess`) **chưa xác minh** bằng Javadoc, kiểm khi viết spec.
- Xét lại khi có KMS hoặc Vault: chuyển sang keyset được bọc bằng KEK, không đổi định dạng ciphertext.
