"""Authenticated reporting API. Run with: uvicorn backend_fastapi.main:app."""

import logging
import os
from contextlib import asynccontextmanager
from dataclasses import dataclass
from typing import Annotated
from urllib.parse import urlparse
from uuid import UUID, uuid4

import httpx
from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException, Query, Request
from fastapi.exceptions import RequestValidationError
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel, ConfigDict, Field

load_dotenv()
logger = logging.getLogger("alertx")
bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class Settings:
    supabase_url: str = ""
    supabase_anon_key: str = ""
    environment: str = "development"
    cors_origins: tuple[str, ...] = ()
    allowed_hosts: tuple[str, ...] = ("localhost", "127.0.0.1", "testserver")

    @classmethod
    def from_env(cls):
        return cls(
            supabase_url=os.getenv("SUPABASE_URL", "").rstrip("/"),
            supabase_anon_key=os.getenv("SUPABASE_ANON_KEY", ""),
            environment=os.getenv("APP_ENV", "development"),
            cors_origins=tuple(filter(None, (s.strip() for s in os.getenv("CORS_ORIGINS", "").split(",")))),
            allowed_hosts=tuple(filter(None, (s.strip() for s in os.getenv("ALLOWED_HOSTS", "localhost,127.0.0.1").split(",")))),
        )

    @property
    def configured(self):
        return bool(self.supabase_url and self.supabase_anon_key)

    def validate(self):
        if self.environment not in {"development", "production", "test"}:
            raise RuntimeError("APP_ENV inválido")
        if self.environment == "production":
            if not self.configured or urlparse(self.supabase_url).scheme != "https":
                raise RuntimeError("Producción requiere Supabase con HTTPS y su clave pública")
            if not self.allowed_hosts or "*" in self.allowed_hosts:
                raise RuntimeError("Configura ALLOWED_HOSTS explícitamente")
            if any(urlparse(origin).scheme != "https" for origin in self.cors_origins):
                raise RuntimeError("CORS_ORIGINS debe contener orígenes HTTPS")
        if self.supabase_anon_key.startswith("sb_secret_"):
            raise RuntimeError("Usa una clave pública; las claves secretas omiten RLS")
        if self.supabase_anon_key.count(".") == 2:
            import base64
            import json

            try:
                payload = self.supabase_anon_key.split(".")[1]
                role = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4))).get("role")
            except (ValueError, UnicodeError):
                raise RuntimeError("Clave pública inválida") from None
            if role != "anon":
                raise RuntimeError("La clave de Supabase debe tener rol anon")


class ReportInput(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True, allow_inf_nan=False)
    request_id: UUID
    latitud: float = Field(ge=-90, le=90)
    longitud: float = Field(ge=-180, le=180)
    descripcion: str = Field(min_length=15, max_length=2000)
    tipo: str = Field(pattern=r"^(colision|obstruccion|riesgo_vial|otro)$")
    precision_metros: float | None = Field(default=None, ge=0, le=100000)


class BodyLimitMiddleware:
    """Bound streamed request bodies before JSON decoding, including chunked input."""

    def __init__(self, app, limit=16384):
        self.app, self.limit = app, limit

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http" or scope["method"] not in {"POST", "PUT", "PATCH"}:
            return await self.app(scope, receive, send)
        messages, size = [], 0
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            size += len(message.get("body", b""))
            if size > self.limit:
                return await JSONResponse({"detail": "Solicitud demasiado grande"}, status_code=413)(scope, receive, send)
            messages.append(message)
            if not message.get("more_body", False):
                break

        async def replay():
            return messages.pop(0) if messages else await receive()

        await self.app(scope, replay, send)


