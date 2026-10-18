-- ==================================================
-- SEED: E-Commerce Tecnologico
-- Requiere que schema.sql ya se haya ejecutado.
-- ==================================================

-- Extensiones necesarias
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Categorias
INSERT INTO categories (name, description) VALUES
    ('Laptops', 'Computadoras portatiles para trabajo, estudio y gaming'),
    ('GPUs', 'Tarjetas graficas para rendimiento extremo'),
    ('Procesadores', 'CPUs para todo tipo de usos')
ON CONFLICT (name) DO NOTHING;

-- 10 productos tecnologicos reales con imagen y stock inicial
-- Idempotente: products.name NO es UNIQUE, asi que solo inserta si el catalogo esta vacio.
INSERT INTO products (name, description, price, stock, category_id, image_url)
SELECT v.*
FROM (VALUES
    ('MacBook Pro M2 14" 512GB', 'Notebook profesional Apple M2 Pro, pantalla Liquid Retina XDR de 14 pulgadas, 16GB RAM unificada, SSD de 512GB', 1999.00, 12, 1, 'https://images.unsplash.com/photo-1517336714731-489689fd1ca8?w=800'),
    ('ASUS ROG Strix G16 RTX 4070', 'Laptop gaming con Intel Core i9-13980HX, 16GB RTX 4070, 32GB DDR5, pantalla 165Hz', 1899.00, 8, 1, 'https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?w=800'),
    ('Lenovo ThinkPad X1 Carbon Gen 11', 'Ultrabook empresarial, Intel Core i7 de 13va gen, 16GB RAM, 512GB SSD, peso 1.12kg', 1449.99, 15, 1, 'https://images.unsplash.com/photo-1611183077793-1f549e26d7cd?w=800'),
    ('ASUS Vivobook 15 i5-1235U', 'Laptop cotidiana con Intel Core i5-1235U, 8GB RAM DDR4, SSD de 256GB, pantalla 15.6 pulgadas', 649.99, 25, 1, 'https://images.unsplash.com/photo-1517134191118-9d595e4c8eeb?w=800'),
    ('NVIDIA GeForce RTX 4090', 'GPU tope de gama, 24GB GDDR6X, arquitectura Ada Lovelace, ideal para gaming 8K y IA', 1899.00, 5, 2, 'https://images.unsplash.com/photo-1604300410354-ea6bd8b95c99?w=800'),
    ('NVIDIA GeForce RTX 4080 SUPER', 'Tarjeta grafica para gaming 4K, 16GB GDDR6X, DLSS 3.5, entre 15% y 20% mas rapida que la 4070 Ti', 1199.00, 10, 2, 'https://images.unsplash.com/photo-1592906269976-74d731c63cb5?w=800'),
    ('AMD Radeon RX 7900 XT', 'GPU AMD RDNA3, 20GB GDDR6, borde sobresaliente para 1440p y 4K, AV1 decode', 899.00, 14, 2, 'https://images.unsplash.com/photo-1591238372348-31d69a41bd88?w=800'),
    ('Intel Core i9-14900K', 'Procesador desktop 24 nucleos (8P+16E), 32 hilos, hasta 6.0GHz Turbo, socket LGA1700', 589.99, 18, 3, 'https://images.unsplash.com/photo-1504328345606-18bbc8c9d7d1?w=800'),
    ('AMD Ryzen 9 7950X3D', 'Procesador 16 nucleos, 32 hilos, 3D V-Cache de 128MB, hasta 5.7GHz, socket AM5', 699.00, 20, 3, 'https://images.unsplash.com/photo-1591799264318-7e6ef8ddb7ea?w=800'),
    ('AMD Ryzen 7 7800X3D', 'CPU de alto rendimiento para gaming, 8 nucleos, 96MB 3D V-Cache, superioridad clara en FPS', 449.00, 30, 3, 'https://images.unsplash.com/photo-1555618557-e1f74ca68779?w=800')
) AS v(name, description, price, stock, category_id, image_url)
WHERE NOT EXISTS (SELECT 1 FROM public.products);

-- ==================================================
-- USUARIOS DE PRUEBA (1 admin y 5 clientes)
-- El trigger on_auth_user_created creara automaticamente
-- sus filas en users_profile con el rol definido en raw_app_meta_data
-- y el nombre completo desde raw_user_meta_data.
-- Contrasena comun: Password123!
-- ==================================================

