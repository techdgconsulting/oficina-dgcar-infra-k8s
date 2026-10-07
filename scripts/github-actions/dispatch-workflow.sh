#!/usr/bin/env bash
set -euo pipefail

repo="${1:?repo nao informado}"
workflow="${2:?workflow nao informado}"
ref="${3:?ref nao informado}"
shift 3

: "${GH_TOKEN:?GH_TOKEN nao informado}"

marker_file=".workflow-marker-${repo//\//-}-${workflow}.txt"
gh run list \
  --repo "$repo" \
  --workflow "$workflow" \
  --branch "$ref" \
  --limit 50 \
  --json databaseId \
  --jq '.[].databaseId' > "$marker_file"

gh workflow run "$workflow" \
  --repo "$repo" \
  --ref "$ref" \
  "$@"

echo "Workflow enviado: $repo/$workflow"
echo "Marcador gravado em: $marker_file"
