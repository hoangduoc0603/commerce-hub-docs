#!/usr/bin/env bash
# Đo lead time deploy hello qua GitOps (G0-24 bước 6). Mỗi lần: commit rỗng → push → chờ run CI → chờ commit gitops
# của bot → chờ Argo CD sync → chờ pod Ready với đúng digest. Lần sau chỉ push khi lần trước đã xong.
# Mốc lấy từ nguồn gốc: job GitHub (startedAt/completedAt), commit gitops (committer date), history Argo CD
# (deployedAt), điều kiện Ready của pod. Chỉ mốc push là giờ máy.
set -euo pipefail
ROOT=/Users/hoangduoc/Desktop/sys-craft/lab/commerce-hub
R=hoangduoc0603/commerce-hub-hello
N=${1:-3}
iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ; }
sec() { date -u -j -f %Y-%m-%dT%H:%M:%SZ "$1" +%s; }

echo "lan|sha|push|check_done|ghcr|gitops_commit|argo_sync|pod_ready|push→check|check→ghcr|ghcr→gitops|gitops→sync|sync→ready|tong"
for i in $(seq 1 "$N"); do
  if [ "$i" = 1 ] && [ -n "${FIRST_SHA:-}" ]; then
    # Lần 1 đã push ở lần chạy trước: mốc push lấy theo giờ commit (push ngay sau commit, lệch ~1 s).
    sha=$(git -C "$ROOT/services/hello" rev-parse "$FIRST_SHA")
    push=$(git -C "$ROOT/services/hello" show -s --format=%ct "$sha")
  else
    git -C "$ROOT/services/hello" commit -q --allow-empty -m "chore: đo lead time deploy, lần $i (G0-24 bước 6)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
    sha=$(git -C "$ROOT/services/hello" rev-parse HEAD)
    push=$(date -u +%s)
    git -C "$ROOT/services/hello" push -q origin main
  fi

  run=""
  until [ -n "$run" ]; do sleep 5; run=$(gh run list -R $R -c "$sha" --json databaseId --jq '.[0].databaseId // empty'); done
  # Hỏi trạng thái tới khi completed (gh run watch đã trả về sớm khi run còn đang chạy).
  until [ "$(gh run view "$run" -R $R --json status --jq .status 2>/dev/null)" = completed ]; do sleep 15; done
  [ "$(gh run view "$run" -R $R --json conclusion --jq .conclusion)" = success ] || { echo "lần $i: run $run không success" >&2; exit 1; }
  jobs=$(gh run view "$run" -R $R --json jobs)
  check=$(jq -r '.jobs[] | select(.name=="ci / check") | .completedAt' <<<"$jobs")
  ghcr=$(jq -r '.jobs[] | select(.name=="ci / image / publish") | .completedAt' <<<"$jobs")

  # Trạng thái run có lúc báo completed khi job của workflow lồng còn chạy: chờ chính commit gitops (tối đa 10 phút).
  gsha=""
  for _ in $(seq 1 60); do
    git -C "$ROOT/gitops" pull -q --ff-only
    gsha=$(git -C "$ROOT/gitops" log -1 --format=%H --grep="Nguồn: $R@$sha")
    [ -n "$gsha" ] && break
    sleep 10
  done
  [ -n "$gsha" ] || { echo "lần $i: không thấy commit gitops cho $sha" >&2; exit 1; }
  jobs=$(gh run view "$run" -R $R --json jobs)
  check=$(jq -r '.jobs[] | select(.name=="ci / check") | .completedAt' <<<"$jobs")
  ghcr=$(jq -r '.jobs[] | select(.name=="ci / image / publish") | .completedAt' <<<"$jobs")
  gepoch=$(git -C "$ROOT/gitops" show -s --format=%ct "$gsha"); gtime=$(iso "$gepoch")
  digest=$(git -C "$ROOT/gitops" show -s --format=%B "$gsha" | sed -n 's/^Image: //p')

  sync=""
  until [ -n "$sync" ]; do
    sleep 3
    sync=$(kubectl -n argocd get app svc-hello -o json --request-timeout=5s 2>/dev/null \
      | jq -r --arg g "$gsha" '[.status.history[]? | select(.revisions[1]==$g) | .deployedAt][0] // empty')
  done
  ready=""
  until [ -n "$ready" ]; do
    sleep 2
    ready=$(kubectl -n hello get pod -l app.kubernetes.io/name=hello -o json --request-timeout=5s 2>/dev/null \
      | jq -r --arg d "$digest" '[.items[] | select(.status.containerStatuses[0].imageID | endswith($d))
          | .status.conditions[]? | select(.type=="Ready" and .status=="True") | .lastTransitionTime][0] // empty')
  done

  p=$push c=$(sec "$check") g=$(sec "$ghcr") o=$(sec "$gtime") s=$(sec "$sync") r=$(sec "$ready")
  echo "$i|${sha:0:7}|$(iso "$p")|$check|$ghcr|$gtime|$sync|$ready|$((c-p))|$((g-c))|$((o-g))|$((s-o))|$((r-s))|$((r-p))"
  sleep 20
done
