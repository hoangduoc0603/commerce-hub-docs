# Runbook: thêm một service (database) vào `pg-main`

Thêm database, role và mật khẩu cho một service mới trên cluster PostgreSQL dùng chung `pg-main`, trong **một commit** của repo `gitops`. Kèm cách đưa mật khẩu sang namespace của service, đổi mật khẩu, gỡ service và xử lý sự cố.

- Ticket: [G0-08](../.scratch/g0-platform/issues/08-pg-main.md). Chuẩn: [postgres-cnpg.md](../standards/postgres-cnpg.md), [db-migration.md](../standards/db-migration.md) mục "Tách quyền migrate và runtime". ADR: [0003](../adr/0003-shared-postgres-cluster.md), [0010](../adr/0010-workspace-isolation-shared-schema-with-mandatory-rls.md).
- Phiên bản: CloudNativePG **1.30.1**, PostgreSQL **18.7**, PgBouncer 1.25.2, Argo CD 3.6.1, Sealed Secrets 0.41.2.
- Diễn tập ngày 2026-11-15: database `keycloak` (biến thể B) thêm bằng commit gitops `8c44be4` (4 file, 80 dòng), app `pg-main` `Synced/Healthy` 12 s sau push. Biến thể A dựng lần đầu với `hello` (commit `da82fd6` và `359a90e`, G0-08 bước 4–5).
- Mẫu để copy: `gitops/infra/pg-main/hello.yaml` (A), `gitops/infra/pg-main/keycloak.yaml` (B).

## Mô hình trong một đoạn

Mỗi database trên `pg-main` được bảo vệ bởi bốn lớp, đều khai báo trong `gitops/infra/pg-main/`:

| Lớp | Object | Chặn điều gì |
|---|---|---|
| Ai được nối vào database nào | Một dòng `hostssl <db> <role,...> all scram-sha-256` trong `Cluster.spec.postgresql.pg_hba`, **trước** dòng `host all all all reject` | Role của service này vào database của service khác; kết nối không TLS |
| Role làm được gì | `DatabaseRole` (LOGIN hay không, `BYPASSRLS`, `inRoles`) | Runtime chạy DDL; role đăng nhập được mà vượt RLS |
| Mật khẩu | `SealedSecret` `kubernetes.io/basic-auth` có nhãn `cnpg.io/reload` | Plaintext trong Git |
| Bao nhiêu kết nối | `connectionLimit` trên từng role LOGIN | Một service chiếm hết `max_connections` của cả cụm |

Thứ tự áp nằm trong sync wave, nên mọi thứ vào được một commit: `Cluster` (0) → SealedSecret, role NOLOGIN (1) → role LOGIN (2) → `Database` (3). Argo CD chờ wave trước `Healthy` rồi mới áp wave sau. Đổi `pg_hba` chỉ reload PostgreSQL, không restart pod.

Chọn biến thể:

| | A. Service G1 (có RLS, Flyway) | B. Ứng dụng tự migrate, không RLS (Keycloak) |
|---|---|---|
| Role | `<svc>_owner` (NOLOGIN), `<svc>_lookup` (NOLOGIN, `BYPASSRLS`), `<svc>_migrator` (LOGIN, `inRoles` owner + lookup), `<svc>_app` (LOGIN) | Một role `<svc>` LOGIN, là owner database |
| SealedSecret | 2 (`_migrator`, `_app`) | 1 |
| `connectionLimit` | `_migrator` 2, `_app` 10 (= `default_pool_size` 8 của Pooler 1 pod + 2 chỗ cho kết nối thẳng) | Bằng kích thước pool của ứng dụng × số pod (Keycloak: 20) |
| Đường nối | Runtime qua `pg-main-pooler-rw`; Job Flyway thẳng `pg-main-rw` | Thẳng `pg-main-rw` |
| Vì sao | Runtime không có DDL, migrate tách quyền (db-migration.md) | Ứng dụng tự đổi schema bằng chính thông tin DB của nó, nên role runtime phải có DDL. Owner database tạo được bảng trong `public` (PostgreSQL 15+, `public` thuộc `pg_database_owner`) mà không cần `GRANT`. Quyết định C của G0-08 |

Các lệnh `psql` trong runbook chạy trong pod primary, đặt biến trước. Tên pod đổi sau switchover (ngày 2026-11-15 primary chuyển từ `pg-main-1` sang `pg-main-2` khi bảo trì node), nên không ghi cứng:

```bash
P=$(kubectl get cluster pg-main -n postgres -o jsonpath='{.status.currentPrimary}')
```

## 1. Kiểm ngân sách kết nối

`max_connections` 100, trừ 3 `superuser_reserved_connections` còn **97**. Tổng `connectionLimit` của mọi role LOGIN phải dưới 97 để một service chiếm hết phần của nó không làm service khác hết chỗ.

