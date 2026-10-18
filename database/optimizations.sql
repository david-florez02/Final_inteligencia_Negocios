-- ============================================================================
--  E-COMMERCE TECNOLOGICO - OPTIMIZACIONES DE BASE DE DATOS (Supabase/Postgres)
--  Archivo: database/optimizations.sql
--  Autor  : Agente DBA & Optimizador de Supabase
--  Linea base: database/schema.sql (NO se modifica; este script lo complementa)
-- ----------------------------------------------------------------------------
--  OBJETIVO
--    1. Auditoria + endurecimiento de RLS (evitar recursión y evaluaciones por
--       fila; usar el patron (select auth.uid()) recomendado por Supabase).
--    2. Indexacion de todas las claves foraneas + indices para los filtros del
--       backend (status, created_at, busqueda ILIKE con pg_trgm).
--    3. Integridad: CHECKs idempotentes, trigger de updated_at, constraints
--       extra y proteccion de campos sensibles de orders.
--    4. Funcion atomica de compra: public.process_checkout(uuid, jsonb).
--
--  IDEMPOTENCIA Y ATOMICIDAD DEL SCRIPT
--    - Solo usa IF NOT EXISTS / CREATE OR REPLACE / DROP ... IF EXISTS.
--    - Todo el script va dentro de BEGIN ... COMMIT: si una sentencia falla,
--      no se aplica nada (evita estados intermedios).
--      Nota: si se ejecuta con `supabase db push` el runner ya abre una
--      transaccion; el BEGIN anidado solo genera un WARNING inofensivo.
--    - Es seguro aplicarlo sobre una base que ya ejecuto schema.sql y seed.sql.
--
--  REFERENCIAS CONSULTADAS (Context7)
--    - Supabase - "Row Level Security / Avoid recursive policies" y
--      "RLS performance and best practices":
--        * envolver auth.uid() en (select ...) para que el planificador lo
--          ejecute como InitPlan (una sola vez por consulta, no por fila);
--        * usar funciones SECURITY DEFINER para consultar otras tablas y
--          romper la recursión entre politicas (error 42P17);
--        * indexar las columnas usadas en las politicas (mejora >100x).
--        https://supabase.com/docs/guides/database/postgres/row-level-security
--        https://supabase.com/docs/guides/troubleshooting/rls-performance-and-best-practices-Z5Jjwv
--    - PostgreSQL 17 - "Row-Level Locks" (SELECT ... FOR UPDATE) y pg_trgm
--      (GIN + gin_trgm_ops acelera LIKE/ILIKE sin anclaje):
--        https://www.postgresql.org/docs/17/explicit-locking.html
--        https://www.postgresql.org/docs/17/pgtrgm.html
-- ============================================================================

BEGIN;

-- ============================================================================
-- SECCION 0. AUDITORIA DE TIPOS DE DATOS (verificacion, no muta datos)
-- ----------------------------------------------------------------------------
--  Estado verificado sobre database/schema.sql (todos correctos, no requieren
--  ALTER TYPE; se deja un chequeo activo al final del script):
--    categories.id            SERIAL (integer)          -> PK de catalogo
--    categories.name          VARCHAR(100) NOT NULL UNIQUE
--    categories.description   TEXT                      -> OK (texto libre)
--    products.id              SERIAL (integer)
--    products.name            VARCHAR(200) NOT NULL
--    products.description     TEXT                      -> OK
--    products.price           DECIMAL(10,2) CHECK >= 0  -> OK (numeric exacto)
--    products.stock           INTEGER DEFAULT 0 CHECK >= 0
--    products.category_id     INTEGER REFERENCES categories(id)  -> FK indexable
--    users_profile.id         UUID PRIMARY KEY REFERENCES auth.users(id)
--    products/orders timestamps  TIMESTAMP WITH TIME ZONE (== timestamptz) OK
--    orders.total_amount      DECIMAL(10,2) CHECK >= 0
--    order_items.quantity     INTEGER CHECK > 0
--    order_items.unit_price   DECIMAL(10,2) CHECK >= 0
--    order_items.total_price  DECIMAL(10,2) CHECK >= 0
--  Decision: NO se convierten tipos. Cambiar el tipo de una columna obliga a
--  reescribir la tabla y a detener lecturas; no aporta valor aqui porque los
--  tipos ya cumplen el contrato (UUID para identidades de usuario, numeric(10,2)
--  para dinero, integer para stock/cantidad, timestamptz para fechas, text para
--  descripciones). Lo unico que se anade es el chequeo automatico final.
-- ============================================================================


-- ============================================================================
-- SECCION 1. EXTENSIONES
-- ============================================================================

-- pg_trgm habilita indices GIN de trigramas para busquedas ILIKE '%texto%'.
-- En Supabase las extensiones se instalan por defecto en el esquema
-- `extensions`, por eso el indice de la Seccion 4 resuelve el esquema en
-- tiempo de ejecucion en lugar de asumir `public`.
CREATE EXTENSION IF NOT EXISTS pg_trgm;


-- ============================================================================
-- SECCION 2. FUNCIONES AUXILIARES DE AUTORIZACION (SECURITY DEFINER)
-- ----------------------------------------------------------------------------
--  PROBLEMA DETECTADO EN schema.sql
--    a) Las politicas de users_profile consultan users_profile dentro de su
--       propia politica:
--          EXISTS (SELECT 1 FROM users_profile WHERE id = auth.uid() AND role='admin')
--       Es una referencia a la misma tabla protegida -> Postgres la evalua
--       aplicando de nuevo las politicas de users_profile. En cuanto una de
--       esas politicas necesite la misma comprobacion aparece el error
--          42P17: infinite recursion detected in policy for relation.
--       Ademas, sin indice la subconsulta se repite una vez por fila.
--    b) auth.uid() se llamaba sin envolver: se evalua por FILA, no por consulta.
--    c) La misma comprobacion "es admin" estaba duplicada con EXISTS
--       correlacionados en orders y order_items (muchas filas x subconsulta).
--
--  SOLUCION (patron oficial de Supabase)
--    Funciones SQL SECURITY DEFINER, STABLE, con search_path fijado, que leen
--    users_profile como su PROPIETARIO (postgres, con BYPASSRLS en Supabase)
--    de modo que la comprobacion no vuelve a disparar las politicas de
--    users_profile: se rompe la recursion y la comprobacion se hace una sola
--    vez (STABLE permite al planificador cachear el resultado por consulta).
--
--  NOTA DE SEGURIDAD: auth.uid() lee el claim `sub` del JWT desde los ajustes
--  de sesion (request.jwt.claims); es independiente de SET ROLE, por lo que
--  sigue devolviendo el usuario autenticado aunque la funcion se ejecute como
--  el propietario. Estas funciones devuelven unicamente informacion del propio
--  invocador (su rol / su orden), por lo que exponerlas no filtra datos: como
--  maximo revelan "soy admin" o "soy dueno de la orden X" al propio usuario.
-- ============================================================================

