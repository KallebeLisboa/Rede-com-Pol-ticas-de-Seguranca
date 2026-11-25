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
```

## Módulo 4 — Firewall, Controle de Acesso e Monitoramento

O contêiner `gateway` aplica a política abaixo automaticamente ao subir, por meio do [gateway/entrypoint.sh](gateway/entrypoint.sh) e do [gateway/firewall.sh](gateway/firewall.sh). Os bloqueios são registrados via `NFLOG` + `ulogd2` em `logs/firewall.log`.

### Política de segurança (empresa hipotética)
1. **Negar por padrão**: tudo que não for explicitamente liberado é descartado (`INPUT` e `FORWARD` com política `DROP`).
2. **Ponto único de entrada**: clientes acessam a aplicação somente pelo proxy Nginx (`172.21.0.10`), nas portas 80 e 443.
3. **Backend protegido**: o acesso direto à API (`172.21.0.20:8000`) é proibido e registrado como tentativa de contornar o proxy.
4. **Servidores não iniciam conexões** com a rede de clientes, o que impede movimento lateral e *reverse shell*.
5. **Diagnóstico controlado**: ping de clientes para servidores e para o gateway é liberado, com limite de taxa.
6. **Gateway sem serviços de gerência** expostos (SSH etc.).
7. **Toda negação é registrada**, com prefixo identificável e limite de 30 registros/min.

### Tabela de regras
| # | Chain | Origem | Destino | Proto/Porta | Ação | Prefixo do log |
| :- | :- | :- | :- | :- | :- | :- |
| 1 | FORWARD | qualquer | qualquer | estado INVALID | LOG + DROP | `FW-INVALID` |
| 2 | FORWARD | qualquer | qualquer | ESTABLISHED,RELATED | ACCEPT | – |
| 3 | FORWARD | 172.20.0.0/24 | 172.21.0.10 | TCP 80 | ACCEPT | – |
| 4 | FORWARD | 172.20.0.0/24 | 172.21.0.10 | TCP 443 | ACCEPT | – |
| 5 | FORWARD | 172.20.0.0/24 | 172.21.0.0/24 | ICMP echo-request (5/s) | ACCEPT | – |
| 6 | FORWARD | 172.20.0.0/24 | 172.21.0.20 | TCP 8000 | LOG + DROP | `FW-BYPASS-PROXY` |
| 7 | FORWARD | 172.21.0.0/24 | 172.20.0.0/24 | qualquer (nova conexão) | LOG + DROP | `FW-SRV-TO-CLI` |
| 8 | FORWARD | qualquer | qualquer | demais | LOG + DROP | `FW-FWD-DROP` |
| 9 | INPUT | lo / ESTABLISHED / ICMP das redes internas | gateway | – | ACCEPT | – |
| 10 | INPUT | qualquer | gateway | demais | LOG + DROP | `FW-IN-DROP` |
| – | OUTPUT | gateway | qualquer | – | ACCEPT | – |

### Comandos úteis
```bash
docker exec gateway sh /firewall.sh status    # regras com contadores
docker exec gateway sh /firewall.sh limpar    # desliga a filtragem (cenário sem proteção)
docker exec gateway sh /firewall.sh aplicar   # religa a política
tail -f logs/firewall.log                     # bloqueios em tempo real
```

### Testes e evidências
```bash
bash testes/testar_modulo4.sh   # executar no host, na raiz do projeto
```
O script compara o cenário **sem firewall** com o cenário **com firewall** e gera:
- `testes/evidencia_modulo4.txt`: resultado de cada teste, contadores das regras e registros de bloqueio;
- `capturas/modulo4_firewall.pcap`: captura no gateway. No Wireshark, com o filtro `tcp.flags.syn==1`, os SYNs bloqueados chegam ao gateway, são retransmitidos e nunca recebem resposta (nem RST).

Na saída dos testes, `RECUSADA` significa que o firewall deixou o pacote passar, mas não há serviço na porta (o destino respondeu RST). `BLOQUEADA` significa que o pacote foi descartado pelo firewall (timeout).

**Limitação:** o tráfego Nginx → API (`172.21.0.10` → `172.21.0.20`) fica dentro da mesma sub-rede e não passa pelo gateway, por isso não é filtrado por ele.
