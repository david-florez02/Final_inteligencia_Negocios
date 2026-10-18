# E-Commerce Tecnológico Modular

E-commerce completo con Angular (frontend), FastAPI (backend) y Supabase (base de datos, Auth y Realtime).

## Descripción de la solución

**Problema que resuelve** — Las pequeñas tiendas online de tecnología necesitan gestionar de forma integrada su catálogo, inventario, carrito y ventas sin pagar plataformas SaaS cerradas ni construir piezas inconexas por separado. Este proyecto entrega un e-commerce *full-stack* donde esas piezas comparten una única fuente de verdad (una base PostgreSQL gestionada por Supabase) y una API propia:

- **Catálogo con inventario en vivo**: el stock del panel de administración, la tarjeta del producto y el carrito se sincronizan en tiempo real vía Supabase Realtime (canales `postgres_changes`).
- **Carrito persistente** con estado reactivo (signals de Angular) guardado en `localStorage`: sobrevive recargas de página.
- **Checkout atómico**: una función SQL transaccional (con `SELECT ... FOR UPDATE`) valida stock, crea la orden, inserta sus ítems y descuenta inventario en una sola transacción, eliminando las carreras de stock típicas de "dos clientes compran la última unidad".
- **Panel de administración con métricas**: CRUD de inventario, cambio de estados de órdenes y agregados de ventas.
- **Autenticación con roles**: registro/login sobre Supabase Auth con JWT HS256 y roles `admin`/`customer`; RLS de PostgreSQL refuerza los permisos en la base.

**Público objetivo** — Tiendas de electrónica y repuestos informáticos (laptops, GPUs, CPUs) que venden online con segundo plano administrativo propio; y como referencia didáctica, equipos de desarrollo que necesiten un ejemplo completo de integración Angular + FastAPI + Supabase con operaciones transaccionales reales.

## Stack tecnológico

| Capa        | Tecnología          | Versión aproximada | Rol |
|-------------|---------------------|--------------------|-----|
| Frontend    | Angular (standalone + Signals) | 17.3 | SPA: catálogo, carrito, checkout, perfil y panel admin |
| Frontend    | Angular Material    | 17.3               | Componentes UI (toolbar, cards, formularios, snackbar, badge) |
| Frontend    | TypeScript          | ~5.3               | Lenguaje del frontend |
| Frontend    | RxJS                | 7.8                | Streams del interceptor JWT y suscripciones |
| Frontend    | supabase-js         | 2.x                | Auth del navegador y canales Realtime de stock |
| Backend     | Python              | 3.11               | Lenguaje del backend |
| Backend     | FastAPI             | ≥ 0.110            | API REST (products, orders, profile, admin) |
| Backend     | Pydantic v2 / pydantic-settings | ≥ 2.6  | Validación de esquemas y configuración |
| Backend     | supabase-py         | 2.4+               | Cliente de base de datos (service_role) y autenticación |
| Backend     | Uvicorn             | ≥ 0.27             | Servidor ASGI |
| Backend     | python-jose         | ≥ 3.3              | Validación criptográfica del JWT (HS256) |
| Base de datos | PostgreSQL (Supabase) | 17               | Tablas, RLS, triggers, `process_checkout` |
| Base de datos | Supabase Auth      | integrado          | Usuarios, sesiones JWT, proveedor email |
| Base de datos | Supabase Realtime  | integrado          | Publicación de cambios de `products` en vivo |
| Infra local | docker-free         | —                  | Supabase cloud + proxy de desarrollo Vite |

Dependencias completas: `backend/requirements.txt` (Python) y `frontend/package.json` (npm). El venv también incluye `psycopg` para tareas de administración de base de datos desde scripts (no lo consume la app).

## Estructura

```
database/      schema.sql (tablas, trigger de perfil, RLS) + seed.sql (catálogo y usuarios de prueba)
               + optimizations.sql (índices, RLS corregida, process_checkout, Realtime)
backend/       API FastAPI: core/ (config, security, cliente Supabase) y routers/ (products, orders, profile, admin)
frontend/      SPA Angular (standalone components, signals, guards, interceptor, realtime)
.opencode/     Configuración de agentes OpenCode (ver la sección 'Agentes y Skills')
```

## Instalación

> Requisitos: Python 3.11+, Node.js 18+ (npm), un navegador y una cuenta gratuita en Supabase.

### 1. Base de datos (Supabase)

