#!/usr/bin/env bash
set -euo pipefail

: "${GH_TOKEN:?GH_TOKEN nao informado}"

environment="${1:-homolog}"
shift || true

for repo in "$@"; do
  if ! gh api "repos/${repo}/environments/${environment}" >/dev/null 2>&1; then
    echo "Environment ausente: ${repo}/${environment}"
    exit 1
  fi
  echo "Environment encontrado: ${repo}/${environment}"
done
