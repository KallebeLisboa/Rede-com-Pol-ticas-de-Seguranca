#!/bin/sh
set -e

PCAP_CONTAINER="/capturas/modulo2_https.pcap"
PCAP_HOST="capturas/modulo2_https.pcap"
EVIDENCIA_TXT="testes/evidencia_modulo2_comparacao.txt"
URL="https://172.21.0.10"

CA_ARG="-k"
if [ -f "nginx/certs/ca.crt" ]; then
  CA_ARG="--cacert /certs/ca.crt"
fi

echo "=== [MODULO 2] Iniciando captura HTTPS (porta 443) no gateway ==="
docker exec -d gateway tcpdump -i any -U -s 0 -w "$PCAP_CONTAINER" "host 172.21.0.10 and port 443"
sleep 1

echo "=== [MODULO 2] Gerando trafego HTTPS cifrado a partir do cliente ==="
LOGIN_RESP=$(docker exec cliente curl -s $CA_ARG -X POST "$URL/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"Admin@2026"}')
TOKEN=$(echo "$LOGIN_RESP" | docker exec -i cliente jq -r '.access_token')

docker exec cliente curl -s $CA_ARG "$URL/protegido" \
  -H "Authorization: Bearer $TOKEN" > /dev/null

sleep 1
echo "=== [MODULO 2] Encerrando captura no gateway ==="
docker exec gateway sh -c 'kill -INT $(pidof tcpdump) 2>/dev/null || true'
sleep 1

echo "=== [MODULO 2] Verificando se dados sensiveis aparecem em texto claro ==="
{
  echo "============================================================"
  echo "EVIDENCIA MODULO 2 - VERIFICACAO DE TRAFEGO HTTPS (CIFRADO)"
  echo "Arquivo PCAP: $PCAP_HOST"
  echo "============================================================"
  echo ""
  echo "--- Busca por dados sensiveis em texto claro no PCAP (deve ser vazia) ---"
  ACHADOS=$(docker exec gateway tcpdump -r "$PCAP_CONTAINER" -A -n 2>/dev/null \
    | grep -E "Admin@2026|Authorization:|dados_confidenciais" || true)
  if [ -z "$ACHADOS" ]; then
    echo "[OK] Nenhum dado sensivel encontrado em texto claro na captura TLS."
  else
    echo "[ALERTA] Dados encontrados:"
    echo "$ACHADOS"
  fi
  echo ""
  echo "--- Primeiros pacotes TLS capturados ---"
  docker exec gateway tcpdump -r "$PCAP_CONTAINER" -n 2>/dev/null | head -n 20
} > "$EVIDENCIA_TXT"

echo "Concluido!"
echo "  - Captura Wireshark: $PCAP_HOST"
echo "  - Verificacao:       $EVIDENCIA_TXT"