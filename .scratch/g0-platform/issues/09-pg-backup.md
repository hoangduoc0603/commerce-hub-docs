# 09: Backup liên tục `pg-main` lên RustFS

Status: ready-for-human
Hoãn tới: G7 (quyết định 2026-11-15, spec G0 mục "Sửa phạm vi 2026-11-15")
Lý do: backup và RPO là vận hành hạ tầng, không phải trọng tâm backend của dự án; xếp vào nhóm "Vận hành production-grade" của G7.
Blocked by: 06, 08
Repos: gitops, platform, docs
Spec: [G0](../spec.md)

## Mô tả

RustFS chạy trên `gw` làm đích S3. Plugin Barman Cloud v0.16.0 (cần cert-manager) archive WAL của `pg-main` với `archive_timeout: 1min`, `ScheduledBackup` hằng ngày, giữ 14 ngày. Ticket này không diễn tập khôi phục (để sau, N10). Theo ticket 03 của map và [homelab](../../../../platform/docs/homelab-hyperv.md).

## Mục tiêu học

- Archive WAL cộng base backup tạo ra RPO thế nào (N10).

## Tiêu chí nghiệm thu

- [ ] Trạng thái cluster báo continuous archiving OK; có WAL mới trên RustFS mỗi phút khi có ghi.
- [ ] Một base backup thủ công và một bản theo lịch đều `completed`.
- [ ] Credential của RustFS là `SealedSecret`.
- [ ] RAM của RustFS trên `gw` đo được, ghi vào bản ghi thí nghiệm G0 (điểm chưa xác minh của ticket 04 của map).
- [ ] Runbook homelab có phần cài RustFS.