-- 2.1 ¿El invocador es administrador?
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.users_profile AS up
        WHERE up.id = (SELECT auth.uid())
          AND up.role = 'admin'
    );
$$;

COMMENT ON FUNCTION public.is_admin() IS
    'TRUE si el usuario del JWT actual tiene rol admin en users_profile. SECURITY DEFINER + STABLE para evitar recursion en RLS (42P17) y evaluarse una vez por consulta.';

-- 2.2 ¿El invocador es cliente (customer)?
CREATE OR REPLACE FUNCTION public.is_customer()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.users_profile AS up
        WHERE up.id = (SELECT auth.uid())
          AND up.role = 'customer'
    );
$$;

COMMENT ON FUNCTION public.is_customer() IS
    'TRUE si el usuario del JWT actual tiene rol customer en users_profile. Usada por las politicas de perfil propio.';

-- 2.3 ¿La orden pertenece al invocador?
--     Se usa en order_items para no repetir
--     `EXISTS (SELECT 1 FROM orders WHERE orders.user_id = auth.uid())`
--     fila por fila y, sobre todo, para no re-evaluar las politicas de orders
--     dentro de las politicas de order_items.
CREATE OR REPLACE FUNCTION public.owns_order(p_order_id INTEGER)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.orders AS o
        WHERE o.id = p_order_id
          AND o.user_id = (SELECT auth.uid())
    );
$$;

COMMENT ON FUNCTION public.owns_order(integer) IS
    'TRUE si la orden p_order_id pertenece al usuario del JWT actual. Rompe el EXISTS correlacionado sobre orders en las politicas de order_items.';

-- 2.4 Permisos de las funciones auxiliares.
--     - Se revoca de PUBLIC para no dejar EXECUTE abierto a cualquiera.
--     - Se concede explicitamente a anon: las politicas "FOR ALL" de
--       categories/products incluyen la expresion (select public.is_admin())
--       y Postgres exige privilegio EXECUTE al rol que evalua la politica.
--       Sin este GRANT, una consulta anonima al catalogo publico fallaria con
--       42501 (permission denied for function is_admin) en lugar de devolver
--       el catalogo. is_admin() devuelve FALSE para anon (auth.uid() IS NULL),
--       por lo que no hay fuga de informacion.
REVOKE ALL ON FUNCTION public.is_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.is_customer() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.owns_order(INTEGER) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.is_admin() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_customer() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.owns_order(INTEGER) TO anon, authenticated, service_role;


-- ============================================================================
-- SECCION 3. ROW LEVEL SECURITY: HABILITACION Y POLITICAS OPTIMIZADAS
-- ============================================================================

-- 3.1 RLS habilitado en las 5 tablas (idempotente: re-ejecutarlo no cambia nada).
ALTER TABLE public.categories    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users_profile ENABLE ROW LEVEL SECURITY;

-- 3.2 FORCE ROW LEVEL SECURITY.
--     Aplica RLS tambien al propietario de la tabla (defensa en profundidad por
--     si algun dia se opera con el rol `postgres` desde una herramienta).
--     Los roles con atributo BYPASSRLS (service_role y postgres en Supabase)
--     siguen ignorando RLS: por eso el backend FastAPI, que usa el cliente
--     service_role (backend/core/supabase_client.py), no cambia su
--     comportamiento y sigue viendo/gestionando todo.
ALTER TABLE public.categories  FORCE ROW LEVEL SECURITY;
ALTER TABLE public.products    FORCE ROW LEVEL SECURITY;
ALTER TABLE public.orders      FORCE ROW LEVEL SECURITY;
ALTER TABLE public.order_items FORCE ROW LEVEL SECURITY;

-- users_profile NO se fuerza, de forma deliberada y documentada:
--   1) public.is_admin() / public.is_customer() son SECURITY DEFINER y leen
--      users_profile; si se aplicara FORCE sobre esa tabla, la lectura volveria
--      a evaluar las politicas de users_profile y se recuperaria la recursion
--      (42P17) en entornos donde el propietario no tuviera BYPASSRLS.
--   2) El trigger on_auth_user_created -> public.handle_new_user()
--      (SECURITY DEFINER, definido en schema.sql) se ejecuta al crear usuarios
--      en auth.users e inserta en users_profile; FORCE obligaria a mantener una
--      politica de INSERT especial solo para el alta de cuentas.
--   3) La proteccion del perfil no depende de FORCE: los roles de API
--      (anon/authenticated) SIEMPRE pasan por RLS con ENABLE ROW LEVEL SECURITY.

-- ----------------------------------------------------------------------------
-- 3.3 Reescritura de politicas
--     Patron aplicado en todas:
--        * (select auth.uid())     -> una sola evaluacion por consulta (InitPlan)
--        * (select public.is_admin()) -> sin recursión, sin EXISTS repetidos
--        * USING (lectura/update/delete) + WITH CHECK (insert/update) explicitos
--        * TO <rol> para dejar claro a que roles aplican
--     Se eliminan primero las politicas antiguas (mismo nombre que schema.sql)
--     para poder re-ejecutar el script sin duplicarlas.
-- ----------------------------------------------------------------------------

-- ------------------------------ users_profile -------------------------------
DROP POLICY IF EXISTS "Users can view own profile"     ON public.users_profile;
DROP POLICY IF EXISTS "Users can update own profile"   ON public.users_profile;
DROP POLICY IF EXISTS "Admins can manage all profiles" ON public.users_profile;
-- (nombres nuevos de esta optimizacion, por idempotencia)
DROP POLICY IF EXISTS "Users can insert own profile"   ON public.users_profile;
DROP POLICY IF EXISTS "Users can delete own profile"   ON public.users_profile;

-- SELECT: cada usuario lee su propio perfil.
CREATE POLICY "Users can view own profile" ON public.users_profile
    FOR SELECT
    TO authenticated
    USING ((SELECT auth.uid()) = id);

