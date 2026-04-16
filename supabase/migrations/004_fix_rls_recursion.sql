-- Fix infinite recursion between trips_shared_read and shared_access_owner_read.
--
-- The cycle:
--   SELECT trips → trips_shared_read → queries shared_access
--   → shared_access_owner_read → queries trips → trips_shared_read → ...
--
-- Solution: use a SECURITY DEFINER function that reads trips without
-- triggering RLS, then rewrite the shared_access owner policies to use it.

create or replace function public.is_trip_owner(p_trip_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.trips
    where id = p_trip_id and owner_id = auth.uid()
  );
$$;

-- Recreate shared_access owner policies using the recursion-safe function
drop policy if exists "shared_access_owner_read" on public.shared_access;
create policy "shared_access_owner_read"
on public.shared_access
for select
using (public.is_trip_owner(trip_id));

drop policy if exists "shared_access_owner_delete" on public.shared_access;
create policy "shared_access_owner_delete"
on public.shared_access
for delete
using (public.is_trip_owner(trip_id) or user_id = auth.uid());