1. Crea un proyecto en [supabase.com](https://supabase.com).
2. En `SQL Editor` ejecuta, **en este orden**: `database/schema.sql`, `database/seed.sql` y `database/optimizations.sql`.
   - `schema.sql` **no** es idempotente: solo debe aplicarse en una base limpia.
   - `seed.sql` y `optimizations.sql` **son** idempotentes y pueden re-ejecutarse sin daño.
3. Copia de `Settings > API`: la URL del proyecto, la `anon key` y la `service_role key`.

> `optimizations.sql` es **obligatorio**: corrige la recursión infinita de las políticas RLS
> (error `42P17`), añade los índices de rendimiento, publica `products` en Realtime y crea
> la función atómica `public.process_checkout` que usa el checkout.

### 2. Backend (FastAPI)

```powershell
cd backend
copy ..\.env.example .env   # o crea el archivo manualmente con tus credenciales
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn main:app --reload
```

Las 4 variables obligatorias (`SUPABASE_URL`, `SUPABASE_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWT_SECRET`) están descritas en `.env.example`; el backend carga `backend/.env` y luego el `.env` de la raíz (el de la raíz gana si existen ambos).

La documentación interactiva queda en http://localhost:8000/docs.

### 3. Frontend (Angular)

```powershell
cd frontend
npm install                    # instala @angular/material, supabase-js, etc.
npm start
```

Copia en `src/environments/environment.ts` la URL del proyecto y su `anon key` (variables de entorno reales del archivo `.env` de tu proyecto Supabase; el frontend no lee archivos `.env`).

La app corre en http://localhost:4200 con proxy hacia el backend en el puerto 8000 (`src/proxy.conf.js` reescribe `^/api`).

### 4. Entorno de OpenCode (opcional)

Para trabajar con la misma configuración de agentes que se usó en el desarrollo del proyecto:

1. Instala [OpenCode](https://opencode.ai) en la máquina.
2. Abre OpenCode directamente en la carpeta raíz del proyecto — carga automáticamente la siguiente configuración:
   - `AGENTS.md` (raíz): instrucciones del repo para los agentes (comandos, trampas, convenciones).
   - `.opencode/agents/*.md`: agentes especializados con frontmatter `description`, `mode` y reglas `permissions` para `subagent`.
   - `.agents/skills/` con `skills-lock.json`: skills vendidas con hash fijado para reproducibilidad.
3. Al menos un servidor MCP debe estar configurado para que los agentes consulten documentación de librerías: **Context7** (ver la tabla de abajo). Consúltalo en tu archivo de configuración global o de proyecto de OpenCode.

Verifica la instalación rápida: `backend` debe contar `16` rutas y el frontend construir sin errores (`ng build`).

## Cuentas de prueba

El archivo `database/seed.sql` crea **6 usuarios** con la contraseña común `Password123!`:

| Cuenta              | Email                        | Contraseña    | Rol      |
|---------------------|------------------------------|---------------|----------|
| Administrador       | admin@techshop.com           | Password123!  | admin    |
| Cliente de prueba   | cliente@techshop.com         | Password123!  | customer |
| Cliente (QA) 1      | maria.gonzalez@techshop.com  | Password123!  | customer |
| Cliente (QA) 2      | carlos.perez@techshop.com    | Password123!  | customer |
| Cliente (QA) 3      | lucia.fernandez@techshop.com | Password123!  | customer |
| Cliente (QA) 4      | diego.martinez@techshop.com  | Password123!  | customer |

Ingresa con esas credenciales en /login: el admin verá además el enlace al panel /admin; los clientes solo el catálogo, carrito, checkout y su perfil.

### Endpoints principales

| Método | Ruta                  | Descripción                              | Rol mínimo |
|--------|-----------------------|------------------------------------------|------------|
| GET    | /products             | Catálogo con filtros y búsqueda          | público    |
| GET    | /products/{id}        | Detalle de producto                      | público    |
| GET    | /products/categories  | Categorías                               | público    |
| POST   | /orders/checkout      | Checkout atómico vía RPC (valida y descuenta stock) | cliente |
| GET    | /orders/me            | Órdenes del cliente                      | cliente    |
| GET    | /profile/me           | Perfil del usuario autenticado           | cliente    |
| PUT    | /profile/me           | Actualiza perfil                         | cliente    |
| GET    | /profile/me/orders    | Historial de compras                     | cliente    |
| POST   | /admin/products       | Crear producto                           | admin      |
| PUT    | /admin/products/{id}  | Editar producto / stock                  | admin      |
| DELETE | /admin/products/{id}  | Eliminar producto                        | admin      |
| GET    | /admin/orders         | Todas las órdenes con cliente            | admin      |
| PATCH  | /admin/orders/{id}/status | Cambiar estado de una orden          | admin      |
| GET    | /admin/metrics        | Métricas de ventas                       | admin      |

### Códigos de error del checkout

`POST /orders/checkout` invoca la función atómica `public.process_checkout` y traduce
sus SQLSTATE a HTTP:

| SQLSTATE | HTTP | Causa                                            |
|----------|------|--------------------------------------------------|
| `22023`  | 400  | Carrito vacío o ítem malformado                  |
| `23503`  | 400  | Usuario inexistente en `users_profile`            |
| `P0002`  | 404  | Producto inexistente                             |
| `42501`  | 403  | Intento de crear una orden para otro usuario     |
| `23514`  | 409  | Stock insuficiente                               |
| `PGRST202` | 503 | Falta aplicar `database/optimizations.sql`       |

## Flujo end-to-end

1. Registro: crea el usuario en Supabase Auth; el trigger `on_auth_user_created` inserta automáticamente su fila en `users_profile` con rol `customer` y el `full_name` de los metadatos.
2. Login: `SupabaseService` guarda la sesión; el interceptor HTTP adjunta el JWT a cada petición del backend.
3. Catálogo y carrito: gestionados con Angular Signals; cualquier cambio de stock se recibe en tiempo real vía canales de Supabase Realtime.
4. Checkout: `POST /api/orders/checkout` valida stock, registra la orden, crea los ítems y descuenta inventario de forma transaccional.
5. Perfil: `ProfileComponent` edita los datos y muestra el historial con sus ítems.
6. Admin: `AdminDashboardComponent` permite CRUD de inventario, cambiar estados (pending → processing → shipped → delivered) y ver métricas agregadas.

## Agentes y Skills (diseño OpenCode)

Los agentes especializados del proyecto viven en `.opencode/agents/*.md` con frontmatter `description` + `mode` (las `description` van **entre comillas**: un `:` suelto invalida el YAML):

| Agente                               | Responsabilidad                                                            |
|--------------------------------------|----------------------------------------------------------------------------|
| `orquestador.md` (`mode: primary`)   | Planifica por fases, delega y valida la integración end-to-end; sus bloques `permissions` controlan a qué `subagent` puede lanzar |
| `agente-base-de-datos.md`            | DDL idempotente, triggers, RLS y funciones SQL (`process_checkout`)         |
| `agente-backend.md`                  | FastAPI modular, Pydantic v2, RPC del checkout                              |
| `agente-frontend.md`                 | Angular standalone + signals, guards, interceptor JWT, carrito              |
| `autenticacion-y-control-de-accesos.md` | JWT (HS256), roles por `app_metadata`, mínimo privilegio                 |
| `qa-y-pruebas.md`                    | Scripts E2E (`pytest`-like) para Login/Perfil/Checkout/Admin                |
| `configuracion-y-despliegue.md`      | Variables de entorno, arranque, reproducibilidad del entorno                |

Estas restricciones globales aplican a todos los agentes (archivo `.opencode/agents/agent.md`): consultar la documentación con Context7 antes de asumir APIs, y está **prohibido** entregar código incompleto, `TODO` o datos simulados.

### Skills usadas

Las skills están vendidas en `.agents/skills/` y fijadas por hash en `skills-lock.json`:

| Skill                      | Fuente      | Justificación en este proyecto                                              |
|----------------------------|-------------|------------------------------------------------------------------------------|
| `angular-developer`        | `angular/angular` | Componentes standalone, signals, guards e interceptor con el patrón oficial vigente |
| `python-fastapi-development` | `sickn33/agentic-awesome-skills` | Buenas prácticas de routers async y Pydantic v2                              |
| `supabase`                 | `supabase/agent-skills` | RLS, Auth, Realtime y cliente oficial                                       |

### Servidores MCP

| MCP      | Estado          | Uso en el proyecto                                                      |
|----------|-----------------|--------------------------------------------------------------------------|
| Context7 | ✅ disponible   | Consulta la documentación vigente de Angular/FastAPI/Supabase antes de escribir código |
| Supabase MCP/CLI | ❌ no disponible | Se sustituye validando la base de datos con `psycopg` y el SQL Editor (los scripts SQL son idempotentes).
 |
## enlace del dashboard https://drive.google.com/file/d/1Kz_yaAbBrsxGdpWzbYLXA51RzvSVCDXk/view?usp=sharing
## modelo relacional https://drive.google.com/file/d/1MWbDq80qXICCYeiQcPmrjCHHFEg9tZOO/view?usp=sharing
