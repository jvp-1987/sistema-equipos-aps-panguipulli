-- ═══════════════════════════════════════════════════════════════════
-- 08_diagnostico_sesion.sql
--
-- SOLO LECTURA. No modifica nada. Se puede correr las veces que sea.
--
-- Para qué sirve
-- ──────────────
-- Cuando una pantalla muestra "No se pudieron cargar los datos —
-- Unauthorized", o cuando alguien entra pero no ve nada, casi siempre es lo
-- mismo: el servidor no logró emparejar la cuenta que inició sesión (en
-- `auth.users`) con su ficha (en `usuario`).
--
-- El emparejamiento se hace SOLO por correo, en dos lugares distintos:
--
--   1. servidor/base44compat.js → auth.me()
--      .ilike('email', <correo del token>)
--
--   2. migracion/03_policies.sql → mi_rol(), mi_id(), mi_centro()
--      lower(email) = lower(auth.jwt() ->> 'email')
--
-- Ninguno de los dos recorta espacios. Un solo espacio invisible al final de
-- un correo en `usuario` deja a esa persona sin rol y sin filas: la app la
-- deja entrar, pero el servidor responde 401 y las policies no le muestran
-- nada. Las consultas de abajo buscan exactamente eso.
--
-- Cómo usarlo: Supabase → SQL Editor → pegar y ejecutar. Cada bloque imprime
-- su propio resultado.
-- ═══════════════════════════════════════════════════════════════════

-- ── 1) Fichas con espacios o mayúsculas en el correo ────────────────
-- Lo que se busca: CERO filas. Cada fila que salga es una persona que hoy
-- puede estar entrando sin rol.
select
  id,
  email,
  '[' || email || ']'                       as email_entre_corchetes,
  length(email)                             as largo,
  length(btrim(email))                      as largo_sin_espacios,
  (email <> btrim(email))                   as tiene_espacios,
  (email <> lower(email))                   as tiene_mayusculas,
  role,
  centro_principal
from usuario
where email <> btrim(email)
   or email <> lower(email)
order by email;

-- ── 2) Fichas sin cuenta de acceso, y cuentas sin ficha ─────────────
-- Ojo: el proyecto de Supabase se comparte con otra aplicación, así que
-- "cuenta sin ficha" incluye a los usuarios de ese otro sistema. Lo que
-- importa aquí es la primera columna.
select
  'ficha sin cuenta de acceso' as caso,
  u.email,
  u.role
from usuario u
where not exists (
  select 1 from auth.users a
  where lower(btrim(a.email)) = lower(btrim(u.email))
)

union all

select
  'cuenta sin ficha (puede ser del otro sistema)' as caso,
  a.email,
  null as role
from auth.users a
where not exists (
  select 1 from usuario u
  where lower(btrim(u.email)) = lower(btrim(a.email))
)
order by caso, email;

-- ── 3) Correos que se emparejan solo si se recortan los espacios ────
-- Estas son las que fallan hoy y funcionarían con btrim. Si esta consulta
-- devuelve filas, ahí está la causa del "Unauthorized".
select
  u.id,
  u.email      as email_en_usuario,
  a.email      as email_en_auth,
  u.role
from usuario u
join auth.users a
  on lower(btrim(a.email)) = lower(btrim(u.email))
where lower(a.email) <> lower(u.email)
order by u.email;

-- ── 4) El guion bajo en los correos ─────────────────────────────────
-- auth.me() empareja con ILIKE, donde "_" es un comodín que vale por
-- cualquier carácter. Con estos correos podría emparejar la ficha
-- equivocada si existieran dos parecidas. No es urgente si sale vacío.
select email, role
from usuario
where email like '%\_%' escape '\'
   or email like '%\%%' escape '\'
order by email;

-- ── 5) Quién ha entrado alguna vez ──────────────────────────────────
-- Para separar "no puede entrar" de "nunca ha intentado".
select
  u.email,
  u.role,
  u.centro_principal,
  a.last_sign_in_at,
  case
    when a.id is null              then 'sin cuenta de acceso'
    when a.last_sign_in_at is null then 'cuenta creada, nunca ha entrado'
    else 'ha entrado'
  end as situacion
from usuario u
left join auth.users a
  on lower(btrim(a.email)) = lower(btrim(u.email))
order by situacion, u.email;
