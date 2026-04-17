-- Add permission column to shared_access.
-- Values: 'editor' (can modify trip content) or 'viewer' (read-only).
-- Default 'editor' so existing and new members start with edit access.

alter table public.shared_access
  add column if not exists permission text not null default 'editor';

alter table public.shared_access
  drop constraint if exists shared_access_permission_check;

alter table public.shared_access
  add constraint shared_access_permission_check
  check (permission in ('editor', 'viewer'));

-- Allow trip owners to update permission for any member of their trip.
drop policy if exists "shared_access_owner_update" on public.shared_access;
create policy "shared_access_owner_update"
on public.shared_access
for update
using (public.is_trip_owner(trip_id))
with check (public.is_trip_owner(trip_id));

-- Enable Realtime replication so clients can subscribe to permission changes.
-- (Run this once; safe to repeat.)
alter publication supabase_realtime add table public.shared_access;
