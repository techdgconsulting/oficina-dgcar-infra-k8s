#!/usr/bin/env bash
set -euo pipefail

repo="${1:?repo nao informado}"
workflow="${2:?workflow nao informado}"
ref="${3:?ref nao informado}"
shift 3

: "${GH_TOKEN:?GH_TOKEN nao informado}"

marker="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

echo "$marker" > ".workflow-marker-${repo//\//-}-${workflow}.txt"

gh workflow run "$workflow" \
  --repo "$repo" \
  --ref "$ref" \
  "$@"

echo "Workflow enviado: $repo/$workflow"
echo "Marcador do disparo: $marker"