```bash
kubectl exec -n postgres "$P" -c postgres -- psql -Atc "select sum(rolconnlimit) from pg_roles where rolcanlogin and rolconnlimit > 0"
```

Kế hoạch G0–G1: 6 database kiểu A × 12 = 72, Keycloak 20, còn 5. Ngày 2026-11-15 đang dùng 32 (`hello` 12, `keycloak` 20). Thiếu chỗ thì dừng lại, tăng `max_connections` (cần restart pod, có gián đoạn) hoặc giảm giới hạn, ghi lý do vào chuẩn.

## 2. Sinh mật khẩu (mỗi role LOGIN một file)

256 bit ngẫu nhiên dạng hex (không ký tự đặc biệt, không phải escape trong URL JDBC), pipe thẳng sang `kubeseal`, plaintext không chạm đĩa và không hiện ra màn hình:

```bash
cd ~/Desktop/sys-craft/lab/commerce-hub/gitops/infra/pg-main
openssl rand -hex 32 | tr -d '\n' | kubectl create secret generic pg-main-<role-có-gạch-ngang> -n postgres \
  --type=kubernetes.io/basic-auth --from-literal=username=<role> --from-file=password=/dev/stdin \
  --dry-run=client -o yaml | kubectl label --local -f - cnpg.io/reload=true -o yaml | kubeseal --format yaml \
  | yq e '.metadata.annotations["argocd.argoproj.io/sync-wave"] = "1" | del(.metadata.creationTimestamp) | del(.spec.template.metadata.creationTimestamp)' - \
  > pg-main-<role-có-gạch-ngang>.sealedsecret.yaml
```

- `username` phải trùng tên role (CNPG từ chối nếu khác).
- Nhãn `cnpg.io/reload` phải nằm ở `spec.template.metadata.labels` (kubeseal tự chép từ Secret đầu vào): đổi mật khẩu thì operator áp ngay.
- Wave `1`, không phải `-1` như mặc định của [sealing-key.md](sealing-key.md): trong app `pg-main`, Secret chỉ cần có trước `DatabaseRole`.
- Thêm header comment như `pg-main-hello-app.sealedsecret.yaml` (lệnh sinh, ngày, chỗ có bản sao).

## 3. Viết file CR

Copy mẫu thành `gitops/infra/pg-main/<svc>.yaml`, đổi tên. Với mỗi role:

- `name` dùng gạch dưới (`<svc>_app`); `metadata.name` dùng gạch ngang (`<svc>-app`).
- Ghi rõ `connectionLimit` (bỏ trống là -1, không giới hạn).
- Không khai `superuser`, `createdb`, `createrole`, `replication`; `bypassrls: true` chỉ ở `<svc>_lookup` (NOLOGIN).
- Không đặt `databaseRoleReclaimPolicy`, `databaseReclaimPolicy` khác `retain`: xóa nhầm CR không được `DROP`.
- Role do CR quản lý thì không sửa bằng `ALTER ROLE` tay (`DatabaseRole` không phát hiện drift).

## 4. Mở `pg_hba`

Thêm một dòng vào `gitops/infra/pg-main/cluster.yaml`, **phía trên** dòng `reject`:

```yaml
    pg_hba:
      - hostssl hello hello_migrator,hello_app all scram-sha-256
      - hostssl keycloak keycloak all scram-sha-256
      - hostssl <db> <role-login>[,<role-login>] all scram-sha-256   # dòng mới
      - host all all all reject                                      # luôn cuối cùng
```

Chỉ liệt kê role LOGIN. Đặt dòng mới dưới `reject` thì nó không bao giờ được dùng tới (luật khớp đầu tiên thắng).

## 5. Thêm vào kustomization, dry-run, một commit

```bash
cd ~/Desktop/sys-craft/lab/commerce-hub/gitops
# thêm các file SealedSecret và <svc>.yaml vào infra/pg-main/kustomization.yaml
kubectl kustomize infra/pg-main | kubectl apply --dry-run=server -f -
bash scripts/check-no-plain-secrets.sh        # phải in OK
git add infra/pg-main && git commit -m "pg-main: database <svc> ... (<mã yêu cầu>)" && git push
```

Commit gồm đúng: các file SealedSecret mới, `<svc>.yaml`, `cluster.yaml` (+1 dòng), `kustomization.yaml`. Kiểm bằng `git show --stat HEAD`.

## 6. Kiểm sau khi sync

```bash
kubectl get application pg-main -n argocd                  # Synced/Healthy
kubectl get databaserole,database -n postgres              # APPLIED true
```

Thuộc tính role và chính sách `pg_hba`:

