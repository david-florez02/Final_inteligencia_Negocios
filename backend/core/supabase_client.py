"""Cliente Supabase compartido para toda la aplicación."""
from supabase import Client, create_client

from core.config import settings

_admin_client: Client | None = None


def get_admin_client() -> Client:
    """Devuelve el cliente con service_role (bypass RLS) para tareas administrativas."""
    global _admin_client
    if _admin_client is None:
        _admin_client = create_client(settings.SUPABASE_URL, settings.SUPABASE_SERVICE_ROLE_KEY)
    return _admin_client
