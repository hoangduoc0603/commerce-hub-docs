# Kiến trúc commerce-hub

Tài liệu kiến trúc theo [arc42](https://arc42.org/overview) (bản 9), sơ đồ theo [C4 model](https://c4model.com/). Phạm vi hiện tại: **Giai đoạn 0–1** ([C18](../requirements-and-techniques.md#c18-lộ-trình-gợi-ý)).

Tài liệu này **tổng hợp**, không quyết định. Mỗi quyết định nằm ở một ADR trong [`adr/`](../adr/) hoặc ở ticket của [map kiến trúc G0–G1](../.scratch/architecture-g0-g1/map.md). Ở đây chỉ tóm tắt và trỏ về đó. Khi một quyết định đổi, sửa ADR hoặc ticket trước, rồi sửa đoạn tóm tắt ở đây.

| Mục arc42 | File | Trạng thái |
|---|---|---|
| 1. Giới thiệu và mục tiêu | [01-introduction-and-goals.md](01-introduction-and-goals.md) | G0–G1 |
| 2. Ràng buộc | [02-constraints.md](02-constraints.md) | G0–G1 |
| 3. Bối cảnh và phạm vi (C4 Context) | [03-context-and-scope.md](03-context-and-scope.md) | G0–G1 |
| 4. Chiến lược giải pháp | [04-solution-strategy.md](04-solution-strategy.md) | G0–G1 |
| 5. Building block (C4 Container) | [05-building-block-view.md](05-building-block-view.md) | G0–G1 |
| 6. Runtime view | — | Chưa viết. Luồng G1 viết ở spec G1 |
| 7. Deployment view | — | Chưa viết. Cửa vào cụm còn mở ([ticket 16](../.scratch/architecture-g0-g1/issues/16-cluster-entry.md)) |
| 8. Khái niệm xuyên suốt | [08-crosscutting-concepts.md](08-crosscutting-concepts.md) | G0–G1 |
| 9. Quyết định kiến trúc | [09-architecture-decisions.md](09-architecture-decisions.md) | ADR-0001..0012 |
| 10–12. Chất lượng, rủi ro, thuật ngữ | — | Chưa viết. Thuật ngữ ở [GLOSSARY](../GLOSSARY.md) |

## Quy ước

- Sơ đồ viết bằng Mermaid `flowchart` theo ký hiệu C4: mỗi hộp ghi tên, loại (`[Container: công nghệ]`) và một dòng trách nhiệm. Mermaid hiển thị được trên GitHub mà không cần công cụ ngoài. Cú pháp `C4Context` của Mermaid vẫn là thử nghiệm và tự dàn trang kém, nên không dùng.
- Thuật ngữ nghiệp vụ dùng đúng [GLOSSARY](../GLOSSARY.md). Mã yêu cầu (F…, BR-…, N…, SIM-…) theo [SRS](../requirements/srs.md).
- Phiên bản phần mềm ghi ở đây là bản đã chốt trong ticket hoặc `docs/standards/` tại ngày tra của chúng. Nguồn và ngày tra nằm ở file gốc.
