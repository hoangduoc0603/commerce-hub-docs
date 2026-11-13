# Issue tracker: Local Markdown

Issue, spec và map của commerce-hub nằm dưới dạng file markdown trong `docs/.scratch/` và được commit cùng repo `docs`. Đường dẫn bên dưới tính từ thư mục chứa polyrepo (`commerce-hub/`).

Lý do: dự án làm một mình, các repo chưa có remote. Hệ thống là polyrepo nhưng ticket thường cắt ngang nhiều repo, nên gom về một chỗ trong repo `docs`.

## Quy ước

- Mỗi feature (hoặc increment) một thư mục: `docs/.scratch/<feature-slug>/`
- Spec nằm ở `docs/.scratch/<feature-slug>/spec.md`
- Mỗi ticket triển khai là một file riêng: `docs/.scratch/<feature-slug>/issues/<NN>-<slug>.md`, đánh số từ `01`. Không gộp nhiều ticket vào một file.
- Trạng thái triage ghi bằng một dòng `Status:` ở đầu file issue (xem `triage-labels.md`).
- Ticket chạm vào repo nào thì ghi rõ bằng dòng `Repos:` (ví dụ `Repos: contracts, services/order`). Code vẫn commit trong repo tương ứng.
- Ghi mã yêu cầu (F…, BR-…, N…, SIM-…) trong tiêu đề hoặc thân ticket để truy vết.
- Bình luận và lịch sử trao đổi nối vào cuối file, dưới heading `## Comments`.

## Ticket triển khai (khi `/to-tickets` tạo ticket)

Chủ repo tự làm từng ticket qua `/huong-dan` để học (xem [`huong-dan.md`](huong-dan.md)), nên ticket viết cho người làm:

- `Status: ready-for-human`, thay cho `ready-for-agent`.
- Thêm mục `## Mục tiêu học` ngay sau phần mô tả: 1–3 kỹ thuật chủ repo sẽ học qua ticket, mỗi kỹ thuật một dòng, trỏ tới cột "Kỹ thuật trọng tâm" của [ma trận truy vết](../requirements/traceability.md) hoặc câu chuyện phỏng vấn ở [C19](../requirements-and-techniques.md#c19-chủ-đề-phỏng-vấn-gắn-với-dự-án).
- Mỗi ticket đưa vào nhiều nhất **một khái niệm mới**. Ticket vẫn là một lát cắt dọc chạy và kiểm được; lát cắt cần hai khái niệm mới thì tách thành hai ticket.

## Khi một skill nói "publish to the issue tracker"

Tạo file mới dưới `docs/.scratch/<feature-slug>/`, tạo thư mục nếu chưa có.

## Khi một skill nói "fetch the relevant ticket"

Đọc file ở đường dẫn được nhắc tới. Người dùng thường đưa thẳng đường dẫn hoặc số issue.

## Wayfinding operations

Dùng cho `/wayfinder`. **Map** là một file, mỗi ticket là một file **con**.

- **Map**: `docs/.scratch/<effort>/map.md` (phần Destination / Notes / Decisions so far / Not yet specified / Out of scope).
- **Ticket con**: `docs/.scratch/<effort>/issues/NN-<slug>.md`, đánh số từ `01`, thân file là câu hỏi. Dòng `Type:` ghi loại ticket (`research`/`prototype`/`grilling`/`task`); dòng `Status:` ghi `claimed`/`resolved`.
- **Blocking**: dòng `Blocked by: NN, NN` ở đầu file. Ticket hết bị chặn khi mọi file nó liệt kê đã `resolved`.
- **Frontier**: quét `docs/.scratch/<effort>/issues/` tìm file còn mở, không bị chặn, chưa ai nhận; số nhỏ nhất thắng.
- **Claim**: đặt `Status: claimed` và lưu trước khi làm.
- **Resolve**: ghi câu trả lời dưới heading `## Answer`, đặt `Status: resolved`, rồi thêm một dòng gist kèm link vào mục Decisions so far trong `map.md`. Quyết định khó đảo ngược thì viết thêm ADR trong `docs/adr/` và link từ ticket.
