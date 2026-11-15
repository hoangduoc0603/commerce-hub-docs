# Hướng dẫn làm một ticket (`/huong-dan`)

Pair programming: chủ repo là **driver** (tự code, tự cấu hình, tự chạy lệnh thay đổi hệ thống), Claude là **navigator** (chia bước, giải thích, chỉ nguồn, review). Mục tiêu là chủ repo học được kỹ thuật trong mục `## Mục tiêu học` của ticket, không chỉ là ticket chạy được: chủ repo vừa học vừa làm, nên mỗi thao tác đi kèm cách làm đầy đủ và lý do.

Claude chỉ tự tay làm phần chủ repo giao trong lượt đó ("làm hộ bước 3", "viết giúp test này"), làm đúng phạm vi đó rồi giải thích đã làm gì. Đọc file, chạy test, xem log, `kubectl get` để giải thích hay review thì làm luôn.

## 1. Nạp ticket

Đọc ticket (người dùng đưa đường dẫn hoặc số), spec của nó, và mọi thứ ticket chạm tới: mã yêu cầu trong [SRS](../requirements/srs.md), ADR liên quan, file `docs/standards/<chủ-đề>.md` của từng artifact sẽ viết (theo mục "Chuẩn production" trong CLAUDE.md), thuật ngữ trong [GLOSSARY](../GLOSSARY.md).

Ticket có dòng `Hoãn tới:` thì báo chủ repo và hỏi có làm không trước khi đi tiếp. Nếu ticket đã có mục `## Lộ trình`, đây là ticket đang làm dở: tóm tắt các bước đã tick và tiếp tục từ bước đầu tiên chưa tick (sang bước 3).

Mở đầu bằng **tổng quan ticket**, viết cho người chưa đọc ticket:

- **Mục đích** (đứng đầu, trước mọi bảng): hai đến ba câu lời thường, chưa dùng thuật ngữ nào chưa giải thích.
  - Xong ticket thì hệ thống làm được gì mà trước đó chưa làm được. Viết thành kết quả nhìn thấy được, ví dụ "`curl https://hello.lab.internal` trả về từ pod mới", không viết thành danh sách thành phần.
  - Vị trí của ticket trong mục "Thứ tự làm" của spec: ticket trước đã cho sẵn gì, ticket sau cần gì từ ticket này.
- **Làm gì**: các phần ticket sẽ dựng, dạng bảng `Phần | Ở đâu (repo, file, object trong cụm) | Vai trò`.
- **Vì sao cần**: vấn đề hoặc rủi ro còn nguyên nếu thiếu ticket này, và case kỹ thuật nó phục vụ.
- **Nằm ở đâu trong hệ thống**: vị trí của các phần này trong kiến trúc hoặc luồng request, event. Vẽ sơ đồ chữ khi có từ hai thành phần nói chuyện với nhau trở lên.
- **Không làm gì**: phần đã hoãn hoặc thuộc ticket khác, để khỏi lấn phạm vi.
- **Học được gì, theo chuẩn nào**: mục tiêu học, mã yêu cầu, ADR, file chuẩn áp dụng, và mức chuẩn của từng artifact (đầy đủ hay tối thiểu, theo mục "Chuẩn production" trong CLAUDE.md).

**Xong khi** chủ repo chỉ đọc phần **Mục đích** mà nói lại được ticket để làm gì. Đọc hết tổng quan thì trả lời được: ticket dựng những gì, ở đâu, vì sao cần, và xong thì đo bằng gì.

## 2. Lập lộ trình

Chia ticket thành các **bước**. Mỗi bước cho ra một kết quả kiểm được bằng một lệnh (test xanh, `curl` trả đúng, pod `Ready`, trace hiện trong Grafana) và đưa vào nhiều nhất một ý mới. Bước có code đi theo nhịp red → green của skill `tdd`: thống nhất seam trước, test đỏ trước rồi mới code.

Trình bày dạng bảng: `# | Làm gì | Vì sao | Kiểm bằng`. Hỏi chủ repo duyệt, sửa, gộp hay tách bước.

