-- SECURITY FIX: Remove SECURITY DEFINER from profiles_public view.
--
-- Problem: PostgreSQL views default to running with the permissions of the
-- view owner (SECURITY DEFINER behaviour), bypassing the querying user's RLS.
-- The Supabase linter flags this as a security concern.
--
-- Root cause: After migration 015, the profiles table RLS only allows a user
-- to read their own row (profiles_read_self). The profiles_public view was
-- implicitly relying on SECURITY DEFINER to bypass that restriction and join
-- peer profiles. Switching to security_invoker without compensating RLS would
-- break trip member lists entirely.
--
-- Full fix (three steps):
--   1. Add a SECURITY DEFINER helper that returns only a boolean membership
--      result, so profiles RLS and the security_invoker view do not need to
--      read shared_access rows directly under caller RLS.
--   2. Restrict the email column at the grant level so that even with the
--      broader peer-read RLS, authenticated users cannot read email addresses
--      by querying profiles directly. Email is available from auth.getUser()
--      in the Flutter app and does not need to be exposed via the table.
--   3. Recreate profiles_public with security_invoker = true. The view keeps
--      the same visible rows as migration 015 while using the helper.
--
-- Requires PostgreSQL 15+ (available on all Supabase Cloud projects).

-- ── Step 1: Add membership helper and peer-read RLS policy ───────────────────
create or replace function public.can_read_trip_peer_profile(
  p_profile_id uuid,
  p_viewer_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select p_viewer_id is not null
    and (
      exists (
        select 1
        from public.shared_access sa1
        join public.shared_access sa2
          on sa2.trip_id = sa1.trip_id
        where sa1.user_id = p_profile_id
          and sa2.user_id = p_viewer_id
      )
      or exists (
        select 1
        from public.shared_access sa
        join public.trips t
          on t.id = sa.trip_id
        where sa.user_id = p_profile_id
          and t.owner_id = p_viewer_id
      )
    );
$$;

revoke all on function public.can_read_trip_peer_profile(uuid, uuid) from public;
grant execute on function public.can_read_trip_peer_profile(uuid, uuid) to authenticated;
grant execute on function public.can_read_trip_peer_profile(uuid, uuid) to service_role;

drop policy if exists "profiles_read_trip_peer" on public.profiles;
create policy "profiles_read_trip_peer"
on public.profiles
for select
using (public.can_read_trip_peer_profile(id, auth.uid()));

-- ── Step 2: Restrict column-level access on public.profiles ──────────────────
-- Supabase grants SELECT on all public tables to authenticated by default.
-- We revoke that broad grant and re-grant only the non-sensitive columns.
-- This ensures that even with the peer-read RLS policy above, authenticated
-- users cannot read the email column by querying profiles directly.
-- (service_role retains full access via its own Supabase-managed grants.)
revoke select on public.profiles from authenticated, anon;
grant select (id, display_name, avatar_url, created_at, updated_at)
  on public.profiles to authenticated;

-- ── Step 3: Recreate profiles_public with security_invoker = true ────────────
-- The view keeps the same membership rules as migration 015, but delegates the
-- shared-trip check to the SECURITY DEFINER helper above.
drop view if exists public.profiles_public;

create view public.profiles_public
  with (security_invoker = true)
as
select
  p.id,
  p.display_name,
  p.avatar_url
from public.profiles p
where auth.uid() is not null
  and (
    p.id = auth.uid()
    or public.can_read_trip_peer_profile(p.id, auth.uid())
  );

revoke all on public.profiles_public from public;
grant select on public.profiles_public to authenticated;
