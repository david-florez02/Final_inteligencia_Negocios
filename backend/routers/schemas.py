"""Modelos Pydantic compartidos por los routers de la API."""
from pydantic import BaseModel, Field


class ProductBase(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    description: str | None = None
    price: float = Field(..., ge=0)
    stock: int = Field(..., ge=0)
    category_id: int | None = None
    image_url: str | None = None


class ProductCreate(ProductBase):
    pass


class ProductUpdate(BaseModel):
    name: str | None = Field(None, min_length=1, max_length=200)
    description: str | None = None
    price: float | None = Field(None, ge=0)
    stock: int | None = Field(None, ge=0)
    category_id: int | None = None
    image_url: str | None = None


class Product(ProductBase):
    id: int


class Category(BaseModel):
    id: int
    name: str
    description: str | None = None


class ProfileUpdate(BaseModel):
    full_name: str | None = Field(None, max_length=100)
    phone: str | None = Field(None, max_length=20)
    address: str | None = None


class Profile(ProfileUpdate):
    id: str
    role: str


class CartItem(BaseModel):
    product_id: int
    quantity: int = Field(..., gt=0)


class CheckoutRequest(BaseModel):
    items: list[CartItem] = Field(..., min_length=1)


class OrderStatusUpdate(BaseModel):
    status: str = Field(..., pattern="^(pending|processing|shipped|delivered|cancelled)$")


class SalesMetrics(BaseModel):
    total_orders: int
    total_revenue: float
    orders_by_status: dict[str, int]
    top_products: list[dict]