```bash
kubectl exec -n postgres "$P" -c postgres -- psql \
  -c "select rolname, rolcanlogin, rolbypassrls, rolconnlimit, left(rolpassword,13) from pg_authid where rolname like '<svc>%'" \
  -c "select rolname from pg_roles where rolcanlogin and rolbypassrls" \
  -c "select line_number, database, user_name, auth_method from pg_hba_file_rules order by 1"
```

Đạt khi: role LOGIN có `SCRAM-SHA-256` và `rolconnlimit` > 0; role LOGIN có `BYPASSRLS` chỉ có `postgres`; dòng mới đứng trước dòng `reject`.

Đăng nhập thật (mật khẩu đọc từ Secret qua stdin, không in ra):

```bash
kubectl get secret -n postgres pg-main-<role-có-gạch-ngang> -o jsonpath='{.data.password}' | base64 -d \
  | kubectl exec -i -n postgres "$P" -c postgres -- sh -c 'read -r PGPASSWORD; export PGPASSWORD
    psql -X "host=pg-main-rw user=<role> dbname=<db> sslmode=require" -Atc "select current_user, current_database()"
    psql -X "host=pg-main-rw user=<role> dbname=hello sslmode=require" -Atc "select 1"'
```

Đạt khi: lệnh đầu trả `<role>|<db>`; lệnh sau (database của service khác) bị `pg_hba.conf rejects connection`. Biến thể A: thêm `CREATE TABLE x()` bằng `<svc>_app` qua `pg-main-pooler-rw` phải `permission denied for schema public`. Biến thể B: role tự `create table` và `drop table` được trong database của nó.

## Đưa mật khẩu sang namespace của service

Service đọc mật khẩu từ Secret trong namespace của nó. Seal bản sao từ Secret trong cụm, plaintext chỉ đi qua pipe (scope `strict` gắn tên và namespace vào ciphertext, nên phải seal lại chứ không chép được file):

```bash
kubectl get secret -n postgres pg-main-<role-có-gạch-ngang> -o json \
  | jq '{apiVersion: "v1", kind: "Secret", type, metadata: {name: "<tên-ở-service>", namespace: "<ns-service>"}, data}' \
  | kubeseal --format yaml > <đường-dẫn-trong-chart-hoặc-app-của-service>.sealedsecret.yaml
```

Đã thử pipeline (không ghi file) ngày 2026-11-15: ra SealedSecret đúng tên, namespace, `kubernetes.io/basic-auth`. Ticket 10 (Keycloak, `spec.db.usernameSecret`/`passwordSecret`) dùng dạng file này.

**Service dùng chart `app`** (từ 0.3.0, dùng thật ở [G0-27](../.scratch/g0-platform/issues/27-hello-pg-main-presync.md) ngày 2026-11-25): bản sao nằm trong `envs/lab/<svc>/values.yaml` dưới `sealedSecrets.<tên>.encryptedData`, không phải file riêng. Lấy riêng `encryptedData` rồi dán vào values:

```bash
seal_copy() {  # $1 Secret ở postgres, $2 tên ở service, $3 namespace service
  kubectl get secret -n postgres "$1" -o json   | jq --arg n "$2" --arg ns "$3" '{apiVersion: "v1", kind: "Secret", type, metadata: {name: $n, namespace: $ns}, data}'   | kubeseal --format yaml | yq '.spec.encryptedData'
}
seal_copy pg-main-hello-app hello-db-app hello
```

Quy ước tên ở service: `<svc>-db-app` (runtime, SealedSecret thường) và `<svc>-db-migrator` (Job migrate, `preSync: true`). Kiểm trước khi push, không cần đụng plaintext: render rồi `kubeseal --validate`:

```bash
helm template <svc> oci://ghcr.io/hoangduoc0603/charts/app --version 0.3.0 -n <svc> -f envs/lab/<svc>/values.yaml -s templates/sealedsecret.yaml   | yq 'select(.metadata.name == "<svc>-db-app") | .metadata.namespace = "<svc>"' | kubeseal --validate
```

Sau sync, so bản sao bằng **hash**, không so nội dung: `diff` in nguyên `.data` (có password base64) khi một bên chưa tồn tại, đã xảy ra ở G0-27.

```bash
[ "$(kubectl -n postgres get secret pg-main-hello-app -o jsonpath='{.data}' | shasum -a 256)" = "$(kubectl -n hello get secret hello-db-app -o jsonpath='{.data}' | shasum -a 256)" ] && echo khớp
```

## Đổi mật khẩu

Một role PostgreSQL chỉ có một mật khẩu, nên bản ở `postgres` và bản ở namespace service phải đổi **trong cùng commit**. Nếu tách hai commit (seal bản sao từ Secret trong cụm như mục trên), thì giữa hai lần sync, role đã mang mật khẩu mới mà service vẫn dùng mật khẩu cũ, nên mọi kết nối mới bị `password authentication failed`.

