---
status: accepted
date: 2026-11-24
---

# ADR-0019: Bỏ repo `contracts`, không kiểm tương thích giữa service

Dự án **không có repo `contracts`**. Repo `commerce-hub-contracts` (mới có khung từ ticket G0-01) được archive, giữ làm lịch sử. Hợp đồng giữa các service đổi như sau:

- **REST viết code-first** trong từng service: controller, DTO (record) và Bean Validation viết tay, không sinh code từ OpenAPI. Test HTTP (MockMvc) kiểm JSON trực tiếp bằng JsonPath trên đúng tên field, nên đổi tên một field thì test đỏ. Chưa có springdoc; muốn có trang tài liệu thì thêm một dependency sau.
- **Event Kafka là JSON, không có schema registry.** Producer khai record nó gửi; consumer chép record đó vào repo của mình và chỉ đọc field nó cần (tolerant reader). Chi tiết (serde, envelope, cách đặt tên) chốt ở đầu Giai đoạn 1.
- **Danh mục `code` của Problem Details** nằm trong từng service.
- **Giá trị phải giống nhau giữa service** (namespace và cách nối chuỗi của UUIDv5, [ADR-0009](0009-deterministic-ids-for-marketplace-entities.md)) ghi trong ADR kèm cặp giá trị mẫu. Service nào tính thì chép hằng số và có test so với đúng các cặp đó.
- Kỹ thuật **OpenAPI contract-first, Schema Registry kèm Avro, kiểm tương thích schema và Pact** nằm **ngoài phạm vi** dự án. Muốn mở lại thì phải viết ADR mới.

Lý do: chủ repo chốt mục tiêu học là bên trong từng service (Spring Boot, persistence, Kafka producer/consumer, saga, observability), không phải bài toán giữ tương thích khi các service tiến hóa độc lập. Phần còn lại của `contracts` là công cụ và hạ tầng không ai dùng ở G0: lint OpenAPI, `oasdiff`, `org.openapi.generator`, publish Maven và npm lên GitHub Packages, token đọc chéo repo, Apicurio. G0–G1 chỉ có một lệnh REST giữa service (F3.3c).

## Phương án đã cân nhắc

- **Giữ `contracts` đầy đủ** (ticket G0-19 và G0-20: OpenAPI, Avro, `BACKWARD_TRANSITIVE` với Apicurio, publish bất biến). Đây là hướng cũ của ticket 09, 11 và 19 trong map kiến trúc. Bị loại vì không thuộc mục tiêu học đã chốt.
- **Hoãn `contracts` tới G7.** Bị loại: chủ repo chọn bỏ hẳn. Ghi "hoãn" thì danh mục kỹ thuật vẫn hứa một thứ không ai định làm.
- **Avro kèm Apicurio nhưng không kiểm tương thích.** Vẫn phải vận hành Apicurio và vẫn cần một chỗ chung cho file `.avsc`, tức là quay lại bài toán contract. Bị loại.
- **Bỏ luôn polyrepo** vì một lý do của [ADR-0001](0001-polyrepo.md) là học chia sẻ contract. Bị loại: polyrepo vẫn dạy deploy độc lập (mỗi service một CI, image, dòng trong `gitops`), và các repo đã chạy.

## Hệ quả

- **Đổi field ở producer thì consumer hỏng lúc chạy**, không phải lúc build. Lỗi chỉ lộ qua test của consumer (nếu record chép còn khớp với bản thật) hoặc message rơi vào DLT. Chấp nhận có chủ đích.
- Bản chép record giữa producer và consumer trôi lệch dần. Cùng loại chi phí với code chép từ template trong [ADR-0018](0018-self-contained-services-no-shared-library-yet.md).
- Không có CI chặn field mang tên sàn trong dữ liệu giữa service. N13 kiểm bằng review kiến trúc, đúng cách kiểm ghi trong SRS.
- [ADR-0001](0001-polyrepo.md): repo nối nhau qua artifact có version (image, chart, reusable workflow) và runtime. [ADR-0005](0005-kafka-from-g1-with-deliberate-dual-write.md): G1 không có Avro hay Schema Registry. [ADR-0009](0009-deterministic-ids-for-marketplace-entities.md): namespace UUIDv5 ghi trong ADR đó. [ADR-0006](0006-public-repos-on-personal-account.md), [ADR-0018](0018-self-contained-services-no-shared-library-yet.md): bỏ `contracts` khỏi danh sách repo và khỏi phần publish Maven.
- Ticket G0-16 (Apicurio), G0-19 (OpenAPI), G0-20 (contract Avro): `wontfix`. Ticket G0-26, 28, 29, 31, 32, 34 sửa theo. Chi tiết ở mục "Sửa phạm vi 2026-11-24" của [spec G0](../.scratch/g0-platform/spec.md). Ticket kế trong "Thứ tự làm" là G0-26.
- Cụm và compose không có Apicurio, nên trả lại phần RAM đó cho ngân sách của [ADR-0004](0004-single-instance-by-default-on-homelab.md).
- **Xét lại khi** có hai service gọi REST lẫn nhau ngoài F3.3c, hoặc một sự cố thật do producer và consumer lệch record. Khi đó viết ADR mới và chọn giữa kiểm tương thích ở CI hay contract test.
