-- Tokens never enter readable trip rows or snapshots. All mutations lock the
-- trip first, serializing acceptance with reset, revocation and archiving.
create table public.trip_invite_links (
  trip_id uuid primary key references public.trips(id) on delete cascade,
  token_hash text not null unique,
  permission text not null check (permission in ('editor', 'viewer')),
  created_at timestamptz not null default now(),
  revoked_at timestamptz
);
alter table public.trip_invite_links enable row level security;
revoke all on public.trip_invite_links from public, anon, authenticated, service_role;
grant select, insert, update, delete on public.trip_invite_links to service_role;

create function public.get_trip_invite_link(p_trip_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare link public.trip_invite_links%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode = '28000'; end if;
  if not public.is_trip_owner(p_trip_id) then return jsonb_build_object('status', 'not_owner'); end if;
  select * into link from public.trip_invite_links where trip_id = p_trip_id;
  return jsonb_build_object('status', 'success', 'active', found and link.revoked_at is null,
    'permission', link.permission);
end;
$$;

create function public.create_trip_invite_link(p_trip_id uuid, p_permission text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare t public.trips%rowtype; token text;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode = '28000'; end if;
  select * into t from public.trips where id = p_trip_id for update;
  if not found or t.owner_id <> auth.uid() then return jsonb_build_object('status', 'not_owner'); end if;
  if t.is_archived then return jsonb_build_object('status', 'trip_archived'); end if;
  if p_permission is null or p_permission not in ('editor', 'viewer') then
    return jsonb_build_object('status', 'invalid_permission');
  end if;
  token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.trip_invite_links (trip_id, token_hash, permission)
  values (p_trip_id, encode(extensions.digest(token, 'sha256'), 'hex'), p_permission)
  on conflict (trip_id) do update set token_hash = excluded.token_hash,
    permission = excluded.permission, created_at = now(), revoked_at = null;
  return jsonb_build_object('status', 'success', 'token', token, 'permission', p_permission, 'active', true);
end;
$$;

create function public.revoke_trip_invite_link(p_trip_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare t public.trips%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode = '28000'; end if;
  select * into t from public.trips where id = p_trip_id for update;
  if not found or t.owner_id <> auth.uid() then return jsonb_build_object('status', 'not_owner'); end if;
  if t.is_archived then return jsonb_build_object('status', 'trip_archived'); end if;
  update public.trip_invite_links set revoked_at = now() where trip_id = p_trip_id;
  return jsonb_build_object('status', 'success');
end;
$$;

-- Shared implementation is not callable by Data API roles.
create function public.resolve_trip_invite_link(p_token text, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare link public.trip_invite_links%rowtype; t public.trips%rowtype; target uuid; existing_permission text;
begin
  if auth.uid() is null then raise exception 'Authentication required.' using errcode = '28000'; end if;
  if p_token is null or p_token !~ '^[0-9a-f]{64}$' then return jsonb_build_object('status', 'invalid_link'); end if;
  select trip_id into target from public.trip_invite_links
    where token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') and revoked_at is null;
  if not found then return jsonb_build_object('status', 'invalid_link'); end if;
  select * into t from public.trips where id = target for update;
  -- Re-read after obtaining the trip lock: a concurrent reset may have won.
  select * into link from public.trip_invite_links where trip_id = target
    and token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex') and revoked_at is null;
  if not found then return jsonb_build_object('status', 'invalid_link'); end if;
  if t.is_archived then return jsonb_build_object('status', 'trip_archived'); end if;
  if t.owner_id = auth.uid() then
    return jsonb_build_object('status', 'owner', 'trip_id', t.id, 'title', t.title, 'permission', link.permission);
  end if;
  select permission into existing_permission from public.shared_access where trip_id = target and user_id = auth.uid();
  if found then
    return jsonb_build_object('status', 'already_member', 'trip_id', t.id, 'title', t.title, 'permission', existing_permission);
  end if;
  if p_accept then
    insert into public.shared_access (trip_id, user_id, permission) values (target, auth.uid(), link.permission)
      on conflict (trip_id, user_id) do nothing;
    if not found then
      select permission into existing_permission from public.shared_access where trip_id = target and user_id = auth.uid();
      return jsonb_build_object('status', 'already_member', 'trip_id', t.id, 'title', t.title, 'permission', existing_permission);
    end if;
  end if;
  return jsonb_build_object('status', 'success', 'trip_id', t.id, 'title', t.title, 'permission', link.permission);
end;
$$;
create function public.preview_trip_invite_link(p_token text)
returns jsonb language sql security definer set search_path = '' as $$
  select public.resolve_trip_invite_link(p_token, false);
$$;
create function public.accept_trip_invite_link(p_token text)
returns jsonb language sql security definer set search_path = '' as $$
  select public.resolve_trip_invite_link(p_token, true);
$$;

create function public.revoke_invite_on_archive()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.is_archived and not old.is_archived then
    update public.trip_invite_links set revoked_at = now() where trip_id = new.id;
  end if;
  return new;
end;
$$;
create trigger revoke_invite_on_archive after update of is_archived on public.trips
for each row execute function public.revoke_invite_on_archive();

revoke all on function public.resolve_trip_invite_link(text, boolean), public.revoke_invite_on_archive()
  from public, anon, authenticated, service_role;
revoke all on function public.get_trip_invite_link(uuid), public.create_trip_invite_link(uuid,text),
  public.revoke_trip_invite_link(uuid), public.preview_trip_invite_link(text), public.accept_trip_invite_link(text)
  from public, anon, authenticated, service_role;
grant execute on function public.get_trip_invite_link(uuid), public.create_trip_invite_link(uuid,text),
  public.revoke_trip_invite_link(uuid), public.preview_trip_invite_link(text), public.accept_trip_invite_link(text)
  to authenticated, service_role;
revoke all on function public.join_trip_by_code(text) from public, anon, authenticated, service_role;
-- Membership inserts must go through validated invite RPCs.
drop policy if exists shared_access_insert_self on public.shared_access;
