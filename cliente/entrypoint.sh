#!/bin/sh
# Direciona o trafego destinado a rede dos servidores para o gateway
ip route add 172.31.0.0/24 via 172.30.0.2 || true
echo "[CLIENTE] Rota para rede_servidores via 172.30.0.2 configurada."
exec tail -f /dev/null