#!/usr/bin/env bash
set -euo pipefail

missing=()

for name in "$@"; do
  if [ -z "${!name:-}" ]; then
    missing+=("$name")
  fi
done

if [ "${#missing[@]}" -gt 0 ]; then
  printf 'Configuracao ausente: %s\n' "${missing[*]}"
  exit 1
fi

echo "Configuracao obrigatoria encontrada."
