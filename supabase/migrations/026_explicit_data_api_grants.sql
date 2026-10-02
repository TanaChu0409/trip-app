-- Normalize Data API privileges for projects that already ran migrations
-- 001-025 while Supabase's broad default grants were enabled.

-- Future public-schema objects stay private until their creating migration
-- grants the exact privileges required by the application.
alter default privileges for role postgres in schema public
  revoke all on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke all on sequences from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke execute on functions from public, anon, authenticated, service_role;

-- App data tables: anon has no direct access. RLS remains the row-level
-- boundary for authenticated users, while service_role keeps administrative
-- access. Direct trip updates remain forbidden for authenticated clients;
-- archive and colour changes go through scoped RPCs.
revoke all on table
  public.trips,
  public.days,
  public.stops,
  public.parking_spots,
  public.shared_access,
  public.stop_photos
from public, anon, authenticated, service_role;

grant select, insert, delete on table public.trips
  to authenticated;
grant select, insert, update, delete on table
  public.days,
  public.stops,
  public.parking_spots,
  public.shared_access,
  public.stop_photos
to authenticated;

grant select, insert, update, delete on table
  public.trips,
  public.days,
  public.stops,
  public.parking_spots,
  public.shared_access,
  public.stop_photos
to service_role;

-- Profiles expose only non-email columns for reads. A user may update the
-- allowed profile fields on their own row under RLS, but cannot INSERT,
-- DELETE, read email, or retrieve email through RETURNING.
revoke all on table public.profiles
  from public, anon, authenticated, service_role;
revoke select (id, display_name, email, avatar_url, created_at, updated_at),
       insert (id, display_name, email, avatar_url, created_at, updated_at),
       update (id, display_name, email, avatar_url, created_at, updated_at),
       references (id, display_name, email, avatar_url, created_at, updated_at)
  on table public.profiles
  from public, anon, authenticated, service_role;

grant select (id, display_name, avatar_url, created_at, updated_at)
  on table public.profiles to authenticated;
grant update (display_name, email, avatar_url, updated_at)
  on table public.profiles to authenticated;
grant select, insert, update, delete on table public.profiles to service_role;

revoke all on table public.profiles_public
  from public, anon, authenticated, service_role;
grant select on table public.profiles_public to authenticated, service_role;

-- Rate-limit bookkeeping is private to SECURITY DEFINER RPCs and trusted
-- maintenance jobs.
revoke all on table
  public.join_code_attempts,
  public.invite_member_attempts
from public, anon, authenticated, service_role;
grant select, insert, update, delete on table
  public.join_code_attempts,
  public.invite_member_attempts
to service_role;

-- Client-facing RPC allowlist.
revoke all on function public.join_trip_by_code(text)
  from public, anon, authenticated, service_role;
revoke all on function public.invite_member_by_email(uuid, text, text)
  from public, anon, authenticated, service_role;
revoke all on function public.update_trip_color(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.remove_trip_custom_stop_color(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.create_stop_with_palette(uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.update_stop_with_palette(uuid, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.set_owned_trip_archived(uuid, boolean)
  from public, anon, authenticated, service_role;

grant execute on function
  public.join_trip_by_code(text),
  public.invite_member_by_email(uuid, text, text),
  public.update_trip_color(uuid, text),
  public.remove_trip_custom_stop_color(uuid, text),
  public.create_stop_with_palette(uuid, jsonb),
  public.update_stop_with_palette(uuid, jsonb),
  public.set_owned_trip_archived(uuid, boolean)
to authenticated, service_role;

-- Helpers called by authenticated RLS and Storage policies. service_role
-- bypasses RLS and internal SECURITY DEFINER calls execute as their owner.
revoke all on function public.is_trip_owner(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.is_trip_editor(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.is_active_trip_owner(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.is_stop_trip_owner(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.can_edit_stop(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.can_read_stop(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.storage_stop_id(text)
  from public, anon, authenticated, service_role;
revoke all on function public.can_read_trip_peer_profile(uuid, uuid)
  from public, anon, authenticated, service_role;

grant execute on function
  public.is_trip_owner(uuid),
  public.is_trip_editor(uuid),
  public.is_active_trip_owner(uuid),
  public.is_stop_trip_owner(uuid),
  public.can_edit_stop(uuid),
  public.can_read_stop(uuid),
  public.storage_stop_id(text),
  public.can_read_trip_peer_profile(uuid, uuid)
to authenticated;

-- Purge functions are maintenance-only.
revoke all on function public.purge_join_code_attempts()
  from public, anon, authenticated, service_role;
revoke all on function public.purge_invite_member_attempts()
  from public, anon, authenticated, service_role;
grant execute on function
  public.purge_join_code_attempts(),
  public.purge_invite_member_attempts()
to service_role;

-- Trigger and implementation helpers are not callable by Data API roles.
revoke all on function public.handle_new_user()
  from public, anon, authenticated, service_role;
revoke all on function public.enforce_stop_photo_limit()
  from public, anon, authenticated, service_role;
revoke all on function public.can_edit_trip(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.add_custom_stop_color(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.sync_trip_custom_stop_color()
  from public, anon, authenticated, service_role;
revoke all on function public.prevent_archived_trip_membership_changes()
  from public, anon, authenticated, service_role;

-- Lock the immutable parser to trusted built-ins only.
alter function public.storage_stop_id(text) set search_path = pg_catalog;

-- Some older hosted projects contain this Supabase-managed helper in public.
-- Remove client execution when present without making clean local replays fail.
do $$
begin
  if to_regprocedure('public.rls_auto_enable()') is not null then
    execute 'revoke all on function public.rls_auto_enable() from public, anon, authenticated, service_role';
  end if;
end;
$$;
