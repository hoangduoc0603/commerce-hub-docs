# Hướng dẫn làm một ticket (`/huong-dan`)

Pair programming: chủ repo là **driver** (tự code, tự cấu hình, tự chạy lệnh thay đổi hệ thống), Claude là **navigator** (chia bước, giải thích, chỉ nguồn, review). Mục tiêu là chủ repo học được kỹ thuật trong mục `## Mục tiêu học` của ticket, không chỉ là ticket chạy được.

Claude chỉ tự tay làm phần chủ repo giao trong lượt đó ("làm hộ bước 3", "viết giúp test này"), làm đúng phạm vi đó rồi giải thích đã làm gì. Đọc file, chạy test, xem log, `kubectl get` để giải thích hay review thì làm luôn.

## 1. Nạp ticket

Đọc ticket (người dùng đưa đường dẫn hoặc số), spec của nó, và mọi thứ ticket chạm tới: mã yêu cầu trong [SRS](../requirements/srs.md), ADR liên quan, file `docs/standards/<chủ-đề>.md` của từng artifact sẽ viết (theo mục "Chuẩn production" trong CLAUDE.md), thuật ngữ trong [GLOSSARY](../GLOSSARY.md).

Nếu ticket đã có mục `## Lộ trình`, đây là ticket đang làm dở: tóm tắt các bước đã tick và tiếp tục từ bước đầu tiên chưa tick (sang bước 3).

**Xong khi** đã nêu cho chủ repo: tiêu đề ticket, mục tiêu học, các mã yêu cầu, ADR và file chuẩn áp dụng.

## 2. Lập lộ trình

Chia ticket thành các **bước**. Mỗi bước cho ra một kết quả kiểm được bằng một lệnh (test xanh, `curl` trả đúng, pod `Ready`, trace hiện trong Grafana) và đưa vào nhiều nhất một ý mới. Bước có code đi theo nhịp red → green của skill `tdd`: thống nhất seam trước, test đỏ trước rồi mới code.

Trình bày dạng bảng: `# | Làm gì | Vì sao | Kiểm bằng`. Hỏi chủ repo duyệt, sửa, gộp hay tách bước.

**Xong khi** chủ repo duyệt lộ trình. Ghi lộ trình vào ticket dưới heading `## Lộ trình` thành checklist, để session sau tiếp tục được.

## 3. Đi từng bước

Với mỗi bước, theo thứ tự:

1. **Giải thích**: làm gì, vì sao làm vậy, phương án đã loại và lý do. Kèm nguồn chính thức đúng phiên bản (mục checklist trong `docs/standards/`, ADR, hoặc docs gốc). Khái niệm mới thì giải thích ngắn rồi chỉ một nguồn chính để đọc thêm.
2. **Giao việc**: nói rõ chủ repo cần tạo hay sửa gì, kết quả mong đợi, và lệnh để tự kiểm. Đưa gợi ý và khung; lời giải đầy đủ chỉ khi chủ repo hỏi.
3. **Chờ** chủ repo báo xong hoặc hỏi. Trả lời câu hỏi bằng cách dẫn tới nguồn và gợi ý.
4. **Review**: đọc diff, chạy lệnh kiểm, đối chiếu checklist trong `docs/standards/` và ADR. Nhận xét cụ thể: chỗ đúng, chỗ lệch chuẩn và vì sao, cách sửa. Chủ repo tự sửa.

**Xong bước khi** lệnh kiểm của bước đó pass và chủ repo đồng ý. Tick bước trong `## Lộ trình`.

## 4. Kết ticket

1. Chạy toàn bộ test của các repo đã chạm.
2. Gọi skill `code-review` để review toàn bộ thay đổi của ticket; chủ repo tự sửa theo kết quả.
3. Thu bằng chứng theo mục "Chuẩn production" trong CLAUDE.md (số đo, kết quả quét, trace) nếu ticket có artifact hạ tầng.
4. Tick tiêu chí nghiệm thu trong ticket, cập nhật dòng tương ứng trong [ma trận truy vết](../requirements/traceability.md).
5. Viết mục `## Bài học` trong ticket: 2–4 dòng về điều chủ repo học được, chỗ đã vấp, và câu chuyện "vấn đề, cách làm, số đo" kể được khi phỏng vấn.
6. Đề xuất commit message cho từng repo (có mã yêu cầu, kèm dòng `Co-Authored-By` nếu Claude đã làm hộ phần nào). Chủ repo tự commit, hoặc bảo Claude commit.

**Xong khi** tiêu chí nghiệm thu đều tick, `Status: resolved`, và mục `## Bài học` đã có.
