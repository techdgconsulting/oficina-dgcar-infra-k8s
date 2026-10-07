#!/usr/bin/env bash
set -euo pipefail

: "${GATEWAY_BASE_URL:?GATEWAY_BASE_URL nao informado}"
: "${CLIENT_TEST_CPF:?CLIENT_TEST_CPF nao informado}"
: "${CLIENT_TEST_PASSWORD:?CLIENT_TEST_PASSWORD nao informado}"
: "${CLIENT_TEST_OS_NUMBER:?CLIENT_TEST_OS_NUMBER nao informado}"
: "${CLIENT_OTHER_OS_NUMBER:?CLIENT_OTHER_OS_NUMBER nao informado}"

auth_response="$(curl -sS -X POST "${GATEWAY_BASE_URL}/auth/cpf" \
  -H 'Content-Type: application/json' \
  -d "{\"cpf\":\"${CLIENT_TEST_CPF}\",\"senha\":\"${CLIENT_TEST_PASSWORD}\"}")"

access_token="$(printf '%s' "$auth_response" | jq -r '.accessToken // empty')"

if [ -z "$access_token" ]; then
  echo "Autenticacao nao retornou accessToken."
  echo "$auth_response"
  exit 1
fi

jwt_type="$(TOKEN="$access_token" python -c "import base64,json,os; p=os.environ['TOKEN'].split('.')[1]; p += '=' * (-len(p) % 4); print(json.loads(base64.urlsafe_b64decode(p)).get('tipo',''))")"

if [ "$jwt_type" != "CLIENTE" ]; then
  echo "JWT externo nao possui tipo=CLIENTE."
  exit 1
fi

status_code="$(curl -sS -o /tmp/os.json -w '%{http_code}' \
  -H "Authorization: Bearer ${access_token}" \
  "${GATEWAY_BASE_URL}/api/ordens-servico/numero/${CLIENT_TEST_OS_NUMBER}")"

if [ "$status_code" != "200" ]; then
  echo "Consulta de OS com token retornou $status_code."
  cat /tmp/os.json
  exit 1
fi

status_code="$(curl -sS -o /tmp/os-sem-token.json -w '%{http_code}' \
  "${GATEWAY_BASE_URL}/api/ordens-servico/numero/${CLIENT_TEST_OS_NUMBER}")"

if [ "$status_code" != "401" ]; then
  echo "Consulta sem token retornou $status_code; esperado 401."
  cat /tmp/os-sem-token.json
  exit 1
fi

status_code="$(curl -sS -o /tmp/os-outro-cliente.json -w '%{http_code}' \
  -H "Authorization: Bearer ${access_token}" \
  "${GATEWAY_BASE_URL}/api/ordens-servico/numero/${CLIENT_OTHER_OS_NUMBER}")"

if [ "$status_code" != "403" ]; then
  echo "Consulta de OS de outro cliente retornou $status_code; esperado 403."
  cat /tmp/os-outro-cliente.json
  exit 1
fi

status_code="$(curl -sS -o /tmp/abrir-os-cliente.json -w '%{http_code}' \
  -X POST "${GATEWAY_BASE_URL}/api/ordens-servico/completa" \
  -H "Authorization: Bearer ${access_token}" \
  -H 'Content-Type: application/json' \
  -d '{}')"

if [ "$status_code" != "403" ]; then
  echo "Abertura de OS com JWT de cliente retornou $status_code; esperado 403."
  cat /tmp/abrir-os-cliente.json
  exit 1
fi

echo "Smoke tests concluidos."
