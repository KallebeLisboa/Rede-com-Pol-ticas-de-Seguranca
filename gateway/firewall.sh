#!/bin/sh
# =============================================================================
# Modulo 4 - Firewall do gateway (iptables)
#
# Uso: firewall.sh aplicar | limpar | status
#   aplicar -> aplica a politica de seguranca (negar por padrao)
#   limpar  -> remove a filtragem (cenario "sem protecao", tudo ACCEPT)
#   status  -> lista as regras com contadores de pacotes/bytes
#
# Os bloqueios sao registrados via NFLOG (grupo 1) e gravados pelo ulogd em
# /var/log/firewall/firewall.log. O alvo LOG nao e usado porque o kernel o
# ignora dentro de namespaces de rede de conteineres.
#
# Apenas a tabela "filter" e alterada: a tabela "nat" contem as regras do DNS
# embutido do Docker (127.0.0.11) e nao deve ser apagada.
# =============================================================================

REDE_CLIENTES="172.30.0.0/24"
REDE_SERVIDORES="172.31.0.0/24"
SERVIDOR_WEB="172.31.0.10"
APP_PYTHON="172.31.0.20"
NFLOG_GRUPO=1

# Registra (com limite de taxa) e descarta.
# Uso: log_drop <CHAIN> <PREFIXO> [criterios do iptables...]
log_drop() {
    chain="$1"; prefixo="$2"; shift 2
    iptables -A "$chain" "$@" -m limit --limit 30/min --limit-burst 30 \
        -j NFLOG --nflog-group "$NFLOG_GRUPO" --nflog-prefix "$prefixo"
    iptables -A "$chain" "$@" -j DROP
}

limpar() {
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -F
    iptables -X
    iptables -Z
    echo "[FIREWALL] Regras removidas: todo o trafego e permitido (SEM PROTECAO)."
}

aplicar() {
    limpar >/dev/null

    # Politica padrao: negar tudo que nao for explicitamente liberado
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    # ---------------------------- FORWARD ------------------------------------
    # R1: pacotes invalidos (fora de qualquer conexao conhecida)
    log_drop FORWARD "FW-INVALID " -m conntrack --ctstate INVALID
    # R2: respostas de conexoes ja autorizadas
    iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    # R3/R4: clientes -> proxy Nginx somente em HTTP (80) e HTTPS (443)
    iptables -A FORWARD -s "$REDE_CLIENTES" -d "$SERVIDOR_WEB" -p tcp --dport 80 \
        -m conntrack --ctstate NEW -j ACCEPT
    iptables -A FORWARD -s "$REDE_CLIENTES" -d "$SERVIDOR_WEB" -p tcp --dport 443 \
        -m conntrack --ctstate NEW -j ACCEPT
    # R5: ping de diagnostico clientes -> servidores, com limite de taxa
    iptables -A FORWARD -s "$REDE_CLIENTES" -d "$REDE_SERVIDORES" -p icmp \
        --icmp-type echo-request -m limit --limit 5/s --limit-burst 10 -j ACCEPT
    # R6: acesso direto a API, contornando o proxy
    log_drop FORWARD "FW-BYPASS-PROXY " -s "$REDE_CLIENTES" -d "$APP_PYTHON" -p tcp --dport 8000
    # R7: servidores nao podem iniciar conexoes com os clientes
    log_drop FORWARD "FW-SRV-TO-CLI " -s "$REDE_SERVIDORES" -d "$REDE_CLIENTES"
    # R8: todo o resto
    log_drop FORWARD "FW-FWD-DROP "

    # ----------------------------- INPUT -------------------------------------
    # R9: loopback, respostas e ping vindo das redes internas
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -s "$REDE_CLIENTES" -p icmp --icmp-type echo-request \
        -m limit --limit 5/s --limit-burst 10 -j ACCEPT
    iptables -A INPUT -s "$REDE_SERVIDORES" -p icmp --icmp-type echo-request \
        -m limit --limit 5/s --limit-burst 10 -j ACCEPT
    # R10: qualquer outro acesso ao gateway (SSH, gerencia etc.)
    log_drop INPUT "FW-IN-DROP "

    echo "[FIREWALL] Politica aplicada: negar por padrao, liberar apenas o necessario."
}

status() {
    echo "### Tabela filter (com contadores)"
    iptables -L -v -n --line-numbers
}

case "$1" in
    aplicar) aplicar ;;
    limpar)  limpar ;;
    status)  status ;;
    *) echo "Uso: $0 aplicar | limpar | status" >&2; exit 1 ;;
esac
