"""Panel de administración: CRUD de productos, órdenes y métricas de ventas."""
from datetime import datetime, timezone
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from supabase import Client

from core.security import require_admin
from core.supabase_client import get_admin_client
from routers.schemas import (
    OrderStatusUpdate,
    Product,
    ProductCreate,
    ProductUpdate,
    SalesMetrics,
)

router = APIRouter(prefix="/admin", tags=["Admin"], dependencies=[Depends(require_admin)])


@router.post("/products", response_model=Product, status_code=status.HTTP_201_CREATED)
async def create_product(
    payload: ProductCreate,
    sb: Annotated[Client, Depends(get_admin_client)],
) -> Product:
    """Crea un nuevo producto en el catálogo."""
    response = sb.table("products").insert(payload.model_dump()).execute()
    return Product(**response.data[0])


@router.put("/products/{product_id}", response_model=Product)
async def update_product(
    product_id: int,
    payload: ProductUpdate,
    sb: Annotated[Client, Depends(get_admin_client)],
) -> Product:
    """Actualiza cualquier campo de un producto existente (incluido el stock)."""
    existing = sb.table("products").select("id").eq("id", product_id).maybe_single().execute()
    if existing is None or existing.data is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Producto no encontrado")

    updates = {k: v for k, v in payload.model_dump().items() if v is not None}
    if not updates:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="No hay campos para actualizar")

    response = sb.table("products").update(updates).eq("id", product_id).execute()
    return Product(**response.data[0])


@router.delete("/products/{product_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_product(
    product_id: int,
    sb: Annotated[Client, Depends(get_admin_client)],
) -> None:
    """Elimina un producto del catálogo."""
    existing = sb.table("products").select("id").eq("id", product_id).maybe_single().execute()
    if existing is None or existing.data is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Producto no encontrado")
    sb.table("products").delete().eq("id", product_id).execute()


@router.get("/orders")
async def list_all_orders(
    sb: Annotated[Client, Depends(get_admin_client)],
    status_filter: str | None = Query(None, alias="status"),
) -> list[dict]:
    """Lista todas las órdenes del sistema con el nombre del cliente."""
    query = (
        sb.table("orders")
        .select("*, users_profile(full_name)")
        .order("created_at", desc=True)
    )
    if status_filter:
        query = query.eq("status", status_filter)
    return query.execute().data


@router.patch("/orders/{order_id}/status")
async def update_order_status(
    order_id: int,
    payload: OrderStatusUpdate,
    sb: Annotated[Client, Depends(get_admin_client)],
) -> dict:
    """Cambia el estado de una orden y actualiza su marca de tiempo."""
    existing = sb.table("orders").select("id").eq("id", order_id).maybe_single().execute()
    if existing is None or existing.data is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Orden no encontrada")

    timestamp = datetime.now(timezone.utc).isoformat()
    response = (
        sb.table("orders")
        .update({"status": payload.status, "updated_at": timestamp})
        .eq("id", order_id)
        .execute()
    )
    return response.data[0]


@router.get("/metrics", response_model=SalesMetrics)
async def get_sales_metrics(sb: Annotated[Client, Depends(get_admin_client)]) -> SalesMetrics:
    """Métricas de ventas: ingresos totales, órdenes por estado y top productos."""
    orders = sb.table("orders").select("status, total_amount").neq("status", "cancelled").execute()

    total_revenue = round(sum(float(o["total_amount"]) for o in orders.data), 2)
    orders_by_status: dict[str, int] = {}
    for order in orders.data:
        key = order["status"]
        orders_by_status[key] = orders_by_status.get(key, 0) + 1

    items = sb.table("order_items").select("product_id, quantity, total_price").execute()
    product_totals: dict[int, dict] = {}
    for item in items.data:
        entry = product_totals.setdefault(
            item["product_id"],
            {"product_id": item["product_id"], "units": 0, "revenue": 0.0},
        )
        entry["units"] += int(item["quantity"])
        entry["revenue"] += float(item["total_price"])

    top_products = sorted(product_totals.values(), key=lambda e: e["units"], reverse=True)[:5]

    return SalesMetrics(
        total_orders=len(orders.data),
        total_revenue=total_revenue,
        orders_by_status=orders_by_status,
        top_products=top_products,
    )
