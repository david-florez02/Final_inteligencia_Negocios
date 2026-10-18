"""Catálogo público de productos y categorías."""
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Query, status
from supabase import Client

from core.supabase_client import get_admin_client
from routers.schemas import Category, Product

router = APIRouter(prefix="/products", tags=["Products"])


@router.get("", response_model=list[Product])
async def list_products(
    sb: Annotated[Client, Depends(get_admin_client)],
    category_id: int | None = Query(None, description="Filtrar por categoría"),
    search: str | None = Query(None, min_length=1, description="Buscar por nombre"),
    in_stock: bool = Query(False, description="Solo productos con stock"),
) -> list[Product]:
    """Lista el catálogo con filtros opcionales por categoría, búsqueda y stock."""
    query = sb.table("products").select("*")
    if category_id is not None:
        query = query.eq("category_id", category_id)
    if search:
        query = query.ilike("name", f"%{search}%")
    if in_stock:
        query = query.gt("stock", 0)
    response = query.order("name").execute()
    return [Product(**row) for row in response.data]


@router.get("/categories", response_model=list[Category])
async def list_categories(
    sb: Annotated[Client, Depends(get_admin_client)],
) -> list[Category]:
    """Lista todas las categorías disponibles."""
    response = sb.table("categories").select("*").order("name").execute()
    return [Category(**row) for row in response.data]


@router.get("/{product_id}", response_model=Product)
async def get_product(
    product_id: int,
    sb: Annotated[Client, Depends(get_admin_client)],
) -> Product:
    """Devuelve el detalle de un producto por su id."""
    response = sb.table("products").select("*").eq("id", product_id).maybe_single().execute()
    if response is None or response.data is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Producto no encontrado")
    return Product(**response.data)


@router.get("/{product_id}/stock")
async def get_stock(
    product_id: int,
    sb: Annotated[Client, Depends(get_admin_client)],
) -> dict[str, Any]:
    """Devuelve el stock actual de un producto (consumido por el realtime del frontend)."""
    response = sb.table("products").select("id, stock").eq("id", product_id).maybe_single().execute()
    if response is None or response.data is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="Producto no encontrado")
    return response.data
