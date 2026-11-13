# commerce-hub docs

Tài liệu cấp hệ thống của commerce-hub. Tài liệu riêng của một service nằm trong repo của service đó.

| Đường dẫn | Dùng cho |
|---|---|
| `project-charter.md` | Mục tiêu, phạm vi, ràng buộc, mô hình SDLC, rủi ro |
| `GLOSSARY.md` | Ngôn ngữ chung: định nghĩa thuật ngữ nghiệp vụ |
| `requirements/srs.md` | Đặc tả yêu cầu: P0 chi tiết có tiêu chí nghiệm thu, P1/P2 dạng danh sách, NFR, yêu cầu Simulator |
| `requirements/domain-model.md` | Thực thể, quan hệ, ranh giới nhất quán (mức khái niệm) |
| `requirements/user-flows.md` | Các luồng người dùng chính của P0 |
| `requirements/traceability.md` | Yêu cầu ↔ thành phần ↔ giai đoạn ↔ test |
| `requirements-and-techniques.md` | Đầu vào cho thiết kế: đặc điểm các sàn (A2), thiết kế tổng quan (Phần B), kỹ thuật áp dụng và lộ trình (Phần C) |
| `architecture/` | Kiến trúc theo arc42 + C4: bối cảnh, chiến lược, building block, khái niệm xuyên suốt, chỉ mục quyết định |
| `research/` | Ghi chép tra cứu có nguồn, đặt tên `YYYY-MM-chu-de.md` |
| `adr/` | Architecture Decision Records cấp hệ thống, đánh số `NNNN-ten-quyet-dinh.md` |
| `experiments/` | Mỗi thí nghiệm một thư mục: giả thuyết, cách đo, số đo, kết luận |
| `runbooks/` | Hướng dẫn vận hành, xử lý sự cố, postmortem |
| `agents/` | Cấu hình cho engineering skills: issue tracker, nhãn triage, cách đọc domain docs |
| `.scratch/` | Issue tracker dạng markdown: spec, ticket, map của wayfinder, mỗi feature một thư mục |

Thứ tự đọc: Charter → Glossary → SRS → Domain model → Luồng người dùng.