INSERT INTO auth.users (
    instance_id, id, aud, role, email,
    encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, recovery_token,
    email_change, email_change_token_new, phone, phone_confirmed_at, phone_change, phone_change_token, reauthentication_token
) VALUES (
    '00000000-0000-0000-0000-000000000000',
    '11111111-1111-1111-1111-111111111111',
    'authenticated', 'authenticated', 'admin@techshop.com',
    crypt('Password123!', gen_salt('bf', 10)),
    now(),
    '{"provider":"email","providers":["email"],"role":"admin"}',
    '{"full_name":"Administrador TechStore"}',
    now(), now(), '', '', '', '', NULL, null, '', '', ''
), (
    '00000000-0000-0000-0000-000000000000',
    '22222222-2222-2222-2222-222222222222',
    'authenticated', 'authenticated', 'cliente@techshop.com',
    crypt('Password123!', gen_salt('bf', 10)),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Cliente de Prueba"}',
    now(), now(), '', '', '', '', NULL, null, '', '', ''
), (
    '00000000-0000-0000-0000-000000000000',
    '33333333-3333-3333-3333-333333333333',
    'authenticated', 'authenticated', 'maria.gonzalez@techshop.com',
    crypt('Password123!', gen_salt('bf', 10)),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Maria Gonzalez"}',
    now(), now(), '', '', '', '', NULL, null, '', '', ''
), (
    '00000000-0000-0000-0000-000000000000',
    '44444444-4444-4444-4444-444444444444',
    'authenticated', 'authenticated', 'carlos.perez@techshop.com',
    crypt('Password123!', gen_salt('bf', 10)),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Carlos Perez"}',
    now(), now(), '', '', '', '', NULL, null, '', '', ''
), (
    '00000000-0000-0000-0000-000000000000',
    '55555555-5555-5555-5555-555555555555',
    'authenticated', 'authenticated', 'lucia.fernandez@techshop.com',
    crypt('Password123!', gen_salt('bf', 10)),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Lucia Fernandez"}',
    now(), now(), '', '', '', '', NULL, null, '', '', ''
), (
    '00000000-0000-0000-0000-000000000000',
    '66666666-6666-6666-6666-666666666666',
    'authenticated', 'authenticated', 'diego.martinez@techshop.com',
    crypt('Password123!', gen_salt('bf', 10)),
    now(),
    '{"provider":"email","providers":["email"]}',
    '{"full_name":"Diego Martinez"}',
    now(), now(), '', '', '', '', NULL, null, '', '', ''
) ON CONFLICT DO NOTHING;

INSERT INTO auth.identities (id, user_id, provider_id, identity_data, last_sign_in_at, created_at, updated_at, provider) VALUES
    (gen_random_uuid(), '11111111-1111-1111-1111-111111111111', 'email', '{"sub":"11111111-1111-1111-1111-111111111111","email":"admin@techshop.com"}', now(), now(), now(), 'email'),
    (gen_random_uuid(), '22222222-2222-2222-2222-222222222222', 'email', '{"sub":"22222222-2222-2222-2222-222222222222","email":"cliente@techshop.com"}', now(), now(), now(), 'email'),
    (gen_random_uuid(), '33333333-3333-3333-3333-333333333333', 'email', '{"sub":"33333333-3333-3333-3333-333333333333","email":"maria.gonzalez@techshop.com"}', now(), now(), now(), 'email'),
    (gen_random_uuid(), '44444444-4444-4444-4444-444444444444', 'email', '{"sub":"44444444-4444-4444-4444-444444444444","email":"carlos.perez@techshop.com"}', now(), now(), now(), 'email'),
    (gen_random_uuid(), '55555555-5555-5555-5555-555555555555', 'email', '{"sub":"55555555-5555-5555-5555-555555555555","email":"lucia.fernandez@techshop.com"}', now(), now(), now(), 'email'),
    (gen_random_uuid(), '66666666-6666-6666-6666-666666666666', 'email', '{"sub":"66666666-6666-6666-6666-666666666666","email":"diego.martinez@techshop.com"}', now(), now(), now(), 'email')
ON CONFLICT DO NOTHING;

-- Refuerzo: asegura fila de perfil y rol admin si el trigger no lo asigno
INSERT INTO users_profile (id, role, full_name)
SELECT id, 'admin', 'Administrador TechStore'
FROM auth.users
WHERE email = 'admin@techshop.com'
ON CONFLICT (id) DO UPDATE
    SET role      = 'admin',
        full_name = COALESCE(users_profile.full_name, EXCLUDED.full_name);

