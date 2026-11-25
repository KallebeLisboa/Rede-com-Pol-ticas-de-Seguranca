#!/bin/sh
# =============================================================================
# Modulo 2 - CA e certificado do servidor web (OpenSSL)
#
# Uso: bash nginx/gerar_certificados.sh [--force]
#   (sem flags) -> gera nginx/certs/ se ainda nao existir; se existir, pergunta
#                  no terminal ou encerra sem alterar (execucao nao interativa)
#   --force     -> apaga e gera de novo a CA e o certificado do servidor
#
# Rode no host, antes do "docker compose up". Os clientes validam a cadeia com
# ca.crt (montado em /certs). O certificado do servidor inclui SAN para o IP
# 172.31.0.10 e o nome servidor.local, porque o acesso no laboratorio e por IP.
#
# Arquivos gerados em nginx/certs/:
#   ca.key      chave privada da CA (RSA 4096, modo 600)
#   ca.crt      certificado autoassinado da CA (365 dias, CA:TRUE)
#   server.key  chave privada do servidor (RSA 2048, modo 600)
#   server.csr  pedido de certificado (CN=servidor.local)
#   server.crt  certificado do servidor assinado pela CA
#   ca.srl      numero de serie usado pelo OpenSSL na assinatura
# =============================================================================

set -eu

DIAS=365
CA_CN="CA Laboratorio CIC0201"
SERVER_CN="servidor.local"
SAN_DNS="servidor.local"
SAN_IP="172.31.0.10"

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
CERTS_DIR="$SCRIPT_DIR/certs"

usage() {
    echo "Uso: bash nginx/gerar_certificados.sh [--force]"
    echo "  Gera a CA e o certificado TLS do servidor em nginx/certs/."
    echo "  --force  regera mesmo que os arquivos ja existam."
}

FORCE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --force|-f) FORCE=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo "Opcao desconhecida: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
    shift
done

if ! command -v openssl >/dev/null 2>&1; then
    echo "Erro: openssl nao encontrado no PATH." >&2
    exit 1
fi

mkdir -p "$CERTS_DIR"

certs_existem() {
    [ -f "$CERTS_DIR/ca.key" ] && [ -f "$CERTS_DIR/ca.crt" ] \
        && [ -f "$CERTS_DIR/server.key" ] && [ -f "$CERTS_DIR/server.crt" ]
}

if certs_existem && [ "$FORCE" -eq 0 ]; then
    if [ -t 0 ]; then
        printf "Certificados ja existem em %s. Regerar? [s/N] " "$CERTS_DIR"
        read -r resposta || resposta=""
        case "$resposta" in
            s|S|sim|SIM|y|Y|yes|YES) ;;
            *)
                echo "Mantendo os certificados existentes."
                exit 0
                ;;
        esac
    else
        echo "Certificados ja existem em $CERTS_DIR."
        echo "Nada foi alterado. Use --force para regerar."
        exit 0
    fi
fi

CA_CNF=$(mktemp)
SERVER_EXT=$(mktemp)
trap 'rm -f "$CA_CNF" "$SERVER_EXT"' EXIT INT TERM

# openssl req 3.x nao aceita -extfile; a CA usa um config com a extensao v3.
cat > "$CA_CNF" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3_ca
prompt = no

[dn]
CN = ${CA_CN}

[v3_ca]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
EOF

cat > "$SERVER_EXT" <<EOF
subjectAltName = DNS:${SAN_DNS}, IP:${SAN_IP}
basicConstraints = CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid, issuer
EOF

cd "$CERTS_DIR"
rm -f ca.key ca.crt ca.srl server.key server.csr server.crt

umask 077

echo "=== Gerando chave da CA (RSA 4096) ==="
openssl genrsa -out ca.key 4096
chmod 600 ca.key

echo "=== Gerando certificado autoassinado da CA (${DIAS} dias) ==="
openssl req -x509 -new -key ca.key -sha256 -days "$DIAS" \
    -out ca.crt \
    -config "$CA_CNF"
chmod 644 ca.crt

echo "=== Gerando chave do servidor (RSA 2048) ==="
openssl genrsa -out server.key 2048
chmod 600 server.key

echo "=== Gerando CSR do servidor (CN=${SERVER_CN}) ==="
openssl req -new -key server.key -out server.csr \
    -subj "/CN=${SERVER_CN}"
chmod 644 server.csr

echo "=== Assinando o certificado do servidor com a CA ==="
openssl x509 -req \
    -in server.csr \
    -CA ca.crt \
    -CAkey ca.key \
    -CAcreateserial \
    -out server.crt \
    -days "$DIAS" \
    -sha256 \
    -extfile "$SERVER_EXT"
chmod 644 server.crt
chmod 600 ca.key server.key

echo "=== Validando a cadeia ==="
openssl verify -CAfile ca.crt server.crt

echo ""
echo "Certificado do servidor:"
openssl x509 -in server.crt -noout -subject -issuer -dates \
    -ext subjectAltName,basicConstraints,keyUsage,extendedKeyUsage

echo ""
echo "Arquivos gravados em $CERTS_DIR"
