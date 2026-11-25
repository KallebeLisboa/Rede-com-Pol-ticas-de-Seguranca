#!/bin/bash
# =============================================================================
# Modulo 4 - Testes do firewall (executar NO HOST, na raiz do projeto)
#
#   bash testes/testar_modulo4.sh
#
# Fase 1: firewall desligado (cenario sem protecao)
# Fase 2: firewall ligado + captura tcpdump no gateway
# Fase 3: coleta de evidencias (contadores e logs de bloqueio)
#
# Saida completa em testes/evidencia_modulo4.txt
# Classificacao de cada teste:
#   ABERTA    -> conexao estabelecida
#   RECUSADA  -> o destino respondeu RST (o firewall deixou passar, mas nao ha servico)
#   BLOQUEADA -> nenhuma resposta (timeout): pacote descartado pelo firewall
# =============================================================================

cd "$(dirname "$0")/.." || exit 1
SAIDA="testes/evidencia_modulo4.txt"
exec > >(tee "$SAIDA") 2>&1

SERVIDOR_WEB=172.21.0.10
APP=172.21.0.20
GATEWAY=172.20.0.2
CLIENTE=172.20.0.10
PORTA_REVERSA=4444
FALHAS=0

titulo() { printf "\n==================== %s ====================\n" "$1"; }

# Testa uma conexao TCP a partir de um conteiner -> ABERTA | RECUSADA | BLOQUEADA
# tcp     <conteiner> <ip> <porta>  usa netcat (cliente, Alpine)
# tcp_py  <conteiner> <ip> <porta>  usa Python (app_python, sem netcat)
tcp() {
    docker exec "$1" sh -c "
        out=\$(nc -zv -w 3 $2 $3 2>&1); rc=\$?
        if [ \$rc -eq 0 ]; then echo ABERTA
        elif echo \"\$out\" | grep -qi refused; then echo RECUSADA
        else echo BLOQUEADA; fi"
}

tcp_py() {
    docker exec -i "$1" python3 - "$2" "$3" <<'EOF'
import socket, sys
s = socket.socket(); s.settimeout(3)
try:
    s.connect((sys.argv[1], int(sys.argv[2]))); print("ABERTA")
except ConnectionRefusedError:
    print("RECUSADA")
except OSError:
    print("BLOQUEADA")
EOF
}

# Uso: verifica "<descricao>" <esperado> <obtido>
verifica() {
    if [ "$2" = "$3" ]; then marca="OK  "; else marca="FALHA"; FALHAS=$((FALHAS + 1)); fi
    printf "[%s] %-58s esperado=%-9s obtido=%s\n" "$marca" "$1" "$2" "$3"
}

http_code() { docker exec cliente curl -s -m 3 -o /dev/null -w "%{http_code}" "$@"; }

ping_ok() {
    if docker exec cliente ping -c 2 -W 2 "$1" >/dev/null 2>&1; then echo RESPONDE; else echo SEM_RESPOSTA; fi
}

bateria() {
    verifica "Cliente -> Nginx HTTP :80 (codigo HTTP)" "$1" "$(http_code http://$SERVIDOR_WEB/)"
    verifica "Cliente -> Nginx HTTPS :443" "$2" "$(tcp cliente $SERVIDOR_WEB 443)"
    verifica "Cliente -> ping no servidor web" "$3" "$(ping_ok $SERVIDOR_WEB)"
    verifica "Cliente -> API direta :8000 (contorna o proxy)" "$4" "$(tcp cliente $APP 8000)"
    verifica "Cliente -> SSH :22 no servidor web" "$5" "$(tcp cliente $SERVIDOR_WEB 22)"
    verifica "Cliente -> MySQL :3306 no servidor web" "$6" "$(tcp cliente $SERVIDOR_WEB 3306)"
    verifica "Cliente -> SSH :22 no proprio gateway" "$7" "$(tcp cliente $GATEWAY 22)"
    verifica "Servidor (app) -> cliente :$PORTA_REVERSA (reverse shell)" "$8" "$(tcp_py app_python $CLIENTE $PORTA_REVERSA)"
}

echo "Modulo 4 - Firewall, controle de acesso e monitoramento"
echo "Data: $(date '+%d/%m/%Y %H:%M:%S')"

# Listener no cliente para simular o destino de um reverse shell
docker exec -d cliente sh -c "nc -lk -p $PORTA_REVERSA >/dev/null 2>&1"
sleep 1

# ----------------------------------------------------------------------------
titulo "FASE 1: SEM FIREWALL (cenario nao protegido)"
docker exec gateway sh /firewall.sh limpar
#         http  https     ping      api8000  ssh22     mysql     gw22      reverso
bateria   200   RECUSADA  RESPONDE  ABERTA   RECUSADA  RECUSADA  RECUSADA  ABERTA

# ----------------------------------------------------------------------------
titulo "FASE 2: COM FIREWALL (politica aplicada)"
docker exec gateway sh /firewall.sh aplicar
LINHAS_LOG=$(docker exec gateway sh -c 'wc -l < /var/log/firewall/firewall.log')

docker exec -d gateway tcpdump -i any -nn -U -w /capturas/modulo4_firewall.pcap \
    "net 172.20.0.0/24 or net 172.21.0.0/24"
sleep 2

#         http  https     ping      api8000    ssh22      mysql      gw22       reverso
bateria   200   RECUSADA  RESPONDE  BLOQUEADA  BLOQUEADA  BLOQUEADA  BLOQUEADA  BLOQUEADA

TOKEN=$(docker exec cliente curl -s -m 3 -X POST http://$SERVIDOR_WEB/login \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"Admin@2026"}' | docker exec -i cliente jq -r .access_token)
if [ -n "$TOKEN" ] && [ "$TOKEN" != "null" ]; then OBTIDO=200; else OBTIDO=falhou; fi
verifica "Login do Modulo 3 via proxy continua funcionando" 200 "$OBTIDO"

sleep 1
docker exec gateway pkill tcpdump
echo
echo "Observacao: HTTPS :443 e liberado pelo firewall; RECUSADA significa que o"
echo "Nginx ainda nao escuta na 443 (certificados do Modulo 2), nao um bloqueio."

# ----------------------------------------------------------------------------
titulo "FASE 3: EVIDENCIAS"
echo "--- Regras e contadores do firewall ---"
docker exec gateway sh /firewall.sh status
echo
echo "--- Registros de bloqueio gerados nesta execucao (logs/firewall.log) ---"
docker exec gateway sh -c "tail -n +$((LINHAS_LOG + 1)) /var/log/firewall/firewall.log"
echo
echo "--- Captura de pacotes ---"
echo "capturas/modulo4_firewall.pcap (abrir no Wireshark; filtro sugerido: tcp.flags.syn==1)"

docker exec cliente pkill -f "nc -lk -p $PORTA_REVERSA" 2>/dev/null

titulo "RESULTADO"
if [ "$FALHAS" -eq 0 ]; then
    echo "Todos os testes se comportaram como esperado."
else
    echo "$FALHAS teste(s) com resultado diferente do esperado."
fi
exit "$FALHAS"
