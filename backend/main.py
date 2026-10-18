import json
import logging
from contextlib import asynccontextmanager
from typing import Any

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.requests import Request
from fastapi.responses import JSONResponse
import httpx
from postgrest.exceptions import APIError

from core.config import settings

logger = logging.getLogger("techstore")


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Avisa al arrancar si quedan claves de Supabase sin configurar."""
    pending = settings.unconfigured_fields()
    critical = [name for name in pending if name in settings.REQUIRED_FOR_BACKEND]
    optional = [name for name in pending if name not in settings.REQUIRED_FOR_BACKEND]

    if critical:
        logger.warning(
            "FALTAN CLAVES CRÍTICAS de Supabase: %s. El backend devolverá 401/503 en "
            "/products, /orders y /admin. Configúralas en backend/.env o en el .env de la "
            "raíz con los valores de Settings > API Keys del panel de Supabase.",
            ", ".join(critical),
        )
    if optional:
        logger.warning(
            "Claves opcionales sin configurar: %s. SUPABASE_KEY (anon) la usa solo el "
            "frontend (environment.ts) y SUPABASE_JWT_SECRET tiene respaldo ante "
            "auth.get_user(), así que el backend puede funcionar sin ellas.",
            ", ".join(optional),
        )
    if not pending:
        logger.info("Configuración de Supabase cargada correctamente (URL y claves presentes).")
    yield


app = FastAPI(
    title=settings.PROJECT_NAME,
    description="API modular para e-commerce tecnológico con autenticación Supabase, perfiles de usuario, checkout y panel de administración.",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc",
    lifespan=lifespan,
)


@app.exception_handler(APIError)
async def postgrest_exception_handler(request: Request, exc: APIError) -> JSONResponse:
    """Convierte los errores de PostgREST en una respuesta 502 legible."""
    return JSONResponse(status_code=502, content={"detail": _api_error_detail(exc)})


def _extract_nested_message(details: Any) -> str | None:
    """Intenta rescatar un mensaje legible del campo `details` de PostgREST."""
    if not details or isinstance(details, dict):
        return None
    text = details.decode() if isinstance(details, (bytes, bytearray)) else str(details)
    try:
        payload = json.loads(text)
    except (ValueError, TypeError):
        return text.strip() or None
    if isinstance(payload, dict):
        message = payload.get("message")
        hint = payload.get("hint")
        if message and hint:
            return f"{message} ({hint})"
        return message or hint
    return str(payload)


def _api_error_detail(exc: APIError) -> str:
    """Traduce el error de PostgREST/Supabase a un mensaje accionable."""
    code = str(exc.code or "")
    raw = " ".join(str(part) for part in exc.args) + " " + str(exc.message)

    if code == "401" or "invalid api key" in raw.lower():
        return (
            "Supabase rechazó las credenciales (401 Invalid API key). Configura "
            "SUPABASE_KEY (anon key) y SUPABASE_SERVICE_ROLE_KEY (service_role key) en "
            "backend/.env o en el .env de la raíz, copiándolas de Settings > API."
        )
    if code in {"PGRST205", "42P01"} or "could not find the table" in raw.lower():
        return (
            "La tabla no existe en Supabase. Ejecuta en el SQL Editor, en este orden: "
            "database/schema.sql, database/seed.sql y database/optimizations.sql."
        )
    return _extract_nested_message(exc.details) or exc.message or "Error al consultar la base de datos"


@app.exception_handler(httpx.HTTPError)
async def supabase_connection_handler(request: Request, exc: httpx.HTTPError) -> JSONResponse:
    """Devuelve 503 cuando no se puede alcanzar Supabase (URL o claves incorrectas)."""
    return JSONResponse(
        status_code=503,
        content={
            "detail": (
                "No se pudo conectar con Supabase. Revisa SUPABASE_URL y las claves "
                "en backend/.env (o en el .env de la raíz del proyecto) y que tu "
                "proyecto esté activo."
            )
        },
    )

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.BACKEND_CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

from routers import admin, orders, products, profile  # noqa: E402

app.include_router(products.router)
app.include_router(orders.router)
app.include_router(profile.router)
app.include_router(admin.router)


@app.get("/", tags=["Health"])
async def root():
    return {"message": "E-Commerce Tecnológico API", "version": "1.0.0", "docs": "/docs"}


@app.get("/health", tags=["Health"])
async def health_check():
    return {"status": "healthy", "service": settings.PROJECT_NAME}
