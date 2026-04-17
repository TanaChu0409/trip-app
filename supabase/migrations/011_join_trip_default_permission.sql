-- Update join_trip_by_code to:
--  1. Insert with permission = 'editor' (explicit default).
--  2. Return permission in the response payload.

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
begin
  if current_user_id is null then
    raise exception 'Authentication required: user must be authenticated to join a trip.'
      using errcode = '28000';
  end if;

  if normalized_code = '' then
    return jsonb_build_object('status', 'trip_not_found');
  end if;

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