-- INSERT: alta de perfil por el propio usuario.
--   WITH CHECK restringe role a 'customer' para impedir auto-ascenso a admin
--   via API (escalada de privilegios). El rol admin solo lo puede asignar un
--   admin o el flujo de signup (raw_app_meta_data, no manipulable por el
--   cliente desde signUp) a traves del trigger SECURITY DEFINER.
CREATE POLICY "Users can insert own profile" ON public.users_profile
    FOR INSERT
    TO authenticated
    WITH CHECK (
        (SELECT auth.uid()) = id
        AND role = 'customer'
    );

-- UPDATE: el usuario edita sus datos, pero no su rol ni su id.
CREATE POLICY "Users can update own profile" ON public.users_profile
    FOR UPDATE
    TO authenticated
    USING ((SELECT auth.uid()) = id)
    WITH CHECK (
        (SELECT auth.uid()) = id
        AND role = 'customer'
    );

-- DELETE: el borrado de cuenta se hace desde auth.users (ON DELETE CASCADE).
--   Se deja la politica explicita solo para el propio usuario, de modo que la
--   API nunca borre perfiles de terceros.
CREATE POLICY "Users can delete own profile" ON public.users_profile
    FOR DELETE
    TO authenticated
    USING ((SELECT auth.uid()) = id);

-- ALL: el administrador tiene acceso global (SELECT/INSERT/UPDATE/DELETE).
--   Usa la funcion SECURITY DEFINER => sin recursion sobre users_profile.
CREATE POLICY "Admins can manage all profiles" ON public.users_profile
    FOR ALL
    TO authenticated
    USING ((SELECT public.is_admin()))
    WITH CHECK ((SELECT public.is_admin()));

-- -------------------------------- categories --------------------------------
DROP POLICY IF EXISTS "Anyone can view categories"  ON public.categories;
DROP POLICY IF EXISTS "Admins can manage categories" ON public.categories;

-- Catalogo publico: lectura para anon (catalogo sin sesion) y authenticated.
CREATE POLICY "Anyone can view categories" ON public.categories
    FOR SELECT
    TO anon, authenticated
    USING (true);

-- Escritura exclusiva del admin (INSERT/SELECT/UPDATE/DELETE).
CREATE POLICY "Admins can manage categories" ON public.categories
    FOR ALL
    TO authenticated
    USING ((SELECT public.is_admin()))
    WITH CHECK ((SELECT public.is_admin()));

-- --------------------------------- products ---------------------------------
DROP POLICY IF EXISTS "Anyone can view products"  ON public.products;
DROP POLICY IF EXISTS "Admins can manage products" ON public.products;

CREATE POLICY "Anyone can view products" ON public.products
    FOR SELECT
    TO anon, authenticated
    USING (true);

-- El stock se descuenta SOLO desde public.process_checkout (SECURITY DEFINER),
-- nunca con un UPDATE directo del cliente: asi no se puede vender sin pagar el
-- precio real ni dejar el stock negativo desde la API.
CREATE POLICY "Admins can manage products" ON public.products
    FOR ALL
    TO authenticated
    USING ((SELECT public.is_admin()))
    WITH CHECK ((SELECT public.is_admin()));

-- ---------------------------------- orders ----------------------------------
DROP POLICY IF EXISTS "Users can view own orders"          ON public.orders;
DROP POLICY IF EXISTS "Users can insert own orders"        ON public.orders;
DROP POLICY IF EXISTS "Users can cancel own pending orders" ON public.orders;
DROP POLICY IF EXISTS "Admins can manage all orders"       ON public.orders;

-- SELECT: el cliente ve solo sus ordenes (user_id esta indexado -> Seccion 4).
CREATE POLICY "Users can view own orders" ON public.orders
    FOR SELECT
    TO authenticated
    USING (user_id = (SELECT auth.uid()));

-- INSERT: el cliente solo puede crear ordenes a su nombre.
CREATE POLICY "Users can insert own orders" ON public.orders
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = (SELECT auth.uid()));

-- UPDATE: el cliente solo puede tocar ordenes propias en estado 'pending'.
--   WITH CHECK limita el estado destino a 'pending'/'cancelled'.
--   La integridad de columnas (no tocar total_amount ni user_id) la garantiza
--   el trigger public.protect_order_fields() de la Seccion 5, porque RLS no
--   puede restringir columnas.
CREATE POLICY "Users can cancel own pending orders" ON public.orders
    FOR UPDATE
    TO authenticated
    USING (
        user_id = (SELECT auth.uid())
        AND status = 'pending'
    )
    WITH CHECK (
        user_id = (SELECT auth.uid())
        AND status IN ('pending', 'cancelled')
    );

-- ALL: acceso global del administrador (incluye el cambio de estado de
--   /admin/orders/{id}/status y cualquier borrado administrativo).
CREATE POLICY "Admins can manage all orders" ON public.orders
    FOR ALL
    TO authenticated
    USING ((SELECT public.is_admin()))
    WITH CHECK ((SELECT public.is_admin()));

-- -------------------------------- order_items -------------------------------
DROP POLICY IF EXISTS "Users can view own order items"   ON public.order_items;
DROP POLICY IF EXISTS "Users can insert own order items" ON public.order_items;
DROP POLICY IF EXISTS "Admins can manage all order items" ON public.order_items;

-- SELECT: visibilidad heredada de la orden, resuelta con la funcion
--   SECURITY DEFINER (1 sola llamada por fila, sin re-evaluar RLS de orders y
--   sin recursión). No se envuelve en (select ...) porque depende de la fila
--   (order_id): el planificador no podria cachearla.
CREATE POLICY "Users can view own order items" ON public.order_items
    FOR SELECT
    TO authenticated
    USING (
        (SELECT public.is_admin())
        OR public.owns_order(order_id)
    );

-- INSERT: el cliente solo inserta items dentro de una orden suya.
--   Se mantiene por compatibilidad con el backend actual (que inserta items en
--   llamadas separadas). Una vez el backend use public.process_checkout, esta
--   politica puede retirarse para que los items SOLO se creen desde la funcion
--   atomica (que valida stock y precio reales del catalogo).
CREATE POLICY "Users can insert own order items" ON public.order_items
    FOR INSERT
    TO authenticated
    WITH CHECK (public.owns_order(order_id));

