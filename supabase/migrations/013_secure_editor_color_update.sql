-- SECURITY FIX: Replace over-permissive trips_editor_update_color RLS policy.
--
-- The previous policy (migration 010) allowed any editor to UPDATE the entire
-- trips row — including sensitive fields like owner_id, share_code, title, and
-- dates — using the raw PostgREST API. The code comment "application layer
-- ensures editors only call updateTripColor()" relied on client-side enforcement
-- which is trivially bypassed.
--
-- Fix: Drop the policy and replace with a SECURITY DEFINER RPC that only
-- touches the color column. The Flutter app calls update_trip_color() instead
-- of doing a direct table UPDATE.

drop policy if exists "trips_editor_update_color" on public.trips;

create or replace function public.update_trip_color(
  p_trip_id uuid,
  p_color   text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not (public.is_trip_owner(p_trip_id) or public.is_trip_editor(p_trip_id)) then
    raise exception 'Permission denied: only the trip owner or an editor may update the color.'
      using errcode = '42501';
  end if;

  update public.trips
  set color = p_color
  where id = p_trip_id;
end;
$$;

revoke all on function public.update_trip_color(uuid, text) from public;
grant execute on function public.update_trip_color(uuid, text) to authenticated;
