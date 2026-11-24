#!/bin/sh
# Rota de retorno para a rede dos clientes passar pelo gateway
ip route add 172.20.0.0/24 via 172.21.0.2 || true
echo "[NGINX] Rota de retorno via 172.21.0.2 configurada."
exec nginx -g "daemon off;"