-- ALL: acceso global del administrador.
CREATE POLICY "Admins can manage all order items" ON public.order_items
    FOR ALL
    TO authenticated
    USING ((SELECT public.is_admin()))
    WITH CHECK ((SELECT public.is_admin()));

-- ----------------------------------------------------------------------------
-- 3.4 Resumen de cobertura por operacion (que puede hacer cada rol)
--   anon         : SELECT categories, products (catalogo publico).
--   customer     : SELECT/UPDATE/DELETE su propio users_profile;
--                  SELECT sus orders; INSERT orders propias;
--                  UPDATE orders propias solo 'pending' -> 'cancelled';
--                  SELECT/INSERT order_items de sus ordenes.
--   admin        : ALL (SELECT/INSERT/UPDATE/DELETE) en users_profile,
--                  categories, products, orders y order_items.
--   service_role : todo (BYPASSRLS): lo usa el backend FastAPI.
-- ----------------------------------------------------------------------------


-- ============================================================================
-- SECCION 4. INDEXACION Y RENDIMIENTO
-- ----------------------------------------------------------------------------
--  Regla de RLS performance (Supabase): toda columna usada en la clausula USING
--  de una politica debe estar indexada; sobre tablas grandes la mejora supera
--  el 100x porque evita el Seq Scan por cada fila evaluada.
-- ============================================================================

-- 4.1 Claves foraneas (todas indexadas; idx_orders_user_id ya existe en
--     schema.sql, por eso se crea de nuevo como no-op con IF NOT EXISTS y NO se
--     duplica con otro nombre).
CREATE INDEX IF NOT EXISTS idx_orders_user_id        ON public.orders (user_id);
CREATE INDEX IF NOT EXISTS idx_products_category_id  ON public.products (category_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id  ON public.order_items (order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id ON public.order_items (product_id);

-- 4.2 Indices para los filtros reales del backend.
--     orders(status): filtro del panel admin (routers/admin.py).
CREATE INDEX IF NOT EXISTS idx_orders_status       ON public.orders (status);
--     orders(created_at DESC): historial paginado y metricas por fecha.
CREATE INDEX IF NOT EXISTS idx_orders_created_at_desc ON public.orders (created_at DESC NULLS LAST);
--     Historial del cliente: GET /orders/me hace
--     .eq('user_id', x).order('created_at', desc=True).
--     Este indice compuesto cubre filtro + ordenamiento (evita el Sort).
--     TRADE-OFF: deja redundante el indice simple idx_orders_user_id; se
--     mantiene intacto para no romper nada y porque solo 2 columnas integer/uuid
--     tienen coste de escritura bajo. Si mas adelante se quiere limpiar:
--       DROP INDEX CONCURRENTLY public.idx_orders_user_id;
CREATE INDEX IF NOT EXISTS idx_orders_user_id_created_at
    ON public.orders (user_id, created_at DESC);
--     products(name) B-tree: busquedas/orden por nombre exacto o por prefijo.
CREATE INDEX IF NOT EXISTS idx_products_name        ON public.products (name);

-- 4.3 Busqueda del catalogo ILIKE '%texto%' -> GIN con pg_trgm.
--     TRADE-OFF documentado:
--       + Permite usar el indice en LIKE/ILIKE sin anclaje a la izquierda
--         (un B-tree normal NO puede: solo sirve para 'prefijo%').
--       + A partir de unas decenas de miles de filas la diferencia frente al
--         Seq Scan es enorme y baja las lecturas del catalogo.
--       - El indice es mas grande (aprox. 2-3x el tamano del texto indexado) y
--         anade coste de escritura en cada INSERT/UPDATE de products (que aqui
--         es de baja frecuencia: catalogo administrado por un admin).
--       - Necesita al menos 3 caracteres en el termino de busqueda para aportar
--         trigramas utiles; para terminos de 1-2 caracteres el planificador
--         volvera al Seq Scan (y eso esta bien, el catalogo es pequeno).
--       - Con el seed actual (10 productos) el planificador casi siempre
--         preferira Seq Scan; el indice es una inversion a futuro.
--     El esquema de la extension se resuelve en runtime porque Supabase instala
--     pg_trgm en `extensions` y no en `public`.
DO $$
DECLARE
    v_ext_schema TEXT;
BEGIN
    SELECT n.nspname INTO v_ext_schema
    FROM pg_extension e
    JOIN pg_namespace n ON n.oid = e.extnamespace
    WHERE e.extname = 'pg_trgm';

    IF v_ext_schema IS NULL THEN
        EXECUTE 'CREATE EXTENSION IF NOT EXISTS pg_trgm';
        SELECT n.nspname INTO v_ext_schema
        FROM pg_extension e
        JOIN pg_namespace n ON n.oid = e.extnamespace
        WHERE e.extname = 'pg_trgm';
    END IF;

    EXECUTE format(
        'CREATE INDEX IF NOT EXISTS idx_products_name_trgm
             ON public.products USING GIN (name %I.gin_trgm_ops)',
        v_ext_schema
    );
    RAISE NOTICE 'pg_trgm disponible en el esquema "%": indice GIN idx_products_name_trgm listo.', v_ext_schema;
END $$;

-- 4.4 Indice NO creado a proposito: users_profile(role).
--     is_admin()/is_customer() filtran por la PK (id) y luego por role; con la
--     PK el acceso ya es O(1). Un indice por role solo agregaria coste de
--     escritura en cada alta de usuario sin beneficio medible.


-- ============================================================================
-- SECCION 5. INTEGRIDAD: CHECKs, updated_at Y PROTECCION DE CAMPOS
-- ============================================================================

-- 5.1 CHECKs.
--     Los de schema.sql ya existen con el nombre autogenerado de Postgres
--     (<tabla>_<columna>_check). Se re-declaran dentro de un DO idempotente que
--     comprueba el catalogo pg_constraint: si ya existen NO se duplican, si
--     faltan se crean. Asi el script sella la integridad sin romperse cuando
--     schema.sql ya los creo.
DO $$
BEGIN
    -- products
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'products_price_check' AND conrelid = 'public.products'::regclass) THEN
        ALTER TABLE public.products ADD CONSTRAINT products_price_check CHECK (price >= 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'products_stock_check' AND conrelid = 'public.products'::regclass) THEN
        ALTER TABLE public.products ADD CONSTRAINT products_stock_check CHECK (stock >= 0);
    END IF;
    -- orders
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'orders_total_amount_check' AND conrelid = 'public.orders'::regclass) THEN
        ALTER TABLE public.orders ADD CONSTRAINT orders_total_amount_check CHECK (total_amount >= 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'orders_status_check' AND conrelid = 'public.orders'::regclass) THEN
        ALTER TABLE public.orders ADD CONSTRAINT orders_status_check
            CHECK (status IN ('pending', 'processing', 'shipped', 'delivered', 'cancelled'));
    END IF;
    -- order_items
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'order_items_quantity_check' AND conrelid = 'public.order_items'::regclass) THEN
        ALTER TABLE public.order_items ADD CONSTRAINT order_items_quantity_check CHECK (quantity > 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'order_items_unit_price_check' AND conrelid = 'public.order_items'::regclass) THEN
        ALTER TABLE public.order_items ADD CONSTRAINT order_items_unit_price_check CHECK (unit_price >= 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'order_items_total_price_check' AND conrelid = 'public.order_items'::regclass) THEN
        ALTER TABLE public.order_items ADD CONSTRAINT order_items_total_price_check CHECK (total_price >= 0);
    END IF;
    -- users_profile
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'users_profile_role_check' AND conrelid = 'public.users_profile'::regclass) THEN
        ALTER TABLE public.users_profile ADD CONSTRAINT users_profile_role_check
            CHECK (role IN ('customer', 'admin'));
    END IF;

    -- Nuevas restricciones (no duplican nada de schema.sql)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'products_name_not_blank' AND conrelid = 'public.products'::regclass) THEN
        ALTER TABLE public.products ADD CONSTRAINT products_name_not_blank
            CHECK (length(btrim(name)) > 0);
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'categories_name_not_blank' AND conrelid = 'public.categories'::regclass) THEN
        ALTER TABLE public.categories ADD CONSTRAINT categories_name_not_blank
            CHECK (length(btrim(name)) > 0);
    END IF;
