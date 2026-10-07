#!/usr/bin/env bash
set -euo pipefail

repo="${1:?repo nao informado}"
workflow="${2:?workflow nao informado}"
ref="${3:?ref nao informado}"

: "${GH_TOKEN:?GH_TOKEN nao informado}"

marker_file=".workflow-marker-${repo//\//-}-${workflow}.txt"
marker="1970-01-01T00:00:00Z"
if [ -f "$marker_file" ]; then
  marker="$(cat "$marker_file")"
fi

run_id=""

for attempt in $(seq 1 60); do
  run_id="$(gh run list \
    --repo "$repo" \
    --workflow "$workflow" \
    --branch "$ref" \
    --limit 30 \
    --json databaseId,createdAt,event,status \
    --jq "[.[] | select(.event == \"workflow_dispatch\" and .createdAt >= \"${marker}\" and (.status == \"queued\" or .status == \"in_progress\"))][0].databaseId // empty")"

  if [ -z "$run_id" ]; then
    run_id="$(gh run list \
      --repo "$repo" \
      --workflow "$workflow" \
      --branch "$ref" \
      --limit 30 \
      --json databaseId,createdAt,event \
      --jq "[.[] | select(.event == \"workflow_dispatch\" and .createdAt >= \"${marker}\")][0].databaseId // empty")"
  fi

  if [ -n "$run_id" ]; then
    break
  fi

  echo "Aguardando inicio do workflow $repo/$workflow: tentativa $attempt/60"
  sleep 5
done

if [ -z "$run_id" ]; then
  echo "Workflow nao iniciou: $repo/$workflow"
  exit 1
fi

echo "Aguardando workflow $repo/$workflow run $run_id"
gh run watch "$run_id" --repo "$repo" --exit-status

conclusion="$(gh run view "$run_id" --repo "$repo" --json conclusion --jq '.conclusion')"
if [ "$conclusion" != "success" ]; then
  echo "Workflow falhou: $repo/$workflow conclusion=$conclusion"
  exit 1
fi

echo "Workflow concluido: $repo/$workflow"
