import hashlib
import hmac
import logging
import os
import secrets
from typing import Dict

from fastapi import Depends, FastAPI, Header, HTTPException, status
from pydantic import BaseModel

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger("seguranca-app")

app = FastAPI(title="Ambiente de Rede Segura - CIC0201")

# Chave secreta usada no HMAC-SHA256 (pode ser sobrescrita via variavel de ambiente)
HMAC_SECRET_KEY = os.getenv("HMAC_SECRET_KEY", "chave-super-secreta-cic0201").encode()


def gerar_hash_senha(senha: str, salt: bytes) -> str:
    dk = hashlib.pbkdf2_hmac("sha256", senha.encode(), salt, 100_000)
    return dk.hex()


# Banco de usuarios em memoria com salt + PBKDF2-HMAC-SHA256
USERS_DB: Dict[str, Dict[str, object]] = {}
for usuario, senha_inicial in [("admin", "Admin@2026"), ("analista", "UnB@Seg2026")]:
    salt = secrets.token_bytes(16)
    USERS_DB[usuario] = {
        "salt": salt,
        "password_hash": gerar_hash_senha(senha_inicial, salt),
    }

# Tokens ativos: token -> username
ACTIVE_TOKENS: Dict[str, str] = {}


class LoginRequest(BaseModel):
    username: str
    password: str


class MensagemRequest(BaseModel):
    mensagem: str


class VerificarMensagemRequest(BaseModel):
    mensagem: str
    hmac_recebido: str


def verificar_token(authorization: str | None = Header(default=None)) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        logger.warning("[AUTH FALHA] Acesso negado: cabecalho Authorization ausente ou invalido.")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token de autenticacao ausente ou malformado.",
        )

    token = authorization.removeprefix("Bearer ").strip()
    usuario = ACTIVE_TOKENS.get(token)
    if not usuario:
        logger.warning("[AUTH FALHA] Acesso negado: token invalido ou expirado.")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalido ou expirado.",
        )

    return usuario


@app.get("/")
def area_publica():
    logger.info("[PUBLICO] Requisicao recebida na area publica.")
    return {
        "servico": "Servidor Corporativo - CIC0201",
        "mensagem": "Area publica acessivel via HTTP/HTTPS.",
        "endpoints": [
            "POST /login",
            "GET /protegido",
            "POST /mensagem/assinar",
            "POST /mensagem/verificar",
        ],
    }


@app.post("/login")
def login(payload: LoginRequest):
    registro = USERS_DB.get(payload.username)
    if not registro:
        logger.warning(f"[LOGIN FALHA] Usuario inexistente: '{payload.username}'.")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Credenciais invalidas.",
        )

    hash_calculado = gerar_hash_senha(payload.password, registro["salt"])
    if not hmac.compare_digest(hash_calculado, registro["password_hash"]):
        logger.warning(f"[LOGIN FALHA] Senha incorreta para usuario '{payload.username}'.")
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Credenciais invalidas.",
        )

    token = secrets.token_hex(24)
    ACTIVE_TOKENS[token] = payload.username
    logger.info(f"[LOGIN SUCESSO] Usuario '{payload.username}' autenticado.")
    return {
        "status": "autenticado",
        "usuario": payload.username,
        "token_type": "Bearer",
        "access_token": token,
    }


@app.get("/protegido")
def area_protegida(usuario: str = Depends(verificar_token)):
    logger.info(f"[AUTH SUCESSO] Usuario '{usuario}' acessou a area protegida.")
    return {
        "status": "acesso_autorizado",
        "usuario": usuario,
        "dados_confidenciais": "Relatorio Financeiro Interno - Acesso Restrito.",
    }


@app.post("/mensagem/assinar")
def assinar_mensagem(payload: MensagemRequest, usuario: str = Depends(verificar_token)):
    assinatura = hmac.new(
        HMAC_SECRET_KEY,
        payload.mensagem.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    logger.info(f"[HMAC GERADO] Usuario '{usuario}' assinou mensagem ({len(payload.mensagem)} bytes).")
    return {
        "usuario": usuario,
        "algoritmo": "HMAC-SHA256",
        "mensagem": payload.mensagem,
        "hmac": assinatura,
    }


@app.post("/mensagem/verificar")
def verificar_mensagem(
    payload: VerificarMensagemRequest,
    usuario: str = Depends(verificar_token),
):
    hmac_esperado = hmac.new(
        HMAC_SECRET_KEY,
        payload.mensagem.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    if hmac.compare_digest(hmac_esperado, payload.hmac_recebido):
        logger.info(f"[HMAC OK] Integridade confirmada para mensagem enviada por '{usuario}'.")
        return {
            "integra": True,
            "status": "Mensagem integra e autentica.",
            "mensagem": payload.mensagem,
            "hmac_verificado": hmac_esperado,
        }

    logger.warning(
        f"[HMAC FALHA] ADULTERACAO DETECTADA! Mensagem='{payload.mensagem}' | "
        f"Recebido={payload.hmac_recebido[:16]}... | Esperado={hmac_esperado[:16]}..."
    )
    raise HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail={
            "integra": False,
            "status": "FALHA DE INTEGRIDADE: a mensagem ou o HMAC foi alterado.",
            "hmac_esperado": hmac_esperado,
            "hmac_recebido": payload.hmac_recebido,
        },
    )