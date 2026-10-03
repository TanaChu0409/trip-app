begin;

create extension if not exists pgtap with schema extensions;
select no_plan();

-- Validate the complete CRUD privilege matrix for every Data API relation.
with relations(object_name, object_kind) as (
  values
    ('public.trips', 'trips'),
    ('public.days', 'app'),
    ('public.stops', 'app'),
    ('public.parking_spots', 'app'),
    ('public.shared_access', 'app'),
    ('public.stop_photos', 'app'),
    ('public.profiles', 'profiles'),
    ('public.profiles_public', 'profiles_public'),
    ('public.join_code_attempts', 'attempts'),
    ('public.invite_member_attempts', 'attempts')
), roles(role_name) as (
  values ('anon'), ('authenticated'), ('service_role')
), privileges(privilege_name) as (
  values
    ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'),
    ('TRUNCATE'), ('REFERENCES'), ('TRIGGER')
), expected as (
  select
    object_name,
    role_name,
    privilege_name,
    case
      when role_name = 'service_role'
        and object_kind <> 'profiles_public'
        and privilege_name in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
        then true
      when role_name = 'service_role'
        and object_kind = 'profiles_public'
        and privilege_name = 'SELECT'
        then true
      when role_name = 'authenticated'
        and object_kind = 'app'
        and privilege_name in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
        then true
      when role_name = 'authenticated'
        and object_kind = 'trips'
        and privilege_name in ('SELECT', 'INSERT', 'DELETE')
        then true
      when role_name = 'authenticated'
        and object_kind = 'profiles_public'
        and privilege_name = 'SELECT'
        then true
      else false
    end as allowed
  from relations
  cross join roles
  cross join privileges
)
select extensions.ok(
  has_table_privilege(role_name, object_name, privilege_name) = allowed,
  format('%s %s on %s is %s', role_name, privilege_name, object_name,
    case when allowed then 'granted' else 'revoked' end)
)
from expected;

-- Profiles intentionally use column privileges instead of whole-table grants.
with columns(column_name) as (
  values
    ('id'), ('display_name'), ('email'), ('avatar_url'),
    ('created_at'), ('updated_at')
), roles(role_name) as (
  values ('anon'), ('authenticated'), ('service_role')
), privileges(privilege_name) as (
  values ('SELECT'), ('INSERT'), ('UPDATE'), ('REFERENCES')
), expected as (
  select
    column_name,
    role_name,
    privilege_name,
    case
      when role_name = 'service_role'
        and privilege_name in ('SELECT', 'INSERT', 'UPDATE')
        then true
      when role_name = 'authenticated'
        and privilege_name = 'SELECT'
        and column_name in ('id', 'display_name', 'avatar_url', 'created_at', 'updated_at')
        then true
      when role_name = 'authenticated'
        and privilege_name = 'UPDATE'
        and column_name in ('display_name', 'email', 'avatar_url', 'updated_at')
        then true
      else false
    end as allowed
  from columns
  cross join roles
  cross join privileges
)
select extensions.ok(
  has_column_privilege(
    role_name,
    'public.profiles',
    column_name,
    privilege_name
  ) = allowed,
  format('%s %s on profiles.%s is %s', role_name, privilege_name, column_name,
    case when allowed then 'granted' else 'revoked' end)
)
from expected;

-- Validate the EXECUTE allowlist for all application functions in public.
with functions(signature, access_class) as (
  values
    ('public.join_trip_by_code(text)', 'app_rpc'),
    ('public.invite_member_by_email(uuid,text,text)', 'app_rpc'),
    ('public.update_trip_color(uuid,text)', 'app_rpc'),
    ('public.remove_trip_custom_stop_color(uuid,text)', 'app_rpc'),
    ('public.create_stop_with_palette(uuid,jsonb)', 'app_rpc'),
    ('public.update_stop_with_palette(uuid,jsonb)', 'app_rpc'),
    ('public.set_owned_trip_archived(uuid,boolean)', 'app_rpc'),
    ('public.is_trip_owner(uuid)', 'policy_helper'),
    ('public.is_trip_editor(uuid)', 'policy_helper'),
    ('public.is_active_trip_owner(uuid)', 'policy_helper'),
    ('public.is_stop_trip_owner(uuid)', 'policy_helper'),
    ('public.can_edit_stop(uuid)', 'policy_helper'),
    ('public.can_read_stop(uuid)', 'policy_helper'),
    ('public.storage_stop_id(text)', 'policy_helper'),
    ('public.can_read_trip_peer_profile(uuid,uuid)', 'policy_helper'),
    ('public.purge_join_code_attempts()', 'purge'),
    ('public.purge_invite_member_attempts()', 'purge'),
    ('public.handle_new_user()', 'internal'),
    ('public.enforce_stop_photo_limit()', 'internal'),
    ('public.can_edit_trip(uuid)', 'internal'),
    ('public.add_custom_stop_color(uuid,text)', 'internal'),
    ('public.sync_trip_custom_stop_color()', 'internal'),
    ('public.prevent_archived_trip_membership_changes()', 'internal')
), roles(role_name) as (
  values ('anon'), ('authenticated'), ('service_role')
), expected as (
  select
    signature,
    role_name,
    (
      (access_class = 'app_rpc' and role_name in ('authenticated', 'service_role'))
      or (access_class = 'policy_helper' and role_name = 'authenticated')
      or (
        signature = 'public.can_read_trip_peer_profile(uuid,uuid)'
        and role_name = 'service_role'
      )
      or (access_class = 'purge' and role_name = 'service_role')
    ) as allowed
  from functions
  cross join roles
)
select extensions.ok(
  has_function_privilege(role_name, signature, 'EXECUTE') = allowed,
  format('%s EXECUTE on %s is %s', role_name, signature,
    case when allowed then 'granted' else 'revoked' end)
)
from expected;

select extensions.ok(
  not exists (
    select 1
    from pg_default_acl d
    join pg_roles owner_role on owner_role.oid = d.defaclrole
    left join pg_namespace n on n.oid = d.defaclnamespace
    cross join lateral aclexplode(d.defaclacl) acl
    left join pg_roles grantee_role on grantee_role.oid = acl.grantee
    where owner_role.rolname = 'postgres'
      and (
        (
          d.defaclnamespace = 0
          and d.defaclobjtype = 'f'
          and acl.grantee = 0
        )
        or (
          n.nspname = 'public'
          and (
            acl.grantee = 0
            or grantee_role.rolname in ('anon', 'authenticated', 'service_role')
          )
        )
      )
  ),
  'postgres global function and public-schema defaults do not expose future objects'
);

select extensions.is(
  (
    select setting
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    cross join lateral unnest(coalesce(p.proconfig, array[]::text[])) setting
    where n.nspname = 'public'
      and p.proname = 'storage_stop_id'
      and setting like 'search_path=%'
  ),
  'search_path=pg_catalog',
  'storage_stop_id uses a fixed trusted search_path'
);

select * from finish();
rollback;
