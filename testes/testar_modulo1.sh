#!/bin/sh
set -e

PCAP_CONTAINER="/capturas/modulo1_http.pcap"
PCAP_HOST="capturas/modulo1_http.pcap"
EVIDENCIA_TXT="testes/evidencia_modulo1_analise.txt"
URL="http://172.31.0.10"

echo "=== [MODULO 1] Iniciando captura HTTP (porta 80) no gateway ==="
docker exec -d gateway tcpdump -i any -U -s 0 -w "$PCAP_CONTAINER" "host 172.31.0.10 and port 80"
sleep 1

echo "=== [MODULO 1] Gerando trafego HTTP em texto claro a partir do cliente ==="

echo "1. GET / (area publica)"
docker exec cliente curl -s -i "$URL/" > /dev/null

echo "2. POST /login (enviando credenciais em texto claro)"
LOGIN_RESP=$(docker exec cliente curl -s -X POST "$URL/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"admin","password":"Admin@2026"}')
TOKEN=$(echo "$LOGIN_RESP" | docker exec -i cliente jq -r '.access_token')

echo "3. GET /protegido (enviando Bearer Token e recebendo dados confidenciais)"
docker exec cliente curl -s -i "$URL/protegido" \
  -H "Authorization: Bearer $TOKEN" > /dev/null

echo "4. POST /mensagem/assinar (enviando payload sensivel sem criptografia)"
docker exec cliente curl -s -X POST "$URL/mensagem/assinar" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"mensagem":"Transferencia confidencial de R$ 15.000,00 - Conta 0042"}' > /dev/null

sleep 1
echo "=== [MODULO 1] Encerrando captura no gateway ==="
docker exec gateway sh -c 'kill -INT $(pidof tcpdump) 2>/dev/null || true'
sleep 1

echo "=== [MODULO 1] Extraindo evidencias em texto claro do .pcap ==="
{
  echo "============================================================"
  echo "EVIDENCIA MODULO 1 - ANALISE DE TRAFEGO HTTP (TEXTO CLARO)"
  echo "Arquivo PCAP: $PCAP_HOST"
  echo "============================================================"
  echo ""
  echo "--- 1. Cabecalhos HTTP e rotas expostas ---"
  docker exec gateway tcpdump -r "$PCAP_CONTAINER" -A -n 2>/dev/null \
    | grep -E "^(GET|POST|HTTP/1\.1|Host:|User-Agent:|Authorization:|Content-Type:)" \
    | sort -u
  echo ""
  echo "--- 2. Credenciais e dados sensiveis capturados em texto claro ---"
  docker exec gateway tcpdump -r "$PCAP_CONTAINER" -A -n 2>/dev/null \
    | grep -E "Admin@2026|access_token|dados_confidenciais|Transferencia confidencial" \
    | sort -u
  echo ""
  echo "--- 3. Resumo de pacotes capturados ---"
  docker exec gateway tcpdump -r "$PCAP_CONTAINER" -n 2>/dev/null | head -n 25
} > "$EVIDENCIA_TXT"

echo "Concluido!"
echo "  - Captura Wireshark: $PCAP_HOST"
echo "  - Resumo em texto:   $EVIDENCIA_TXT"