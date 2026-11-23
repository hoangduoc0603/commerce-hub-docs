# Domain Docs

Cách các engineering skill đọc tài liệu domain của commerce-hub khi khám phá codebase.

Layout: **single-context**. Hệ thống là polyrepo, nhưng chỉ có một ngôn ngữ chung (một `GLOSSARY.md`) và một chỗ chứa ADR cấp hệ thống, cả hai nằm trong repo `docs`, không nằm ở gốc.

## Đọc trước khi khám phá

- **`docs/GLOSSARY.md`**: thuật ngữ chuẩn (Workspace, Listing, Available, Short order…).
- **`docs/adr/`**: đọc các ADR liên quan tới vùng sắp làm.
- **`docs/requirements/srs.md`**: đọc các mã yêu cầu liên quan (F…, BR-…, N…, SIM-…). SRS thắng mọi tài liệu khác.
- Tài liệu riêng của một service (nếu có) nằm trong repo của service đó, ví dụ `services/<service>/docs/`.

Nếu một file chưa tồn tại thì **cứ tiếp tục, không báo**. Đừng đề xuất tạo trước. `/domain-modeling` (qua `/grill-with-docs` và `/improve-codebase-architecture`) tạo chúng khi thuật ngữ hoặc quyết định thật sự được chốt.

## Cấu trúc

```
commerce-hub/                 ← thư mục chứa, không phải git repo
├── CLAUDE.md
├── docs/                     ← repo docs
│   ├── GLOSSARY.md
│   ├── adr/
│   │   ├── 0001-polyrepo.md
│   │   └── 0002-reserve-stock-on-first-sight.md
│   ├── requirements/
│   └── .scratch/             ← issue tracker (xem issue-tracker.md)
├── services/<service>/
└── simulators/<simulator>/
```

## Dùng đúng thuật ngữ trong glossary

Khi đầu ra nhắc tới một khái niệm domain (tiêu đề issue, đề xuất refactor, giả thuyết, tên test), dùng đúng thuật ngữ trong `docs/GLOSSARY.md`. Không trôi sang từ đồng nghĩa mà glossary đã loại.

Nếu khái niệm cần dùng chưa có trong glossary thì đó là tín hiệu: hoặc bạn đang tự đặt ngôn ngữ mà dự án không dùng (cân nhắc lại), hoặc đó là lỗ hổng thật (ghi lại cho `/domain-modeling`). Theo CLAUDE.md, khi chốt được thuật ngữ mới thì thêm ngay vào glossary.

## Nêu rõ khi mâu thuẫn ADR

Nếu đầu ra mâu thuẫn với một ADR có sẵn, nói rõ thay vì lặng lẽ ghi đè:

> _Mâu thuẫn với ADR-0002 (giữ tồn ngay khi thấy đơn), nhưng đáng mở lại vì…_
