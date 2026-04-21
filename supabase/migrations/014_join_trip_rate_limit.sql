-- SECURITY FIX: Rate-limit share-code join attempts to prevent brute-force
-- enumeration of trip share codes.
--
-- Without rate limiting, an attacker could send thousands of requests per
-- second to join_trip_by_code and enumerate all valid 6-character share codes.
-- This migration adds a tracking table and enforces a maximum of 20 attempts
-- per authenticated user per hour.

create table if not exists public.join_code_attempts (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        not null references auth.users(id) on delete cascade,
  attempted_at timestamptz not null default now()
);

create index if not exists idx_join_code_attempts_user_time
  on public.join_code_attempts(user_id, attempted_at);

alter table public.join_code_attempts enable row level security;
-- No direct client access needed; only the SECURITY DEFINER function writes to it.

-- Automatically purge attempts older than 24 hours to keep the table small.
-- (Run as a scheduled job in Supabase, or rely on natural pruning via the index.)

-- Recreate join_trip_by_code with rate limiting.
create or replace function public.join_trip_by_code(p_share_code text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_code  text    := trim(upper(coalesce(p_share_code, '')));
  current_user_id  uuid    := auth.uid();
  target_trip_id   uuid;
  target_owner_id  uuid;
  rows_affected    integer := 0;
  recent_attempts  integer;
  lock_bytes       bytea;
  lock_key_1       integer;
  lock_key_2       integer;
begin
  if current_user_id is null then
    raise exception 'Authentication required: user must be authenticated to join a trip.'
      using errcode = '28000';
  end if;

  lock_bytes := uuid_send(current_user_id);
  lock_key_1 :=
      (get_byte(lock_bytes, 0) << 24)
    + (get_byte(lock_bytes, 1) << 16)
    + (get_byte(lock_bytes, 2) << 8)
    + get_byte(lock_bytes, 3);
  lock_key_2 :=
      (get_byte(lock_bytes, 4) << 24)
    + (get_byte(lock_bytes, 5) << 16)
    + (get_byte(lock_bytes, 6) << 8)
    + get_byte(lock_bytes, 7);

  -- Serialize attempts per user so the count-and-insert check is atomic.
  perform pg_advisory_xact_lock(lock_key_1, lock_key_2);

  -- Rate limit: at most 20 join attempts per user per hour.
  select count(*) into recent_attempts
  from public.join_code_attempts
  where user_id      = current_user_id
    and attempted_at > now() - interval '1 hour';

  if recent_attempts >= 20 then
    raise exception 'Too many join attempts. Please wait before trying again.'
      using errcode = '53400';
  end if;

  if normalized_code = '' then
    return jsonb_build_object('status', 'trip_not_found');
  end if;

  -- Record this non-empty attempt before querying the trips table.
  insert into public.join_code_attempts (user_id) values (current_user_id);

  select id, owner_id
  into target_trip_id, target_owner_id
  from public.trips
  where share_code = normalized_code
  limit 1;

  if target_trip_id is null then
    return jsonb_build_object('status', 'trip_not_found');
  end if;

  if target_owner_id = current_user_id then
    return jsonb_build_object('status', 'already_joined');
  end if;

  insert into public.shared_access (trip_id, user_id, permission)
  values (target_trip_id, current_user_id, 'editor')
  on conflict (trip_id, user_id) do nothing;

  get diagnostics rows_affected = row_count;

  if rows_affected > 0 then
    return jsonb_build_object(
      'status',     'success',
      'trip_id',    target_trip_id,
      'permission', 'editor'
    );
  end if;

  -- Already joined: fetch current permission to return it.
  return jsonb_build_object(
    'status',     'already_joined',
    'trip_id',    target_trip_id,
    'permission', (
      select permission
      from public.shared_access
      where trip_id = target_trip_id and user_id = current_user_id
    )
  );
end;
$$;
