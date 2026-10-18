"""Gestión del perfil del usuario autenticado y su historial de compras."""
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from supabase import Client

from core.security import get_user_id
from core.supabase_client import get_admin_client
from routers.schemas import Profile, ProfileUpdate

router = APIRouter(prefix="/profile", tags=["Profile"])


def _fetch_profile(sb: Client, user_id: str) -> dict:
    """Recupera la fila de users_profile o lanza 404 si no existe."""
    response = sb.table("users_profile").select("*").eq("id", user_id).maybe_single().execute()
    if response is None or response.data is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Perfil no encontrado")
    return response.data


@router.get("/me", response_model=Profile)
async def read_profile(user_id: Annotated[str, Depends(get_user_id)]) -> Profile:
    """Devuelve el perfil del usuario autenticado."""
    data = _fetch_profile(get_admin_client(), user_id)
    return Profile(**data)


@router.put("/me", response_model=Profile)
async def update_profile(
    payload: ProfileUpdate,
    user_id: Annotated[str, Depends(get_user_id)],
) -> Profile:
    """Actualiza los datos personales del usuario autenticado."""
    sb = get_admin_client()
    _fetch_profile(sb, user_id)

    updates = {k: v for k, v in payload.model_dump().items() if v is not None}
    if updates:
        sb.table("users_profile").update(updates).eq("id", user_id).execute()

    return Profile(**_fetch_profile(sb, user_id))


@router.get("/me/orders")
async def get_purchase_history(user_id: Annotated[str, Depends(get_user_id)]) -> list[dict]:
    """Devuelve el historial de compras del usuario autenticado con sus ítems."""
    sb = get_admin_client()
    orders = (
        sb.table("orders")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .execute()
    )

    history: list[dict] = []
    for order in orders.data:
        items = (
            sb.table("order_items")
            .select("*, products(name)")
            .eq("order_id", order["id"])
            .execute()
        )
        history.append({**order, "items": items.data})
    return history
