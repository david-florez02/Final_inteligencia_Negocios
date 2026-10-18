"""Carrito, checkout y consulta de órdenes del cliente.

El checkout delega en la función atómica de PostgreSQL `public.process_checkout`
(definida en `database/optimizations.sql`) para que validar stock, crear la orden,
insertar sus ítems y descontar inventario ocurra en una única transacción con
bloqueo `SELECT ... FOR UPDATE`. Así se elimina la carrera de stock y no quedan
órdenes a medias.
"""
import uuid
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, status
from postgrest.exceptions import APIError
from supabase import Client

from core.security import get_user_id
from core.supabase_client import get_admin_client
from routers.schemas import CheckoutRequest

router = APIRouter(prefix="/orders", tags=["Orders"])

# Mapeo de SQLSTATE de `process_checkout` a códigos HTTP.
SQLSTATE_TO_HTTP: dict[str, int] = {
    "22023": status.HTTP_400_BAD_REQUEST,      # datos inválidos: carrito vacío o ítem malformado
    "23503": status.HTTP_400_BAD_REQUEST,      # usuario inexistente en users_profile
    "P0002": status.HTTP_404_NOT_FOUND,        # producto inexistente
    "42501": status.HTTP_403_FORBIDDEN,        # no autorizado a operar a nombre de otro usuario
    "23514": status.HTTP_409_CONFLICT,         # stock insuficiente / CHECK violado
    "PGRST202": status.HTTP_503_SERVICE_UNAVAILABLE,  # falta aplicar database/optimizations.sql
}

MISSING_FUNCTION_DETAIL = (
    "La función public.process_checkout no existe en la base de datos. "
    "Ejecuta database/optimizations.sql en el SQL Editor de Supabase."
)


def _raise_checkout_error(exc: APIError) -> None:
    """Traduce un APIError de PostgREST a la respuesta HTTP adecuada."""
    code = exc.code or ""
    http_status = SQLSTATE_TO_HTTP.get(code, status.HTTP_502_BAD_GATEWAY)
    detail = exc.message or "Error al procesar el checkout"
    if code == "PGRST202":
        detail = MISSING_FUNCTION_DETAIL
    raise HTTPException(status_code=http_status, detail=detail) from exc


@router.post("/checkout")
async def checkout(
    payload: CheckoutRequest,
    user_id: Annotated[str, Depends(get_user_id)],
    sb: Annotated[Client, Depends(get_admin_client)],
) -> dict[str, Any]:
    """Procesa el carrito de forma atómica mediante la RPC `process_checkout`.

    Traduce los SQLSTATE de la función a códigos HTTP:
    `22023`→400, `23503`→400, `P0002`→404, `42501`→403, `23514`→409 (stock insuficiente).
    """
    items = [{"product_id": item.product_id, "quantity": item.quantity} for item in payload.items]
    try:
        response = sb.rpc(
            "process_checkout",
            {"p_user_id": user_id, "p_items": items},
        ).execute()
    except APIError as exc:
        _raise_checkout_error(exc)

    result = response.data
    if not result:
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY,
            detail="El checkout no devolvió datos de la orden",
        )

    return {
        "order_id": result["order_id"],
        "status": result.get("status", "pending"),
        "total": result.get("total", 0),
        "item_count": result.get("item_count", len(items)),
        "items": result.get("items", []),
        "reference": uuid.uuid4().hex[:8].upper(),
    }


@router.get("/me")
async def list_my_orders(
    user_id: Annotated[str, Depends(get_user_id)],
    sb: Annotated[Client, Depends(get_admin_client)],
) -> list[dict]:
    """Devuelve todas las órdenes del cliente autenticado."""
    response = (
        sb.table("orders")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .execute()
    )
    return response.data


@router.get("/me/{order_id}")
async def get_my_order(
    order_id: int,
    user_id: Annotated[str, Depends(get_user_id)],
    sb: Annotated[Client, Depends(get_admin_client)],
) -> dict:
    """Devuelve una orden propia con sus ítems, verificando la propiedad."""
    order = sb.table("orders").select("*").eq("id", order_id).maybe_single().execute()
    if order is None or order.data is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Orden no encontrada")
    if order.data["user_id"] != user_id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, detail="No es propietario de esta orden")

    items = sb.table("order_items").select("*, products(name)").eq("order_id", order_id).execute()
    return {**order.data, "items": items.data}
