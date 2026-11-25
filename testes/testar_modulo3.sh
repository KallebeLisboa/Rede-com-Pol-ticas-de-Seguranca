#!/bin/sh
set -e

URL="http://172.31.0.10"

echo "=== 1. Teste de acesso NAO AUTORIZADO (sem token) ==="
curl -s -i "$URL/protegido"
printf "\n\n"

echo "=== 2. Teste de LOGIN INVALIDO (senha errada) ==="
curl -s -i -X POST "$URL/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"SenhaErrada"}'
printf "\n\n"

echo "=== 3. Teste de LOGIN VALIDO ==="
LOGIN_RESP=$(curl -s -X POST "$URL/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"Admin@2026"}')
echo "$LOGIN_RESP" | jq .
TOKEN=$(echo "$LOGIN_RESP" | jq -r '.access_token')
echo ""

echo "=== 4. Teste de acesso AUTORIZADO na area protegida ==="
curl -s -i "$URL/protegido" \
  -H "Authorization: Bearer $TOKEN"
printf "\n\n"

echo "=== 5. Gerando HMAC-SHA256 da mensagem original ==="
MSG_ORIGINAL="Autorizar pagamento de R$ 500,00 para fornecedor X"
SIGN_RESP=$(curl -s -X POST "$URL/mensagem/assinar" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"mensagem\":\"$MSG_ORIGINAL\"}")
echo "$SIGN_RESP" | jq .
HMAC_TAG=$(echo "$SIGN_RESP" | jq -r '.hmac')
echo ""

echo "=== 6. Verificando integridade ANTES da alteracao (deve retornar 200 OK) ==="
curl -s -i -X POST "$URL/mensagem/verificar" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"mensagem\":\"$MSG_ORIGINAL\",\"hmac_recebido\":\"$HMAC_TAG\"}"
printf "\n\n"

echo "=== 7. Verificando integridade DEPOIS de alterar a mensagem (deve retornar 400) ==="
MSG_ADULTERADA="Autorizar pagamento de R$ 50000,00 para fornecedor X"
curl -s -i -X POST "$URL/mensagem/verificar" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"mensagem\":\"$MSG_ADULTERADA\",\"hmac_recebido\":\"$HMAC_TAG\"}"
printf "\n\n"