INSERT INTO users_profile (id, role, full_name)
SELECT id, 'customer', 'Cliente de Prueba'
FROM auth.users
WHERE email = 'cliente@techshop.com'
ON CONFLICT (id) DO UPDATE
    SET full_name = COALESCE(users_profile.full_name, EXCLUDED.full_name);

-- Verificacion: los seis usuarios de prueba deben existir realmente en auth.users.
-- Un `ON CONFLICT DO NOTHING` silencioso puede descartarlos (p. ej. `phone` vacío
-- colisiona con el índice único auth.users_phone_key).
DO $$
DECLARE
    v_faltantes TEXT[] := ARRAY[]::TEXT[];
    v_email TEXT;
BEGIN
    FOR v_email IN
        SELECT unnest(ARRAY[
            'admin@techshop.com',
            'cliente@techshop.com',
            'maria.gonzalez@techshop.com',
            'carlos.perez@techshop.com',
            'lucia.fernandez@techshop.com',
            'diego.martinez@techshop.com'
        ])
    LOOP
        IF NOT EXISTS (SELECT 1 FROM auth.users WHERE email = v_email) THEN
            v_faltantes := v_faltantes || v_email;
        END IF;
    END LOOP;

    IF array_length(v_faltantes, 1) > 0 THEN
        RAISE WARNING 'seed: usuarios de prueba NO creados -> %. Revisar colisiones en auth.users.', array_to_string(v_faltantes, ', ');
    ELSE
        RAISE NOTICE 'seed: 6 usuarios de prueba listos (contrasena comun Password123!).';
    END IF;
END $$;

-- Actualizacion defensa en profundidad del rol admin del rol admin en app_metadata
UPDATE auth.users
SET raw_app_meta_data = raw_app_meta_data || '{"role":"admin"}'::jsonb
WHERE email = 'admin@techshop.com';

-- Datos de ejemplo: una orden completada del cliente de prueba (transaccional y consistente)
DO $$
DECLARE
    v_order_id INTEGER;
    v_user_id UUID;
    v_stock_ok BOOLEAN;
BEGIN
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE email = 'cliente@techshop.com';

    -- Sin usuario cliente se omite la orden de ejemplo. Sin este guard se crearia
    -- una orden huerfana con user_id NULL, porque `user_id = NULL` nunca es TRUE.
    IF v_user_id IS NULL THEN
        RAISE NOTICE 'seed: no se encontro cliente@techshop.com; se omite la orden de ejemplo.';
        RETURN;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM orders WHERE user_id = v_user_id) THEN
        SELECT stock >= 1 INTO v_stock_ok FROM products WHERE name LIKE 'ASUS Vivobook 15%';
        IF v_stock_ok THEN
            INSERT INTO orders (user_id, status, total_amount)
            VALUES (v_user_id, 'delivered', 649.99)
            RETURNING id INTO v_order_id;

            INSERT INTO order_items (order_id, product_id, quantity, unit_price, total_price)
            SELECT v_order_id, id, 1, price, price
            FROM products
            WHERE name LIKE 'ASUS Vivobook 15%';

            UPDATE products
            SET stock = stock - 1
            WHERE name LIKE 'ASUS Vivobook 15%';
        END IF;
    END IF;
END $$;

-- ==================================================
-- IMAGENES DEL CATALOGO
-- Hotlinks verificados de Openverse (api.openverse.org/v1/images/{id}/thumb/):
-- cada imagen fue descargada, inspeccionada visualmente y reapareada por hash
-- con su registro de Openverse. Idempotente: aplica a bases nuevas y existentes.
-- ==================================================
UPDATE public.products SET image_url = 'https://api.openverse.org/v1/images/74ec0824-c17b-4866-9921-1daa3fd1c4a5/thumb/' WHERE name = 'ASUS ROG Strix G16 RTX 4070';
UPDATE public.products SET image_url = 'https://api.openverse.org/v1/images/c5b7726d-f830-4281-a800-c949e4c6601d/thumb/' WHERE name = 'Lenovo ThinkPad X1 Carbon Gen 11';
UPDATE public.products SET image_url = 'https://api.openverse.org/v1/images/32f7b0e2-bb52-4a51-86de-78dfedf9ae66/thumb/' WHERE name = 'ASUS Vivobook 15 i5-1235U';
UPDATE public.products SET image_url = 'https://api.openverse.org/v1/images/92900e59-aefa-4a86-b663-af42d279b6fa/thumb/' WHERE name = 'NVIDIA GeForce RTX 4090';
UPDATE public.products SET image_url = 'https://api.openverse.org/v1/images/04be88d3-fdac-4373-92b8-52870b26174d/thumb/' WHERE name = 'NVIDIA GeForce RTX 4080 SUPER';
UPDATE public.products SET image_url = 'https://api.openverse.org/v1/images/e4cd2d67-088d-4b2e-8954-1f7d6946d1a8/thumb/' WHERE name = 'AMD Radeon RX 7900 XT';
UPDATE public.products SET image_url = 'https://api.openverse.org/v1/images/4324f7fd-2092-4df8-bd25-9aa599aff0ad/thumb/' WHERE name = 'Intel Core i9-14900K';
UPDATE public.products SET image_url = 'https://api.openverse.org/v1/images/129a033d-355f-4a98-9755-1dc546cbe41d/thumb/' WHERE name = 'AMD Ryzen 7 7800X3D';

