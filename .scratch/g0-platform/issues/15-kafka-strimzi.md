# 15: Kafka KRaft trên Strimzi

Status: ready-for-human
Blocked by: 03
Repos: gitops, docs
Spec: [G0](../spec.md)

## Mô tả

Strimzi 1.3.1 chạy Kafka 4.3.2 KRaft 3 node dual-role, mỗi broker 1 Gi với heap 512m, `default.replication.factor: 3`, `min.insync.replicas: 2`. Listener nội bộ bắt xác thực ngay từ G0 (theo mục "Bảo mật" của [kafka.md](../../../standards/kafka.md)). Entity Operator có limit. Có Strimzi Drain Cleaner. Chưa có topic nghiệp vụ; topic `perf` chỉ tạo tạm để đo.

## Mục tiêu học

- Độ bền của Kafka: `acks=all`, ISR, `min.insync.replicas`, và KRaft quorum.

## Tiêu chí nghiệm thu

- [ ] CR `Kafka` `Ready=True`; `kafka-metadata-quorum.sh describe --status` có 3 voter, 1 leader, lag 0.
- [ ] `kafka-producer-perf-test` 2 triệu record với `acks=all`, xóa một broker giữa chừng: 0 lỗi gửi, đọc lại đủ số đã ack, `UnderReplicatedPartitions` về 0.
- [ ] Tắt 2 broker, gửi với `acks=all`: producer nhận `NotEnoughReplicas`.
- [ ] Client không có credential không kết nối được listener nội bộ.
- [ ] `kubectl drain` một node: Drain Cleaner giữ ISR; ghi thời gian.
- [ ] Topic `perf` đã xóa sau khi đo; kết quả vào `docs/experiments/`.