END $$;

-- 5.2 Consistencia de importes y unicidad de item.
--     Se aplican solo si los datos existentes ya cumplen la regla; si no, se
--     avisa por NOTICE en lugar de fallar el script completo (la base podria
--     venir de una carga manual). Idempotente.
DO $$
BEGIN
    -- total_price = quantity * unit_price
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'order_items_line_total_check' AND conrelid = 'public.order_items'::regclass) THEN
        IF EXISTS (SELECT 1 FROM public.order_items
                   WHERE total_price IS DISTINCT FROM ROUND(quantity * unit_price, 2)) THEN
            RAISE NOTICE 'order_items_line_total_check NO aplicado: existen filas con total_price != quantity * unit_price. Corregir datos y re-ejecutar la Seccion 5.2.';
        ELSE
            ALTER TABLE public.order_items ADD CONSTRAINT order_items_line_total_check
                CHECK (total_price = ROUND(quantity * unit_price, 2));
        END IF;
    END IF;

    -- un solo renglon por producto dentro de una orden (lo garantiza tambien
    -- public.process_checkout al agrupar por product_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'order_items_order_product_key' AND conrelid = 'public.order_items'::regclass) THEN
        IF EXISTS (SELECT 1 FROM public.order_items
                   GROUP BY order_id, product_id HAVING count(*) > 1) THEN
            RAISE NOTICE 'order_items_order_product_key NO aplicado: hay (order_id, product_id) duplicados. Consolidar y re-ejecutar la Seccion 5.2.';
        ELSE
            ALTER TABLE public.order_items ADD CONSTRAINT order_items_order_product_key
                UNIQUE (order_id, product_id);
        END IF;
    END IF;
END $$;

-- 5.3 Columnas updated_at (idempotente).
--     orders ya la tiene. Se anaden a products, categories y users_profile para
--     poder auditar cambios; ADD COLUMN ... DEFAULT NOW() no reescribe la tabla
--     en Postgres 11+.
ALTER TABLE public.products      ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE public.categories    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();
ALTER TABLE public.users_profile ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- 5.4 Funcion generica de trigger para mantener updated_at.
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, auth
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.set_updated_at() IS
    'Trigger BEFORE UPDATE generico: asigna NOW() a NEW.updated_at.';

-- Se aplica en orders y en todas las tablas con updated_at.
DROP TRIGGER IF EXISTS trg_orders_set_updated_at        ON public.orders;
CREATE TRIGGER trg_orders_set_updated_at
    BEFORE UPDATE ON public.orders
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_products_set_updated_at      ON public.products;
CREATE TRIGGER trg_products_set_updated_at
    BEFORE UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_categories_set_updated_at    ON public.categories;
CREATE TRIGGER trg_categories_set_updated_at
    BEFORE UPDATE ON public.categories
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_users_profile_set_updated_at ON public.users_profile;
CREATE TRIGGER trg_users_profile_set_updated_at
    BEFORE UPDATE ON public.users_profile
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 5.5 Proteccion de campos sensibles de orders.
--     RLS no puede limitar COLUMNAS, y la politica de cancelacion permite al
--     cliente un UPDATE sobre su propia orden en estado pending. Sin esta
--     proteccion el cliente podria enviar {"status":"pending", "total_amount":0}
--     y reescribir el importe. El trigger lo impide:
--       * user_id y total_amount inmutables para el cliente;
--       * unica transicion permitida al cliente: pending -> cancelled.
--     Los roles internos (service_role/postgres, usados por el backend) y los
--     administradores NO se ven afectados: pueden cambiar estado libremente
--     (endpoint /admin/orders/{id}/status).
CREATE OR REPLACE FUNCTION public.protect_order_fields()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public, auth
AS $$
BEGIN
    -- Roles internos / administradores: sin restricciones.
    IF current_user NOT IN ('authenticated', 'anon')
       OR COALESCE(public.is_admin(), false) THEN
        RETURN NEW;
    END IF;

    -- Excepcion necesaria: la accion referencial ON DELETE SET NULL de
    -- orders.user_id (borrado de la cuenta en auth.users) ejecuta un UPDATE
    -- interno que tambien dispara este trigger. Se permite UNICAMENTE la
    -- direccion NOT NULL -> NULL y sin tocar importe ni estado: no sirve para
    -- robar ordenes (solo para que el propio cliente pierda el acceso a la
    -- suya), pero evita que el borrado de cuenta con ordenes historicas falle.
    IF OLD.user_id IS NOT NULL
       AND NEW.user_id IS NULL
       AND NEW.total_amount IS NOT DISTINCT FROM OLD.total_amount
       AND NEW.status IS NOT DISTINCT FROM OLD.status THEN
        RETURN NEW;
    END IF;

    IF NEW.user_id IS DISTINCT FROM OLD.user_id THEN
        RAISE EXCEPTION 'No se permite cambiar el propietario de la orden'
            USING ERRCODE = '42501';
    END IF;

    IF NEW.total_amount IS DISTINCT FROM OLD.total_amount THEN
        RAISE EXCEPTION 'No se permite modificar el total de la orden'
            USING ERRCODE = '42501';
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status
       AND NOT (OLD.status = 'pending' AND NEW.status = 'cancelled') THEN
        RAISE EXCEPTION 'Transicion de estado no permitida para el cliente (% -> %)',
            OLD.status, NEW.status
            USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_protect_fields ON public.orders;
