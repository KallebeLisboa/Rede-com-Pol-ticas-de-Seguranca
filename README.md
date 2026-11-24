# Ambiente de Rede com Políticas de Segurança — CIC0201

Projeto da disciplina **Segurança Computacional (CIC0201 — UnB)** que implementa uma rede corporativa virtual isolada em Docker, demonstrando comunicação insegura (HTTP), comunicação segura (HTTPS/TLS), autenticação com verificação de integridade (HMAC-SHA256) e filtragem de tráfego com firewall (`iptables`).

## Arquitetura de Rede

O ambiente isola clientes e servidores em duas sub-redes Docker (`internal: true`), forçando todo o tráfego a passar pelo contêiner `gateway`:

| Contêiner | Rede(s) | Endereço IP | Função |
| :--- | :--- | :--- | :--- |
| `cliente` | `rede_clientes` | `172.20.0.10` | Cliente Linux (`curl`, `nc`, `tcpdump`, `openssl`) |
| `gateway` | `rede_clientes` / `rede_servidores` | `172.20.0.2` / `172.21.0.2` | Roteamento, firewall (`iptables`) e captura de pacotes |
| `servidor_web` | `rede_servidores` | `172.21.0.10` | Proxy reverso Nginx (HTTP :80 e HTTPS :443) |
| `app_python` | `rede_servidores` | `172.21.0.20` | API FastAPI com autenticação Bearer e HMAC-SHA256 |

## Como Reproduzir o Ambiente

### Pré-requisitos
- Linux com **Docker** e **Docker Compose** instalados.
- **Wireshark** (no host, para abrir os arquivos `.pcap` salvos em `./capturas`).

### Execução
```bash
# 1. Subir todos os contêineres e redes isoladas
docker compose up -d --build

# 2. Validar que o roteamento passa pelo gateway (172.20.0.2)
docker exec cliente traceroute -n 172.21.0.10