#!/usr/bin/env bash
set -euo pipefail

repo="${1:?repo nao informado}"
workflow="${2:?workflow nao informado}"
ref="${3:?ref nao informado}"
shift 3

: "${GH_TOKEN:?GH_TOKEN nao informado}"

marker="$(gh run list \
  --repo "$repo" \
  --workflow "$workflow" \
  --branch "$ref" \
  --limit 1 \
  --json databaseId \
  --jq '.[0].databaseId // 0')"

echo "$marker" > ".workflow-marker-${repo//\//-}-${workflow}.txt"

gh workflow run "$workflow" \
  --repo "$repo" \
  --ref "$ref" \
  "$@"

echo "Workflow enviado: $repo/$workflow"