CREATE TRIGGER trg_orders_protect_fields
    BEFORE UPDATE ON public.orders
    FOR EACH ROW EXECUTE FUNCTION public.protect_order_fields();

COMMENT ON FUNCTION public.protect_order_fields() IS
    'BEFORE UPDATE en orders: impide al cliente modificar user_id/total_amount o saltarse la transicion pending -> cancelled. Admins y service_role sin restriccion.';

-- 5.6 Higiene de permisos de funciones de trigger.
--     Son funciones de trigger (no deben poder invocarse por HTTP). Supabase
--     concede EXECUTE a anon/authenticated por DEFAULT PRIVILEGES en el esquema
--     public, por eso se revoca explicitamente.
DO $$
DECLARE
    v_sig  TEXT;
    v_sigs TEXT[] := ARRAY[
        'public.handle_new_user()',      -- definida en schema.sql
        'public.set_updated_at()',
        'public.protect_order_fields()'
    ];
BEGIN
    FOREACH v_sig IN ARRAY v_sigs LOOP
        IF to_regprocedure(v_sig) IS NOT NULL THEN
            EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated', v_sig);
        END IF;
    END LOOP;
END $$;


-- ============================================================================
-- SECCION 6. FUNCION ATOMICA DE COMPRA: public.process_checkout(uuid, jsonb)
-- ----------------------------------------------------------------------------
--  PROBLEMA ACTUAL (backend/routers/orders.py)
--    El checkout hace 5+ llamadas HTTP separadas a PostgREST:
--      SELECT products -> INSERT orders -> INSERT order_items -> N x (SELECT
--      stock; UPDATE stock) y, si algo falla, un UPDATE orders SET status
--      'cancelled' de compensacion.
--    Consecuencias:
--      * No es atomico: un fallo intermedio deja orden sin items o stock sin
--        descontar (se intenta compensar a mano, pero una caida de red entre
--        pasos deja la base inconsistente).
--      * Condicion de carrera (lost update): entre el SELECT de stock y el
--        UPDATE de stock otra compra puede vender las mismas unidades -> se
--        vende de mas, o `new_stock = max(stock - qty, 0)` oculta el problema
--        poniendo el stock en 0 sin alertar.
--      * Latencia: N idas y vueltas de red desde FastAPI.
--
--  SOLUCION
--    Una sola funcion PL/pgSQL SECURITY DEFINER que se ejecuta dentro de la
--    transaccion implicita de la sentencia RPC: o se hace todo, o no se hace
--    nada. Bloquea las filas de producto con SELECT ... FOR UPDATE en orden
--    ascendente de id (mismo orden siempre => sin deadlocks entre compras
--    concurrentes) y toma los precios del catalogo, no del cliente.
--
--  CONTRATO
--    p_user_id UUID   : propietario de la orden (validado contra auth.uid()).
--    p_items   JSONB  : [{"product_id": 1, "quantity": 2}, ...]
--    RETURNS JSONB    : {order_id, user_id, status, total, item_count, items[]}
--
--  ERRORES CONTROLADOS (PostgREST los propaga como error de Postgres)
--    22023 invalid_parameter_value : parametros/carrito invalidos o vacios.
--    42501 insufficient_privilege  : un cliente intenta comprar a nombre de otro.
--    23503 foreign_key_violation   : el usuario no existe en users_profile.
--    P0002 no_data_found           : producto inexistente.
--    23514 check_violation         : stock insuficiente (conflicto de negocio).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.process_checkout(
    p_user_id UUID,
    p_items   JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    v_caller     UUID;
    v_line       RECORD;
    v_product    RECORD;
    v_lines      JSONB := '[]'::JSONB;
    v_total      NUMERIC(12, 2) := 0;
    v_order_id   INTEGER;
    v_line_count INTEGER := 0;
BEGIN
    -- Identidad del invocador (NULL si se llama con service_role, por ejemplo
    -- desde el backend FastAPI con la service key).
    v_caller := (SELECT auth.uid());

    -- ------------------------------------------------------------------
    -- (0) Validacion de parametros de entrada
    -- ------------------------------------------------------------------
    IF p_user_id IS NULL THEN
        RAISE EXCEPTION 'process_checkout: p_user_id es obligatorio'
            USING ERRCODE = '22023';
    END IF;

    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' THEN
        RAISE EXCEPTION 'process_checkout: p_items debe ser un arreglo JSON con {"product_id", "quantity"}'
            USING ERRCODE = '22023';
    END IF;

    IF jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'process_checkout: el carrito esta vacio'
            USING ERRCODE = '22023';
    END IF;

    IF jsonb_array_length(p_items) > 100 THEN
        RAISE EXCEPTION 'process_checkout: el carrito excede el maximo de 100 lineas'
            USING ERRCODE = '22023';
    END IF;

    -- Forma de cada linea: objeto con product_id y quantity enteros positivos y
    -- acotados (evita desbordar el cast a INTEGER y valores sin sentido).
    IF EXISTS (
        SELECT 1
        FROM jsonb_array_elements(p_items) AS e
        WHERE jsonb_typeof(e) IS DISTINCT FROM 'object'
           OR (e -> 'product_id') IS NULL
           OR (e -> 'quantity') IS NULL
           OR jsonb_typeof(e -> 'product_id') IS DISTINCT FROM 'number'
           OR jsonb_typeof(e -> 'quantity')   IS DISTINCT FROM 'number'
           OR (e ->> 'product_id')::NUMERIC <= 0
           OR (e ->> 'product_id')::NUMERIC <> trunc((e ->> 'product_id')::NUMERIC)
           OR (e ->> 'product_id')::NUMERIC > 2147483647
           OR (e ->> 'quantity')::NUMERIC <= 0
           OR (e ->> 'quantity')::NUMERIC <> trunc((e ->> 'quantity')::NUMERIC)
           OR (e ->> 'quantity')::NUMERIC > 100000
    ) THEN
        RAISE EXCEPTION 'process_checkout: item invalido; se esperaba [{"product_id": <int > 0>, "quantity": <int > 0}, ...]'
            USING ERRCODE = '22023';
    END IF;

    -- ------------------------------------------------------------------
    -- (0.b) Autorizacion: la funcion es SECURITY DEFINER (salta RLS), por eso
    --       debe comprobar explicitamente que el invocador no compra como otro
    --       usuario. Si no hay JWT (auth.uid() IS NULL) se asume una llamada
    --       del backend con service_role, que ya valido el token y extrae el
    --       sub -> p_user_id. Un admin puede crear ordenes a nombre de otro.
    -- ------------------------------------------------------------------
    IF v_caller IS NOT NULL
       AND v_caller <> p_user_id
       AND NOT public.is_admin() THEN
        RAISE EXCEPTION 'process_checkout: no autorizado a crear ordenes para otro usuario'
            USING ERRCODE = '42501';
    END IF;

    -- ------------------------------------------------------------------
    -- (0.c) El usuario debe existir (mensaje claro en vez del FK generico).
    -- ------------------------------------------------------------------
    IF NOT EXISTS (SELECT 1 FROM public.users_profile AS up WHERE up.id = p_user_id) THEN
        RAISE EXCEPTION 'process_checkout: el usuario % no existe en users_profile', p_user_id
            USING ERRCODE = '23503';
    END IF;

    -- ------------------------------------------------------------------
    -- (a) Bloqueo de filas + validacion de existencia y stock
    --     - Se agrupa por product_id (si el carrito repite un producto, se suma
    --       la cantidad) y se recorre en orden ascendente de id: asi todas las
    --       transacciones concurrentes toman los locks en el MISMO orden y no
    --       se producen deadlocks.
    --     - FOR UPDATE bloquea escritores concurrentes hasta el COMMIT: dos
    --       compras simultaneas del ultimo articulo se serializan y la segunda
    --       recibe "stock insuficiente" (nunca se vende de mas).
    --     - El precio SIEMPRE se lee del catalogo: el cliente no puede
    --       manipularlo.
    -- ------------------------------------------------------------------
    FOR v_line IN
        SELECT (e ->> 'product_id')::INTEGER                       AS product_id,
               SUM((e ->> 'quantity')::INTEGER)::INTEGER           AS quantity
        FROM jsonb_array_elements(p_items) AS e
        GROUP BY 1
        ORDER BY 1
    LOOP
        SELECT p.id, p.name, p.price, p.stock
          INTO v_product
          FROM public.products AS p
         WHERE p.id = v_line.product_id
           FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'process_checkout: el producto % no existe', v_line.product_id
                USING ERRCODE = 'P0002';
        END IF;

        IF v_product.stock < v_line.quantity THEN
            RAISE EXCEPTION 'process_checkout: stock insuficiente para "%" (id %): disponible %, solicitado %',
                v_product.name, v_line.product_id, v_product.stock, v_line.quantity
                USING ERRCODE = '23514';
        END IF;

        v_total := v_total + ROUND(v_product.price * v_line.quantity, 2);
        v_lines := v_lines || jsonb_build_object(
            'product_id',  v_line.product_id,
            'name',        v_product.name,
            'quantity',    v_line.quantity,
            'unit_price',  v_product.price,
            'total_price', ROUND(v_product.price * v_line.quantity, 2)
        );
        v_line_count := v_line_count + 1;
    END LOOP;

    v_total := ROUND(v_total, 2);

    -- ------------------------------------------------------------------
    -- (c) Creacion de la orden (estado inicial 'pending').
    --     El trigger set_updated_at no interviene aqui (es BEFORE UPDATE), y el
    --     DEFAULT NOW() cubre created_at/updated_at.
    -- ------------------------------------------------------------------
    INSERT INTO public.orders (user_id, status, total_amount)
    VALUES (p_user_id, 'pending', v_total)
    RETURNING id INTO v_order_id;

    -- ------------------------------------------------------------------
    -- (d) Renglones de la orden (precio unitario congelado desde el catalogo).
    -- ------------------------------------------------------------------
    INSERT INTO public.order_items (order_id, product_id, quantity, unit_price, total_price)
    SELECT v_order_id,
           l.product_id,
           l.quantity,
           l.unit_price,
           l.total_price
      FROM jsonb_to_recordset(v_lines) AS l(
               product_id  INTEGER,
               quantity    INTEGER,
               unit_price  NUMERIC(10, 2),
               total_price NUMERIC(10, 2)
           );

    -- ------------------------------------------------------------------
    -- (e) Descuento de stock (las filas ya estan bloqueadas por FOR UPDATE).
    --     La restriccion products_stock_check (stock >= 0) actua como red de
    --     seguridad final: si por cualquier motivo el descuento dejara stock
    --     negativo, la transaccion completa falla en lugar de corromper datos.
    -- ------------------------------------------------------------------
    UPDATE public.products AS p
       SET stock = p.stock - l.quantity
      FROM jsonb_to_recordset(v_lines) AS l(
               product_id INTEGER,
               quantity   INTEGER
           )
     WHERE p.id = l.product_id;

    -- ------------------------------------------------------------------
    -- (f) Resultado para el backend.
    -- ------------------------------------------------------------------
    RETURN jsonb_build_object(
        'order_id',   v_order_id,
        'user_id',    p_user_id,
        'status',     'pending',
        'total',      v_total,
        'item_count', v_line_count,
        'items',      v_lines
    );
END;
$$;

COMMENT ON FUNCTION public.process_checkout(uuid, jsonb) IS
    'Checkout atomico: valida y bloquea stock (FOR UPDATE), crea la orden y sus items y descuenta inventario en una sola transaccion. Evita carreras de stock y ordenes a medias.';

-- Permisos: solo usuarios autenticados y el backend (service_role).
-- anon queda fuera: el checkout exige identidad.
REVOKE ALL ON FUNCTION public.process_checkout(UUID, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_checkout(UUID, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_checkout(UUID, JSONB) TO service_role;


-- ============================================================================
-- SECCION 7. VERIFICACION POST-APLICACION (solo lectura)
-- ============================================================================

-- 7.1 Auditoria automatica de tipos: avisa en WARNING si algun tipo esperado no
--     coincide (los 5 CHECKs de formato se hacen contra information_schema, sin
--     modificar nada).
DO $$
DECLARE
    v_rec  RECORD;
    v_bad  TEXT[] := ARRAY[]::TEXT[];
BEGIN
    FOR v_rec IN
        SELECT * FROM (VALUES
            ('categories',    'id',          'integer'),
            ('categories',    'description', 'text'),
            ('products',      'price',       'numeric'),
            ('products',      'stock',       'integer'),
            ('products',      'description', 'text'),
            ('products',      'created_at',  'timestamp with time zone'),
            ('users_profile', 'id',          'uuid'),
            ('users_profile', 'role',        'character varying'),
            ('orders',        'user_id',     'uuid'),
            ('orders',        'total_amount','numeric'),
            ('orders',        'created_at',  'timestamp with time zone'),
            ('order_items',   'quantity',    'integer'),
            ('order_items',   'unit_price',  'numeric')
        ) AS t(tbl, col, expected_type)
    LOOP
        IF NOT EXISTS (
            SELECT 1
            FROM information_schema.columns c
            WHERE c.table_schema = 'public'
              AND c.table_name   = v_rec.tbl
              AND c.column_name  = v_rec.col
              AND c.data_type    = v_rec.expected_type
        ) THEN
            v_bad := v_bad || format('%s.%s', v_rec.tbl, v_rec.col);
        END IF;
    END LOOP;

    IF array_length(v_bad, 1) > 0 THEN
        RAISE WARNING 'AUDITORIA DE TIPOS: columnas con tipo inesperado -> %', array_to_string(v_bad, ', ');
    ELSE
        RAISE NOTICE 'AUDITORIA DE TIPOS: OK (UUID/numeric(10,2)/integer/timestamptz/text verificados).';
    END IF;
END $$;

-- 7.2 Conteo de objetos creados/actualizados por este script.
DO $$
DECLARE
    v_idx  INTEGER;
    v_pol  INTEGER;
    v_fn   INTEGER;
    v_trg  INTEGER;
BEGIN
    SELECT count(*) INTO v_idx
    FROM pg_indexes
    WHERE schemaname = 'public' AND indexname LIKE 'idx_%';

    SELECT count(*) INTO v_pol
    FROM pg_policies
    WHERE schemaname = 'public';

    SELECT count(*) INTO v_fn
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public';

    SELECT count(*) INTO v_trg
    FROM pg_trigger t
    JOIN pg_class c     ON c.oid = t.tgrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public' AND NOT t.tgisinternal;

    RAISE NOTICE 'optimizations.sql aplicado -> indices idx_*: %, politicas: %, funciones public: %, triggers: %',
        v_idx, v_pol, v_fn, v_trg;
END $$;

-- 7.3 Realtime: publicar public.products para las actualizaciones de stock en vivo.
--     El frontend se suscribe a `postgres_changes` (UPDATE) sobre public.products en
--     el canal 'stock-updates' (ver supabase.service.ts). Si la tabla no esta en la
--     publicacion, Realtime no entrega ningun evento y el stock no se refresca solo.
DO $$
DECLARE
    v_publicada BOOLEAN;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        RAISE NOTICE 'Realtime: la publicacion supabase_realtime no existe en este proyecto; se omite la publicacion de products.';
        RETURN;
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM pg_publication_tables
        WHERE pubname    = 'supabase_realtime'
          AND schemaname = 'public'
          AND tablename  = 'products'
    ) INTO v_publicada;

    IF v_publicada THEN
        RAISE NOTICE 'Realtime: public.products ya estaba publicado en supabase_realtime.';
    ELSE
        ALTER PUBLICATION supabase_realtime ADD TABLE public.products;
        RAISE NOTICE 'Realtime: public.products agregado a la publicacion supabase_realtime (canal stock-updates).';
    END IF;
END $$;

COMMIT;

-- ============================================================================
--  VERIFICACIONES MANUALES DE RLS (ejecutar por separado, tras COMMIT)
--  Nota: en Supabase el SQL Editor se ejecuta como `postgres` (BYPASSRLS), por
--  lo que RLS no se aplica ahi. Para probar politicas hay que simular el rol y
--  el claim del JWT, por ejemplo:
--
--  -- a) Cliente leyendo SOLO sus ordenes (2222... es el cliente del seed):
--  BEGIN;
--    SET LOCAL ROLE authenticated;
--    SET LOCAL request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';
--    SELECT count(*) FROM public.orders;                    -- >= 1 (las suyas)
--    SELECT count(*) FROM public.orders
--     WHERE user_id <> '22222222-2222-2222-2222-222222222222';  -- 0
--    SELECT count(*) FROM public.users_profile WHERE id <> '2222...'; -- 0
--  ROLLBACK;
--
--  -- b) Cliente intentando leer ordenes ajenas del admin -> 0 filas:
--  BEGIN;
--    SET LOCAL ROLE authenticated;
--    SET LOCAL request.jwt.claims = '{"sub":"22222222-...","role":"authenticated"}';
--    SELECT * FROM public.orders WHERE user_id = '11111111-1111-1111-1111-111111111111';
--  ROLLBACK;
--
--  -- c) Admin (1111...) viendo todo:
--  BEGIN;
--    SET LOCAL ROLE authenticated;
--    SET LOCAL request.jwt.claims = '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';
--    SELECT count(*) FROM public.orders;            -- todas
--    SELECT count(*) FROM public.users_profile;     -- todos los perfiles
--  ROLLBACK;
--
--  -- d) Trigger on_auth_user_created (alta de usuario -> users_profile):
--  --    INSERT INTO auth.users (...) y comprobar que existe la fila de perfil.
--
--  -- e) Checkout atomico:
--  SELECT public.process_checkout(
--      '22222222-2222-2222-2222-222222222222'::uuid,
--      '[{"product_id":4,"quantity":1}]'::jsonb
--  );
--
--  -- f) Concurrencia (en dos sesiones): ejecutar process_checkout del ultimo
--  --    articulo en ambas; la segunda debe fallar con 23514 (stock insuficiente)
--  --    y el stock nunca debe quedar negativo.
-- ============================================================================
