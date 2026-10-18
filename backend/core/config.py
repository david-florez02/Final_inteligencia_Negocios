"""Configuracion central de la aplicacion leida desde variables de entorno.

Los archivos `.env` se resuelven con rutas absolutas, de modo que la configuracion
funciona sin importar desde que directorio se ejecute `uvicorn`. Se cargan en este
orden (el ultimo sobrescribe al anterior, tal como documenta pydantic-settings):

1. `backend/.env`
2. `.env` de la raiz del proyecto (configuracion global del proyecto)

Las variables de entorno reales del sistema siempre tienen prioridad sobre ambos.
"""
from functools import lru_cache
from pathlib import Path

from pydantic_settings import BaseSettings, SettingsConfigDict

BASE_DIR = Path(__file__).resolve().parent.parent      # .../backend
PROJECT_ROOT = BASE_DIR.parent                          # .../proyectoInteligenciaNegocios

# Fragmentos que delatan un valor de ejemplo sin reemplazar.
PLACEHOLDER_HINTS = ("tu-", "tu_", "reemplaza", "aqui", "aquí", "placeholder", "example", "<")


class Settings(BaseSettings):
    """Configuracion central de la aplicacion."""

    PROJECT_NAME: str = "E-Commerce Tecnologico API"
    SUPABASE_URL: str
    SUPABASE_KEY: str
    SUPABASE_SERVICE_ROLE_KEY: str
    SUPABASE_JWT_SECRET: str
    BACKEND_CORS_ORIGINS: list[str] = [
        "http://localhost:4200",
        "http://127.0.0.1:4200",
    ]
    PORT: int = 8000

    # Claves sin las cuales el backend no puede operar:
    # el cliente de Supabase usa la service_role key y la URL del proyecto.
    REQUIRED_FOR_BACKEND: tuple[str, ...] = ("SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY")
    # Claves que el backend puede tolerar:
    # SUPABASE_KEY (anon) solo la usa el frontend; el JWT secret tiene respaldo
    # contra auth.get_user() cuando la firma HS256 no se puede verificar.
    OPTIONAL_FOR_BACKEND: tuple[str, ...] = ("SUPABASE_KEY", "SUPABASE_JWT_SECRET")

    model_config = SettingsConfigDict(
        # El ultimo archivo de la tupla tiene prioridad.
        env_file=(BASE_DIR / ".env", PROJECT_ROOT / ".env"),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    def unconfigured_fields(self) -> list[str]:
        """Devuelve los campos de Supabase que siguen vacios o con valor de ejemplo."""
        names = (
            "SUPABASE_URL",
            "SUPABASE_KEY",
            "SUPABASE_SERVICE_ROLE_KEY",
            "SUPABASE_JWT_SECRET",
        )
        pending: list[str] = []
        for name in names:
            value = (getattr(self, name) or "").strip()
            if not value or any(hint in value.lower() for hint in PLACEHOLDER_HINTS):
                pending.append(name)
        return pending


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