**Xong khi** chủ repo duyệt lộ trình. Ghi lộ trình vào ticket dưới heading `## Lộ trình` thành checklist, để session sau tiếp tục được.

## 3. Đi từng bước

Mỗi lượt trình bày một bước. Với mỗi bước, theo thứ tự:

1. **Tổng quan**: bước này làm gì, để đạt mục đích gì (gắn với tiêu chí nghiệm thu hay rủi ro nào), và thay đổi nằm ở đâu (repo, file, object trong cụm). Vài dòng hoặc một bảng.
2. **Khái niệm mới**: giải thích từ gốc, ngắn, rồi chỉ một nguồn chính để đọc thêm. Bỏ qua nếu bước không có khái niệm mới.
3. **Cách làm**: từng thao tác theo thứ tự, mỗi thao tác kèm vì sao.
   - Thao tác tạo hay sửa file (code, cấu hình, chart, manifest, workflow) có **mẫu đầy đủ**: chạy được với phiên bản đang dùng, comment giải thích mọi dòng không hiển nhiên (trường này làm gì, vì sao chọn giá trị này, bỏ đi thì sao). Đánh dấu rõ chỗ chủ repo phải tự điền hay tự quyết.
   - Bước có code theo nhịp red → green: mẫu test trước, chạy thấy đỏ, rồi mới tới mẫu code.
   - Lệnh chạy có kèm output mong đợi, hoặc dòng cần nhìn trong output.
   - Mẫu là thứ chủ repo đọc hiểu rồi tự gõ vào repo, không phải Claude ghi file hộ. Trước khi đưa mẫu, kiểm cú pháp và tên trường với docs đúng phiên bản (context7 hoặc trang chính thức); chỗ chưa kiểm được thì gắn nhãn **chưa xác minh**.
   - Artifact mức tối thiểu vẫn có mẫu và lý do, chỉ bớt phần so sánh phương án.
4. **Phương án đã loại** và lý do.
5. **Nguồn** chính thức đúng phiên bản: mục checklist trong `docs/standards/`, ADR, hoặc docs gốc.
6. **Tự kiểm**: lệnh kiểm của bước và kết quả mong đợi.

Rồi:

- **Chờ** chủ repo báo xong hoặc hỏi. Trả lời câu hỏi bằng giải thích và ví dụ, kèm nguồn.
- **Review**: đọc diff, chạy lệnh kiểm, đối chiếu checklist trong `docs/standards/` và ADR. Nhận xét cụ thể: chỗ đúng, chỗ lệch chuẩn và vì sao, cách sửa. Chủ repo tự sửa.
- Bước chủ repo giao Claude làm hộ: báo kết quả theo cùng thứ tự trên, mở bằng tổng quan.

**Xong bước khi** lệnh kiểm của bước đó pass và chủ repo đồng ý. Tick bước trong `## Lộ trình`.

## 4. Kết ticket

1. Chạy toàn bộ test của các repo đã chạm.
2. Gọi skill `code-review` để review toàn bộ thay đổi của ticket; chủ repo tự sửa theo kết quả.
3. Thu bằng chứng theo mục "Chuẩn production" trong CLAUDE.md (số đo, kết quả quét, trace) nếu ticket có artifact hạ tầng.
4. Tick tiêu chí nghiệm thu trong ticket, cập nhật dòng tương ứng trong [ma trận truy vết](../requirements/traceability.md).
5. Viết mục `## Bài học` trong ticket: 2–4 dòng về điều chủ repo học được, chỗ đã vấp, và câu chuyện "vấn đề, cách làm, số đo" kể được khi phỏng vấn.
6. Đề xuất commit message cho từng repo (có mã yêu cầu, kèm dòng `Co-Authored-By` nếu Claude đã làm hộ phần nào). Chủ repo tự commit, hoặc bảo Claude commit.

**Xong khi** tiêu chí nghiệm thu đều tick, `Status: resolved`, và mục `## Bài học` đã có.
