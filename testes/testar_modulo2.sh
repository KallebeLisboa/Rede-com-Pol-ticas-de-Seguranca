#!/bin/bash
# =============================================================================
# Modulo 2 - Testes de HTTPS/TLS (executar NO HOST, na raiz do projeto)
#
#   bash testes/testar_modulo2.sh
#
# Pre-requisitos:
#   bash nginx/gerar_certificados.sh
#   docker compose up -d --build
#
# Saida completa em testes/evidencia_modulo2_tls.txt
# =============================================================================

cd "$(dirname "$0")/.." || exit 1
SAIDA="testes/evidencia_modulo2_tls.txt"
exec > >(tee "$SAIDA") 2>&1

SERVIDOR_WEB=172.31.0.10
URL="https://$SERVIDOR_WEB"
CA=/certs/ca.crt
FALHAS=0

titulo() { printf "\n==================== %s ====================\n" "$1"; }

# Uso: verifica "<descricao>" <0|1 condicao-ok>
verifica() {
    if [ "$2" = "1" ]; then marca="OK  "; else marca="FALHA"; FALHAS=$((FALHAS + 1)); fi
    printf "[%s] %s\n" "$marca" "$1"
}

contem() { echo "$1" | grep -qiE "$2" && echo 1 || echo 0; }

echo "Modulo 2 - Servidor Web, Criptografia e HTTPS/TLS"
echo "Data: $(date '+%d/%m/%Y %H:%M:%S')"

# ----------------------------------------------------------------------------
titulo "PRE-CONDICOES"
if [ ! -f nginx/certs/ca.crt ] || [ ! -f nginx/certs/server.crt ]; then
    echo "[FALHA] Certificados ausentes. Execute: bash nginx/gerar_certificados.sh"
    exit 1
fi
for c in cliente servidor_web gateway; do
    if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" != "true" ]; then
        echo "[FALHA] Conteiner '$c' nao esta em execucao. Execute: docker compose up -d --build"
        exit 1
    fi
done
echo "--- Validacao da cadeia no host ---"
openssl verify -CAfile nginx/certs/ca.crt nginx/certs/server.crt
echo "--- Configuracao do Nginx ---"
docker exec servidor_web nginx -t 2>&1

# ----------------------------------------------------------------------------
titulo "TESTE 1: curl --cacert (validacao da cadeia pela CA do laboratorio)"
SAIDA1=$(docker exec cliente curl -sv -m 5 --cacert $CA -o /dev/null -w "HTTP_CODE=%{http_code}\n" "$URL/" 2>&1)
echo "$SAIDA1" | grep -E "SSL connection|TLSv|subject:|issuer:|SSL certificate verify|HTTP_CODE"
verifica "Handshake TLS concluido e certificado verificado" "$(contem "$SAIDA1" "SSL certificate verify ok")"
verifica "API respondeu 200 por HTTPS" "$(contem "$SAIDA1" "HTTP_CODE=200")"

# ----------------------------------------------------------------------------
titulo "TESTE 2: curl SEM --cacert (a CA nao e confiavel: deve falhar)"
SAIDA2=$(docker exec cliente curl -sv -m 5 -o /dev/null "$URL/" 2>&1)
RC2=$?
echo "$SAIDA2" | grep -iE "certificate|SSL|verify" | head -n 6
verifica "Conexao rejeitada por falta de CA confiavel" \
    "$(contem "$SAIDA2" "unable to get local issuer certificate|self.signed|SSL certificate problem")"

# ----------------------------------------------------------------------------
titulo "TESTE 3: curl -k (sem validacao, apenas para contraste)"
CODIGO3=$(docker exec cliente curl -sk -m 5 -o /dev/null -w "%{http_code}" "$URL/")
echo "Codigo HTTP com -k: $CODIGO3 (a conexao e cifrada, mas sem garantia de identidade)"
verifica "curl -k conecta sem validar o certificado" "$([ "$CODIGO3" = "200" ] && echo 1 || echo 0)"

# ----------------------------------------------------------------------------
titulo "TESTE 4: openssl s_client (protocolo, cipher suite, cadeia e SAN)"
SCLIENT=$(docker exec cliente sh -c "echo | openssl s_client -connect $SERVIDOR_WEB:443 \
    -CAfile $CA -servername servidor.local 2>&1")
echo "$SCLIENT" | grep -E "Protocol|Cipher|subject=|issuer=|Verify return code|Verification|^ *[0-9] s:|^ *i:" | head -n 15
echo
echo "--- Certificado do servidor (SAN, validade, restricoes) ---"
docker exec cliente sh -c "echo | openssl s_client -connect $SERVIDOR_WEB:443 -CAfile $CA \
    -servername servidor.local 2>/dev/null | openssl x509 -noout -subject -issuer -dates \
    -ext subjectAltName,basicConstraints,keyUsage,extendedKeyUsage 2>&1"
