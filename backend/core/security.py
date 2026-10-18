"""Seguridad: validacion de JWT de Supabase y control de roles."""
from typing import Annotated

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from jose import JWTError, jwt

from core.config import settings
from core.supabase_client import get_admin_client

bearer_scheme = HTTPBearer(auto_error=False)


def decode_supabase_jwt(token: str) -> dict:
    """Decodifica y valida la firma del JWT emitido por Supabase Auth.

    Supabase firma los tokens con HS256 usando el JWT Secret del proyecto.
    Si la validacion de firma falla, se valida el token contra el servidor
    de Supabase como respaldo.
    """
    try:
        payload = jwt.decode(
            token,
            settings.SUPABASE_JWT_SECRET,
            algorithms=["HS256"],
            options={"verify_aud": False},
        )
        return payload
    except JWTError:
        pass

    try:
        user = get_admin_client().auth.get_user(token)
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalido o expirado",
        ) from exc

    if user is None or user.user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalido o expirado",
        )
    return user.user.model_dump()


def get_current_user(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer_scheme)],
) -> dict:
    """Dependencia que extrae el Bearer token y valida su firma."""
    if credentials is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="No autenticado: falta el token Bearer",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return decode_supabase_jwt(credentials.credentials)


def get_user_id(user: Annotated[dict, Depends(get_current_user)]) -> str:
    """Extrae el UID del usuario desde el claim sub del JWT."""
    user_id = user.get("id") or user.get("sub")
    if not user_id:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token sin identidad")
    return user_id


def is_admin(user: dict) -> bool:
    """Determina si el JWT corresponde a un administrador."""
    app_meta = user.get("app_metadata") or {}
    user_meta = user.get("user_metadata") or {}
    return app_meta.get("role") == "admin" or user_meta.get("role") == "admin"


def is_customer(user: dict) -> bool:
    """Determina si el JWT corresponde a un cliente."""
    app_meta = user.get("app_metadata") or {}
    user_meta = user.get("user_metadata") or {}
    role = app_meta.get("role") or user_meta.get("role")
    return role in (None, "customer")


async def require_admin(user: Annotated[dict, Depends(get_current_user)]) -> dict:
    """Dependencia que restringe el acceso a administradores."""
    if not is_admin(user):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Se requiere rol de administrador")
    return user


async def require_customer(user: Annotated[dict, Depends(get_current_user)]) -> dict:
    """Dependencia que garantiza que el usuario tenga rol customer."""
    if not is_customer(user):
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Se requiere rol de cliente")
    return user
