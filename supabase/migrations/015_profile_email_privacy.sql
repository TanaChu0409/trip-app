-- SECURITY FIX: Restrict profile email visibility.
--
-- The previous profiles_read_authenticated policy allowed any authenticated
-- user to read the email address of every user in the system. This is a
-- privacy risk: a malicious (but authenticated) user could enumerate all
-- registered users' emails.
--
-- Fix:
--   1. Drop the broad read policy.
--   2. Keep full-row access (including email) for self only.
--   3. Expose peer/owner-safe profile fields through a dedicated
--      profiles_public view that never returns email.
--
-- NOTE: PostgreSQL RLS is row-level, not column-level. Column masking is
-- achieved here via a dedicated view (profiles_public) that excludes the
-- email column. Clients that need member lists should SELECT from
-- profiles_public instead of profiles.

drop policy if exists "profiles_read_authenticated" on public.profiles;

-- Full profile (including email) visible to the owner only.
create policy "profiles_read_self"
on public.profiles
for select
using (id = auth.uid());

drop policy if exists "profiles_read_shared_trip_peer" on public.profiles;
drop policy if exists "profiles_read_trip_member_for_owner" on public.profiles;

create or replace view public.profiles_public as
select
  p.id,
  p.display_name,
  p.avatar_url
from public.profiles p
where auth.uid() is not null
  and (
    p.id = auth.uid()
    or exists (
      select 1
      from public.shared_access sa1
      join public.shared_access sa2
        on sa2.trip_id = sa1.trip_id
      where sa1.user_id = p.id
        and sa2.user_id = auth.uid()
    )
    or exists (
      select 1
      from public.shared_access sa
      where sa.user_id = p.id
        and public.is_trip_owner(sa.trip_id)
    )
  );

revoke all on public.profiles_public from public;
grant select on public.profiles_public to authenticated;
