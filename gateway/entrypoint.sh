#!/bin/sh
echo "[GATEWAY] Roteamento ativo entre 172.20.0.0/24 e 172.21.0.0/24."

# Coletor de logs do firewall (NFLOG -> /var/log/firewall/firewall.log)
mkdir -p /var/log/firewall
ulogd -d -c /etc/ulogd.conf
echo "[GATEWAY] ulogd iniciado (logs em /var/log/firewall/firewall.log)."

# Modulo 4: aplica a politica de seguranca ao subir o conteiner
sh /firewall.sh aplicar

exec tail -f /dev/null