verifica "Verify return code: 0 (ok)" "$(contem "$SCLIENT" "Verify return code: 0 \(ok\)")"
verifica "Protocolo negociado e TLSv1.3 ou TLSv1.2" "$(contem "$SCLIENT" "(Protocol *: *TLSv1\.[23]|New, TLSv1\.[23])")"
SAN=$(docker exec cliente sh -c "echo | openssl s_client -connect $SERVIDOR_WEB:443 -CAfile $CA \
    -servername servidor.local 2>/dev/null | openssl x509 -noout -ext subjectAltName 2>&1")
verifica "SAN contem o IP $SERVIDOR_WEB e DNS servidor.local" \
    "$([ "$(contem "$SAN" "IP Address:$SERVIDOR_WEB")" = 1 ] && [ "$(contem "$SAN" "DNS:servidor.local")" = 1 ] && echo 1 || echo 0)"

# ----------------------------------------------------------------------------
titulo "TESTE 5: versoes antigas de TLS (devem ser recusadas)"
echo "--- curl --tlsv1.1 --tls-max 1.1 ---"
SAIDA5=$(docker exec cliente curl -sv -m 5 --cacert $CA --tlsv1.1 --tls-max 1.1 -o /dev/null "$URL/" 2>&1)
RC5=$?
echo "$SAIDA5" | grep -iE "alert|protocol|handshake|error|unsupported" | head -n 5
CODIGO5=$(docker exec cliente curl -s -m 5 --cacert $CA --tlsv1.1 --tls-max 1.1 -o /dev/null -w "%{http_code}" "$URL/" 2>/dev/null)
verifica "TLS 1.1 recusado pelo servidor (sem resposta HTTP)" "$([ "$CODIGO5" = "000" ] && echo 1 || echo 0)"

echo "--- openssl s_client -tls1_1 (SECLEVEL=0 para o cliente aceitar oferecer TLS 1.1) ---"
S11=$(docker exec cliente sh -c "echo | openssl s_client -connect $SERVIDOR_WEB:443 -tls1_1 -cipher 'DEFAULT:@SECLEVEL=0' 2>&1")
echo "$S11" | grep -iE "alert|error|unknown option|no protocols|Protocol" | head -n 4
if echo "$S11" | grep -qiE "unknown option|invalid command|no protocols available"; then
    echo "(openssl do cliente nao suporta -tls1_1; o resultado do curl acima e a evidencia)"
else
    verifica "Servidor enviou alerta 'protocol version' ao ClientHello TLS 1.1" "$(contem "$S11" "alert protocol version|alert number 70")"
fi

echo "--- curl --tlsv1.2 --tls-max 1.2 (deve funcionar) ---"
CODIGO5B=$(docker exec cliente curl -s -m 5 --cacert $CA --tlsv1.2 --tls-max 1.2 -o /dev/null -w "%{http_code}" "$URL/")
verifica "TLS 1.2 aceito (codigo $CODIGO5B)" "$([ "$CODIGO5B" = "200" ] && echo 1 || echo 0)"

# ----------------------------------------------------------------------------
titulo "TESTE 6: aplicacao sob TLS (POST /login e GET /protegido)"
LOGIN=$(docker exec cliente curl -s -m 5 --cacert $CA -X POST "$URL/login" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"Admin@2026"}')
TOKEN=$(echo "$LOGIN" | docker exec -i cliente jq -r '.access_token // empty' 2>/dev/null)
if [ -n "$TOKEN" ]; then
    echo "Token JWT obtido: ${TOKEN:0:30}..."
else
    echo "Resposta do login: $LOGIN"
fi
verifica "POST /login via HTTPS retornou access_token" "$([ -n "$TOKEN" ] && echo 1 || echo 0)"

PROT_CODE=$(docker exec cliente curl -s -m 5 --cacert $CA -o /tmp/protegido.json -w "%{http_code}" \
    "$URL/protegido" -H "Authorization: Bearer $TOKEN")
docker exec cliente cat /tmp/protegido.json 2>/dev/null; echo
verifica "GET /protegido com token via HTTPS (codigo $PROT_CODE)" "$([ "$PROT_CODE" = "200" ] && echo 1 || echo 0)"

SEM_TOKEN=$(docker exec cliente curl -s -m 5 --cacert $CA -o /dev/null -w "%{http_code}" "$URL/protegido")
verifica "GET /protegido sem token e negado (codigo $SEM_TOKEN)" "$([ "$SEM_TOKEN" = "401" ] || [ "$SEM_TOKEN" = "403" ] && echo 1 || echo 0)"

# ----------------------------------------------------------------------------
titulo "TESTE 7: HTTP :80 permanece disponivel (Modulo 1 depende dele)"
CODIGO7=$(docker exec cliente curl -s -m 5 -o /dev/null -w "%{http_code}" "http://$SERVIDOR_WEB/")
verifica "HTTP :80 sem redirecionamento (codigo $CODIGO7)" "$([ "$CODIGO7" = "200" ] && echo 1 || echo 0)"

# ----------------------------------------------------------------------------
titulo "RESULTADO"
if [ "$FALHAS" -eq 0 ]; then
    echo "Todos os testes do Modulo 2 passaram."
else
    echo "$FALHAS verificacao(oes) falharam."
fi
echo "Evidencia salva em $SAIDA"
exit "$FALHAS"
