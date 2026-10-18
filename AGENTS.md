# AGENTS.md

E-commerce modular: **Angular 17** (standalone + signals) + **FastAPI** + **Supabase**. Toda la
documentación, los docstrings y los agentes del repo están en español: mantén ese idioma.

No es un repositorio git (no hay `.git`): no intentes `git log`/`git diff` para investigar.

## Estructura

| Directorio | Contenido |
|---|---|
| `database/` | `schema.sql` (tablas, trigger de perfil, RLS) → `seed.sql` → `optimizations.sql` |
| `backend/` | `main.py`, `core/` (config, security, cliente Supabase), `routers/` (products, orders, profile, admin, schemas) |
| `frontend/` | SPA Angular; páginas en `src/app/page/`, servicios en `src/app/core/` |
| `.opencode/agents/` | Agentes del proyecto (ver el final de este archivo) |

## Comandos

El venv ya existe en `backend/venv`. `uvicorn` **debe** lanzarse desde `backend/` (imports
absolutos `core.*` / `routers.*`, sin `src/` layout).

```powershell
cd backend
.\venv\Scripts\python.exe -m uvicorn main:app --reload   # http://127.0.0.1:8000/docs
```

```powershell
cd frontend
npm start          # ng serve en :4200
npm run build      # ng build -> dist/techstore/browser
```

**No hay tests**: no existe pytest ni karma/jasmine y `package.json` no define script `test`.
No inventes `npm test`/`pytest`; verifica así:

```powershell
cd backend
.\venv\Scripts\python.exe -m py_compile main.py routers\orders.py
.\venv\Scripts\python.exe -c "import main; print(len(main.app.openapi()['paths']))"   # hoy: 16
```

Arrancar el servidor en un puerto de prueba y detenerlo (no hay Ctrl+C en segundo plano):

```powershell
$c = Get-NetTCPConnection -LocalPort 8123 -State Listen -ErrorAction SilentlyContinue
if ($c) { Stop-Process -Id $c.OwningProcess -Force }
```

## Configuración

- `core/config.py` carga **dos** `.env` con rutas absolutas: `backend/.env` y luego el de la raíz
  (el de la raíz gana). Las variables de entorno reales ganan a ambos. No lo hagas relativo al CWD.
- Cuatro variables, todas obligatorias para que arranque: `SUPABASE_URL`, `SUPABASE_KEY`,
  `SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_JWT_SECRET`. `SUPABASE_KEY` (anon) **no la usa el backend**,
  solo el frontend.
- El `README` manda `copy ..\.env.example .env`, pero **`.env.example` no existe**: crea el `.env`
  a mano o añade el archivo si toca ese flujo.
- El frontend **no lee variables de entorno**: la URL y la anon key viven en
  `src/environments/environment.ts`. No añadas dotenv al bundle.
- `styles.scss` (Sass) es la hoja global, no `.css`.

## Arquitectura (lo que no se ve en los nombres)

- **Todo el backend usa `service_role`** (`core/supabase_client.get_admin_client`), que **salta el
  RLS**. Un fallo de políticas RLS no aparece por la API: solo rompe el navegador, porque el
  frontend consulta Supabase directamente con la anon key (`supabase.service.ts` lee
  `users_profile` y se suscribe a `postgres_changes` sobre `products`). Verifica RLS simulando el
  rol, no con una llamada a la API.
- **No hay prefijo `/api` en el backend**: el frontend pide `/api/...` y `src/proxy.conf.js` (referenciado
  desde `angular.json`, es `.js` no `.json`) reescribe `^/api` → `http://localhost:8000`. Al añadir
  endpoints, en el backend van sin `/api`.
- Auth: `core/security.py` valida HS256 con `SUPABASE_JWT_SECRET` y, si falla, cae a
  `auth.get_user()`. Por eso el backend funciona aunque el JWT secret esté vacío (cuesta una llamada
  extra por request). Roles por `app_metadata`/`user_metadata.role` (`require_admin`).
- El frontend adjunta el JWT en un interceptor global (`jwt-interceptor.ts`): **las páginas no pasan
  cabeceras a mano**.
- Realtime de stock solo emite si `public.products` está en la publicación `supabase_realtime`
  (lo hace `optimizations.sql` §7.3). Sin eso el canal `stock-updates` queda mudo.
- Las APIs de los dos clientes Supabase difieren: en Python `maybe_single()`, en JS `maybeSingle()`.

## Base de datos

- Orden obligatorio en el SQL Editor: `schema.sql` → `seed.sql` → `optimizations.sql`.
  `optimizations.sql` **no es opcional**: corrige la recursión infinita de RLS (`42P17`) que trae
  `schema.sql`, crea `public.process_checkout` y publica Realtime.
- Idempotencia: `seed.sql` y `optimizations.sql` se pueden re-ejecutar sin daño; **`schema.sql` no**
  (usa `CREATE TABLE`/`CREATE POLICY` sin `IF NOT EXISTS`), así que solo en una base limpia.
- El checkout **debe** ir por la función SQL, no por inserts sueltos:
  `sb.rpc("process_checkout", {"p_user_id": ..., "p_items": [...]})`. Traduce sus SQLSTATE a HTTP
  (tabla en el `README`). Si falta el script → `PGRST202` → 503.
- Trampas al probar el checkout: carrito vacío da **422** (lo corta Pydantic antes de la BD), y
  `quantity > 100000` da **400** ("item inválido"), no 409. Para provocar el 409 pide `stock + 1`.
- `orders.user_id` puede ser NULL: `user_id = NULL` **nunca** es TRUE en SQL. Guardo siempre contra
  ese caso en los scripts (ya costó una orden huérfana en el seed).
- Al tocar `seed.sql`: `auth.users.phone` debe ir **NULL** (el índice único `users_phone_key` hace que
  un `''` duplique y `ON CONFLICT DO NOTHING` descarte el usuario en silencio), y el insert de
  productos va con `WHERE NOT EXISTS` porque **`products.name` no es UNIQUE** (`categories.name` sí).
- `updated_at` lo mantienen triggers de `optimizations.sql` (§6); no escribas timestamps a mano.
- El venv tiene `psycopg` instalado **fuera** de `requirements.txt` (se usó para aplicar los scripts
  SQL sin el panel). Para trabajo de BD puedes conectar con el `DATABASE_URL` del `.env`.

## Restricciones y entorno

- **Prohibido** entregar código incompleto: ni `TODO`, ni placeholders, ni datos simulados
  (restricción global en `.opencode/agents/agent.md`).
- Consulta la documentación vigente con **Context7** antes de asumir APIs de memoria. El **MCP/CLI de
  Supabase no está disponible** en este entorno (solo Context7), aunque `agent.md` los mencione:
  valida la BD ejecutando los scripts SQL o con `psycopg`, no esperes ese MCP.
- Shell **PowerShell (Windows)**: no encadenes con `&&` (usa líneas separadas) y evita `python -c "..."`
  con comillas anidadas — se rompe. Escribe un `.py` en `C:\Users\david\AppData\Local\Temp\opencode`
  y ejecútalo.
- Agentes del repo en `.opencode/agents/*.md`: markdown con frontmatter `description` + `mode`
  (**cita siempre la `description`**, un `:` sin comillas invalida el YAML). `orquestador.md` es
  `primary` y necesita sus reglas `permissions` para lanzar `subagent`. Las skills están vendorizadas
  en `.agents/skills/` y fijadas en `skills-lock.json`.
