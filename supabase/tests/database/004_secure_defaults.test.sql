begin;
create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

-- Check actual objects, including tables added after the ACL allowlist.
select extensions.ok(c.relrowsecurity, format('%s has RLS enabled', c.oid::regclass))
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind in ('r', 'p')
  and not exists (
    select 1 from pg_depend d
    where d.classid = 'pg_class'::regclass and d.objid = c.oid and d.deptype = 'e'
  );

select extensions.ok(
  coalesce(c.reloptions, array[]::text[]) @> array['security_invoker=true'],
  format('%s evaluates permissions as the caller', c.oid::regclass)
)
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'v'
  and has_table_privilege('authenticated', c.oid, 'SELECT');

-- Do not rely solely on pg_default_acl rows: PostgreSQL also has implicit
-- defaults (notably PUBLIC EXECUTE). Create real future objects as the same
-- owner used by migrations, then check effective privileges including PUBLIC.
set local role postgres;
create table public.acl_future_table_probe (id bigint);
create sequence public.acl_future_sequence_probe;
create function public.acl_future_function_probe() returns integer
  language sql as $$ select 1 $$;
reset role;

with roles(role_name) as (values ('anon'), ('authenticated'), ('service_role')),
privileges(privilege_name) as (
  values ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'),
    ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')
)
select extensions.ok(
  not has_table_privilege(role_name, 'public.acl_future_table_probe', privilege_name),
  format('future tables deny %s to %s until explicitly granted', privilege_name, role_name)
)
from roles cross join privileges;

with roles(role_name) as (values ('anon'), ('authenticated'), ('service_role')),
privileges(privilege_name) as (values ('USAGE'), ('SELECT'), ('UPDATE'))
select extensions.ok(
  not has_sequence_privilege(role_name, 'public.acl_future_sequence_probe', privilege_name),
  format('future sequences deny %s to %s until explicitly granted', privilege_name, role_name)
)
from roles cross join privileges;

select extensions.ok(
  not has_function_privilege(role_name, 'public.acl_future_function_probe()', 'EXECUTE'),
  format('future functions deny EXECUTE to %s until explicitly granted', role_name)
)
from (values ('anon'), ('authenticated'), ('service_role')) roles(role_name);

set local role anon;
select extensions.throws_ok($$select * from public.acl_future_table_probe$$, '42501');
select extensions.throws_ok($$select public.acl_future_function_probe()$$, '42501');
reset role;

select * from extensions.finish();
rollback;
