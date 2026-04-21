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
