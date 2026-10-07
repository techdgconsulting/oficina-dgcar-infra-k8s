#!/usr/bin/env bash
set -euo pipefail

repo="${1:?repo nao informado}"
workflow="${2:?workflow nao informado}"
ref="${3:?ref nao informado}"

: "${GH_TOKEN:?GH_TOKEN nao informado}"

marker_file=".workflow-marker-${repo//\//-}-${workflow}.txt"
marker="0"
if [ -f "$marker_file" ]; then
  marker="$(cat "$marker_file")"
fi

run_id=""

for attempt in $(seq 1 60); do
  run_id="$(gh run list \
    --repo "$repo" \
    --workflow "$workflow" \
    --branch "$ref" \
    --limit 10 \
    --json databaseId \
    --jq "[.[] | select(.databaseId > ${marker})][0].databaseId // empty")"

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