-- ==================================================
-- CATALOGO AMPLIADO: categorias y productos nuevos
-- Idempotente: categorias por name UNIQUE; productos con WHERE NOT EXISTS
-- porque products.name NO es UNIQUE.
-- ==================================================
INSERT INTO categories (name, description) VALUES
    ('Monitores', 'Pantallas para trabajo y gaming competitivo'),
    ('Perifericos', 'Teclados, mouses, audifonos y accesorios de jugador'),
    ('Componentes', 'Almacenamiento y memoria para armar o mejorar el equipo')
ON CONFLICT (name) DO NOTHING;

INSERT INTO products (name, description, price, stock, category_id, image_url)
SELECT v.*
FROM (VALUES
    ('Monitor gamer 27 pulgadas IPS 165Hz', 'Pantalla IPS sin marco con 165Hz y respuesta de 1ms, ideal para esport y diseno', 279.99, 12, (SELECT id FROM categories WHERE name = 'Monitores'), 'https://api.openverse.org/v1/images/5f1fef14-c6e7-4f54-bd8b-0dc83e64715e/thumb/'),
    ('Teclado mecanico Noppoo Choc RGB', 'Teclado mecanico compacto con retroiluminacion por tecla y switches azules', 89.99, 30, (SELECT id FROM categories WHERE name = 'Perifericos'), 'https://api.openverse.org/v1/images/e1246fe4-27aa-435f-a0b5-aa08481c3b38/thumb/'),
    ('Mouse gamer Logitech MX518', 'Mouse ergonomico con sensor de alta precision, 8 botones programables y cable resistente', 69.99, 35, (SELECT id FROM categories WHERE name = 'Perifericos'), 'https://api.openverse.org/v1/images/5b72408a-ee33-4f96-ac81-44857c612eae/thumb/'),
    ('Diadema gamer Razer Megalodon 7.1', 'Audifonos con sonido surround 7.1 virtual, mando de volumen USB y LED azul', 129.99, 15, (SELECT id FROM categories WHERE name = 'Perifericos'), 'https://api.openverse.org/v1/images/8dae7c1c-c960-42d0-81d4-806784fde538/thumb/'),
    ('SSD Plextor M6 Pro 512GB', 'Unidad SSD SATA 2.5 pulgadas de alto rendimiento, controlador Marvell y memoria MLC', 119.99, 25, (SELECT id FROM categories WHERE name = 'Componentes'), 'https://api.openverse.org/v1/images/42a5d2f8-d30a-477a-b394-4eaad6e70dd1/thumb/'),
    ('HyperX Fury DDR4 32GB 3200MHz', 'Kit de memoria DDR4 de 32GB (2x16GB) a 3200MHz con disipador de aluminio', 109.99, 22, (SELECT id FROM categories WHERE name = 'Componentes'), 'https://api.openverse.org/v1/images/e31122d4-e7ec-4291-acac-8162b1033d4c/thumb/')
) AS v(name, description, price, stock, category_id, image_url)
WHERE NOT EXISTS (SELECT 1 FROM public.products WHERE public.products.name = v.name);

-- Verificacion: ninguna fila del catalogo puede quedar con image_url nula
DO $$
DECLARE
    v_sin_imagen INT;
BEGIN
    SELECT count(*) INTO v_sin_imagen FROM public.products WHERE image_url IS NULL;
    IF v_sin_imagen > 0 THEN
        RAISE WARNING 'seed: hay % productos sin imagen', v_sin_imagen;
    END IF;
END $$;
