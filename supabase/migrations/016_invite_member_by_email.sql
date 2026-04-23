-- Invite a member to a trip by their email address.
-- Replaces the share-code join mechanism: only the trip owner can call this.
-- The invitee must already have an account (i.e. have signed in at least once
-- so that a row exists in auth.users with the given email).
--
-- Returns JSONB with a `status` field and, on success, `trip_id` and `permission`.
--
-- Possible status values:
--   'success'            – Row inserted into shared_access.
--   'not_owner'          – Caller is not the trip owner.
--   'invalid_permission' – p_permission is not 'editor' or 'viewer'.
--   'user_not_found'     – No auth.users row matches the normalised email.
--   'cannot_invite_self' – Owner is trying to invite themselves.
--   'already_member'     – Invitee already has a shared_access row for this trip.

create table if not exists public.invite_member_attempts (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        not null references auth.users(id) on delete cascade,
  attempted_at timestamptz not null default now()
);

create index if not exists idx_invite_member_attempts_user_time
  on public.invite_member_attempts(user_id, attempted_at);

alter table public.invite_member_attempts enable row level security;
-- No direct client access needed; only the SECURITY DEFINER function writes to it.

-- Purge attempts older than 24 hours to keep the table small.
-- Schedule `select public.purge_invite_member_attempts();` on an interval (for
-- example, hourly) to enforce retention.
create or replace function public.purge_invite_member_attempts()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.invite_member_attempts
  where attempted_at < now() - interval '24 hours';
$$;

revoke all on function public.purge_invite_member_attempts() from public;
grant execute on function public.purge_invite_member_attempts() to service_role;

create or replace function public.invite_member_by_email(
  p_trip_id    uuid,
  p_email      text,
  p_permission text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_id     uuid := auth.uid();
  normalised    text := lower(trim(coalesce(p_email, '')));
  invitee_id    uuid;
  trip_owner_id uuid;
  recent_attempts integer;
  lock_bytes     bytea;
  lock_key_1     integer;
  lock_key_2     integer;
begin
  -- Must be authenticated.
  if caller_id is null then
    raise exception 'Authentication required.'
      using errcode = '28000';
  end if;

  -- Validate permission value (also handles NULL p_permission).
  if p_permission is null or p_permission not in ('editor', 'viewer') then
    return jsonb_build_object('status', 'invalid_permission');
  end if;

  -- Caller must be the trip owner.
  select owner_id
    into trip_owner_id
    from public.trips
   where id = p_trip_id;

  if trip_owner_id is null or trip_owner_id <> caller_id then
    return jsonb_build_object('status', 'not_owner');
  end if;

  if normalised = '' then
    raise exception 'Email address cannot be empty or contain only whitespace.'
      using errcode = '22023';
  end if;

  -- Serialize invite attempts per owner so the count-and-insert check is atomic.
  lock_bytes := uuid_send(caller_id);
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

  perform pg_advisory_xact_lock(lock_key_1, lock_key_2);

  -- Rate limit: at most 20 invite attempts per owner per hour before querying auth.users,
  -- after confirming the caller owns the target trip.
  select count(*) into recent_attempts
  from public.invite_member_attempts
  where user_id = caller_id
    and attempted_at > now() - interval '1 hour';

  if recent_attempts >= 20 then
    -- Match join_trip_by_code's retry-later rate-limit signal.
    raise exception 'Too many invite attempts. Please wait before trying again.'
      using errcode = '53400';
  end if;

  insert into public.invite_member_attempts (user_id) values (caller_id);

  -- Look up the invitee in auth.users by (normalised) email.
  -- auth.users is only accessible to SECURITY DEFINER functions.
  select id
    into invitee_id
    from auth.users
   where lower(trim(email)) = normalised
   limit 1;

  if invitee_id is null then
    return jsonb_build_object('status', 'user_not_found');
  end if;

  -- Prevent self-invite.
  if invitee_id = caller_id then
    return jsonb_build_object('status', 'cannot_invite_self');
  end if;

  -- Check for an existing membership.
  if exists (
    select 1
      from public.shared_access
     where trip_id = p_trip_id
       and user_id = invitee_id
  ) then
    return jsonb_build_object('status', 'already_member');
  end if;

  -- Insert the membership row. Use ON CONFLICT to avoid a race where
  -- another concurrent invite creates the membership after the EXISTS check.
  insert into public.shared_access (trip_id, user_id, permission)
  values (p_trip_id, invitee_id, p_permission)
  on conflict (trip_id, user_id) do nothing;

  if not found then
    return jsonb_build_object('status', 'already_member');
  end if;

  return jsonb_build_object(
    'status',     'success',
    'trip_id',    p_trip_id,
    'permission', p_permission
  );
end;
$$;

-- Only authenticated users need to call this; service_role inherits implicitly.
revoke all on function public.invite_member_by_email(uuid, text, text) from public;
grant execute on function public.invite_member_by_email(uuid, text, text) to authenticated;