Cách đề xuất: sinh mật khẩu một lần, dùng `tee` chia cho hai lệnh `kubeseal`; plaintext chỉ đi qua pipe:

```bash
seal() {  # $1 tên Secret, $2 namespace, $3 username
  kubectl create secret generic "$1" -n "$2" --type=kubernetes.io/basic-auth --from-literal=username="$3" \
    --from-file=password=/dev/stdin --dry-run=client -o yaml \
  | kubectl label --local -f - cnpg.io/reload=true -o yaml | kubeseal --format yaml
}
openssl rand -hex 32 | tr -d '\n' \
  | tee >(seal pg-main-<role-có-gạch-ngang> postgres <role> > infra/pg-main/pg-main-<role-có-gạch-ngang>.sealedsecret.yaml) \
  | seal <tên-ở-service> <ns-service> <role> > <đường-dẫn-bản-sao>.sealedsecret.yaml
```

Service dùng chart `app` thì bản sao không phải file mà là `encryptedData` trong values: thay vế sau của `tee` bằng `| seal <svc>-db-app <ns-service> <role> | yq '.spec.encryptedData'`, dán vào `sealedSecrets.<svc>-db-app.encryptedData` và tăng `secretRevision` (pod phải khởi động lại mới đọc Secret mới). Bản sao không cần nhãn `cnpg.io/reload` nhưng có cũng vô hại.

Sau đó thêm lại annotation wave và header cho file ở `postgres` (như mục 2), rồi commit cả hai file cùng lúc. Pod service đang giữ kết nối cũ vẫn chạy (PostgreSQL chỉ kiểm mật khẩu lúc nối); restart pod để chắc mật khẩu mới dùng được.

**Chưa diễn tập**, kể cả lệnh `tee` ở trên: thử ở lần đổi mật khẩu đầu tiên khi đã có service thật, rồi sửa mục này theo kết quả.

## Gỡ service

1. Xóa file `<svc>.yaml`, các SealedSecret, dòng `pg_hba` và dòng kustomization trong một commit. Argo prune CR; vì `retain`, role và database vẫn còn trong PostgreSQL. Dòng `pg_hba` mất nên không ai đăng nhập được nữa.
2. Cắt phiên còn mở (siết `pg_hba` không cắt phiên cũ): `select pg_terminate_backend(pid) from pg_stat_activity where datname = '<db>'`.
3. Sau khi có backup (G0-09), xóa hẳn trong pod: `kubectl exec -it -n postgres "$P" -c postgres -- psql` rồi `DROP DATABASE <db>;` và `DROP ROLE ...` cho từng role.

Chưa diễn tập.

## Sự cố thường gặp

| Triệu chứng | Nguyên nhân hay gặp | Xử lý |
|---|---|---|
| App `pg-main` kẹt `Progressing`, không đỏ | `DatabaseRole`/`Database` lỗi (role trong `inRoles` hay `owner` sai tên, Secret thiếu). Health check coi `applied=false` khi generation chưa từng áp thành công là Progressing | `kubectl get databaserole,database -n postgres`, đọc cột `MESSAGE` |
| `pg_hba.conf rejects connection ... SSL encryption` | Thiếu dòng `pg_hba` cho cặp database × role, hoặc dòng nằm dưới `reject` | Xem `pg_hba_file_rules`, sửa `cluster.yaml` |
| `pg_hba.conf rejects connection ... no encryption` | Client tắt TLS (`sslmode=disable`, một số GUI mặc định) | Đặt `sslmode=prefer` hoặc `require` |
| `FATAL: SSL required` khi nối Pooler | Như trên, ở chặng Pooler (`client_tls_sslmode: require`) | Như trên |
| `too many connections for role "<role>"` | Pool của ứng dụng lớn hơn `connectionLimit`, hoặc Pooler lên 2 pod mà chưa nhân đôi giới hạn `_app` | Cho pool ứng dụng ≤ `connectionLimit`; xem lại ngân sách mục 1 |
| `password authentication failed` sau khi đổi mật khẩu | Bản sao ở namespace service chưa seal lại, hoặc Secret ở `postgres` thiếu nhãn `cnpg.io/reload` | Kiểm nhãn; seal lại bản sao |
| Siết `pg_hba` rồi mà phiên cũ vẫn vào database bị cấm | `pg_hba` chỉ xét lúc thiết lập kết nối | `pg_terminate_backend` các phiên vi phạm |

Lưu ý: Pooler không giới hạn role nào được dùng nó (ngày 2026-11-15 `keycloak` qua `pg-main-pooler-rw` vẫn vào được database `keycloak`). "Keycloak và Job Flyway nối thẳng `pg-main-rw`" là quy ước cấu hình của ứng dụng; ranh giới thật là `pg_hba` và quyền của role.