def create_app(settings: Settings | None = None, transport=None):
    settings = settings or Settings.from_env()
    settings.validate()

    @asynccontextmanager
    async def lifespan(app):
        async with httpx.AsyncClient(timeout=httpx.Timeout(10, connect=5), transport=transport) as client:
            app.state.http = client
            yield

    app = FastAPI(
        title="AlertX API", version="1.0.0", lifespan=lifespan,
        docs_url="/docs" if settings.environment != "production" else None,
        redoc_url=None, openapi_url="/openapi.json" if settings.environment != "production" else None,
    )
    app.add_middleware(BodyLimitMiddleware)
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=list(settings.allowed_hosts))
    app.add_middleware(CORSMiddleware, allow_origins=list(settings.cors_origins),
                       allow_methods=["GET", "POST"], allow_headers=["Authorization", "Content-Type"],
                       expose_headers=["X-Request-ID"], max_age=600)

    @app.middleware("http")
    async def headers(request, call_next):
        request_id = str(uuid4())
        try:
            response = await call_next(request)
        except Exception:
            logger.error("Unhandled request failure: %s", request_id)
            response = JSONResponse({"detail": "No se pudo completar la solicitud"}, status_code=500)
        response.headers["X-Request-ID"] = request_id
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["Cache-Control"] = "no-store"
        response.headers["Referrer-Policy"] = "no-referrer"
        if settings.environment == "production":
            response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        return response

    @app.exception_handler(RequestValidationError)
    async def validation_error(request, exc):
        return JSONResponse({"detail": "Revisa los campos del reporte", "campos": [
            ".".join(map(str, e["loc"])) for e in exc.errors()
        ]}, status_code=422)

    async def upstream(request: Request, method, path, token=None, **kwargs):
        if not settings.configured:
            raise HTTPException(503, "Servicio pendiente de configuración")
        headers = {"apikey": settings.supabase_anon_key}
        if token:
            headers["Authorization"] = f"Bearer {token}"
        try:
            response = await request.app.state.http.request(
                method, f"{settings.supabase_url}{path}", headers=headers, **kwargs
            )
        except httpx.RequestError:
            raise HTTPException(503, "Servicio temporalmente no disponible") from None
        if response.status_code in (401, 403):
            raise HTTPException(401, "Tu sesión expiró. Vuelve a iniciar sesión", headers={"WWW-Authenticate": "Bearer"})
        if not response.is_success:
            try:
                message = response.json().get("message")
            except (ValueError, AttributeError):
                message = None
            if message == "report_rate_limit":
                raise HTTPException(429, "Has enviado varios reportes. Intenta en un minuto", headers={"Retry-After": "60"})
            if message == "idempotency_conflict":
                raise HTTPException(409, "Este envío ya existe con otros datos")
            logger.warning("Upstream failure: %s %s", path, response.status_code)
            raise HTTPException(503, "No se pudo acceder a los reportes. Intenta nuevamente")
        try:
            return response.json()
        except ValueError:
            raise HTTPException(503, "Respuesta del servicio no disponible") from None

    async def authenticated(request: Request, credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)]):
        if not credentials or credentials.scheme.lower() != "bearer":
            raise HTTPException(401, "Inicia sesión para continuar", headers={"WWW-Authenticate": "Bearer"})
        user = await upstream(request, "GET", "/auth/v1/user", credentials.credentials)
        if not isinstance(user, dict) or not user.get("id") or user.get("is_anonymous"):
            raise HTTPException(401, "Se requiere una cuenta registrada")
        try:
            user_id = str(UUID(user["id"]))
        except (ValueError, TypeError):
            raise HTTPException(401, "Sesión inválida") from None
        return credentials.credentials, user_id

    @app.get("/health")
    async def health():
        return {"status": "ok", "service": "AlertX", "version": "1.0.0"}

    @app.get("/ready")
    async def ready(request: Request):
        await upstream(request, "GET", "/auth/v1/health")
        await upstream(request, "POST", "/rest/v1/rpc/alertx_schema_version", json={})
        return {"status": "ready"}

    @app.get("/reportes")
    async def reports(request: Request, session=Depends(authenticated),
                      limit: int = Query(20, ge=1, le=100), offset: int = Query(0, ge=0, le=100000)):
        token, user_id = session
        return await upstream(request, "GET", "/rest/v1/alertx_reports", token, params={
            "select": "id,created_at,latitud,longitud,descripcion,tipo,estado,precision_metros",
            "usuario_id": f"eq.{user_id}", "order": "created_at.desc,id.desc", "limit": limit, "offset": offset,
        })

    @app.get("/estadisticas")
    async def statistics(request: Request, session=Depends(authenticated)):
        return await upstream(request, "POST", "/rest/v1/rpc/alertx_my_stats", session[0], json={})

    @app.post("/reportes", status_code=201)
    async def create_report(report: ReportInput, request: Request, session=Depends(authenticated)):
        return await upstream(request, "POST", "/rest/v1/rpc/alertx_create_report", session[0], json={
            "p_request_id": str(report.request_id), "p_latitud": report.latitud,
            "p_longitud": report.longitud, "p_descripcion": report.descripcion,
            "p_tipo": report.tipo, "p_precision_metros": report.precision_metros,
        })

    @app.post("/analizar_accidente", status_code=410)
    @app.post("/analizar_imagen_accidente", status_code=410)
    async def retired_analysis(session=Depends(authenticated)):
        return {"detail": "El análisis experimental se retiró de producción. Registra el incidente en POST /reportes."}

    return app


app = create_app()
