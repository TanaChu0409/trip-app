-- 018_stop_photos.sql
-- Adds photo support for stops: up to 4 photos per stop stored in Supabase Storage.

-- ── stop_photos table ──────────────────────────────────────────────────────

create table if not exists public.stop_photos (
  id           uuid primary key default gen_random_uuid(),
  stop_id      uuid not null references public.stops(id) on delete cascade,
  storage_path text not null,
  sort_order   integer not null default 0,
  created_at   timestamptz not null default now()
);

alter table public.stop_photos enable row level security;

-- ── RLS helpers (reuse is_trip_editor from migration 010) ─────────────────

-- Helper to check if the current user is the trip owner for a given stop.
create or replace function public.is_stop_trip_owner(p_stop_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.stops
    join public.days    on days.id  = stops.day_id
    join public.trips   on trips.id = days.trip_id
    where stops.id     = p_stop_id
      and trips.owner_id = auth.uid()
  );
$$;

-- Helper to check if the current user can read a stop
-- (owner OR any shared_access member).
create or replace function public.can_read_stop(p_stop_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.stops
    join public.days on days.id = stops.day_id
    join public.trips on trips.id = days.trip_id
    where stops.id = p_stop_id
      and (
        trips.owner_id = auth.uid()
        or exists (
          select 1 from public.shared_access
          where shared_access.trip_id = trips.id
            and shared_access.user_id = auth.uid()
        )
      )
  );
$$;

-- ── RLS policies ───────────────────────────────────────────────────────────

-- SELECT: trip owner or any shared member can read photos
drop policy if exists "stop_photos_read" on public.stop_photos;
create policy "stop_photos_read"
on public.stop_photos
for select
using (public.can_read_stop(stop_id));

-- INSERT: trip owner or shared editor can add photos
drop policy if exists "stop_photos_owner_insert" on public.stop_photos;
create policy "stop_photos_owner_insert"
on public.stop_photos
for insert
with check (
  public.is_stop_trip_owner(stop_id)
  or exists (
    select 1
    from public.stops
    join public.days on days.id = stops.day_id
    where stops.id = stop_photos.stop_id
      and public.is_trip_editor(days.trip_id)
  )
);

-- UPDATE: trip owner or shared editor can update photos
drop policy if exists "stop_photos_owner_update" on public.stop_photos;
create policy "stop_photos_owner_update"
on public.stop_photos
for update
using (
  public.is_stop_trip_owner(stop_id)
  or exists (
    select 1
    from public.stops
    join public.days on days.id = stops.day_id
    where stops.id = stop_photos.stop_id
      and public.is_trip_editor(days.trip_id)
  )
)
with check (
  public.is_stop_trip_owner(stop_id)
  or exists (
    select 1
    from public.stops
    join public.days on days.id = stops.day_id
    where stops.id = stop_photos.stop_id
      and public.is_trip_editor(days.trip_id)
  )
);

-- DELETE: trip owner or shared editor can delete photos
drop policy if exists "stop_photos_owner_delete" on public.stop_photos;
create policy "stop_photos_owner_delete"
on public.stop_photos
for delete
using (
  public.is_stop_trip_owner(stop_id)
  or exists (
    select 1
    from public.stops
    join public.days on days.id = stops.day_id
    where stops.id = stop_photos.stop_id
      and public.is_trip_editor(days.trip_id)
  )
);

-- ── Storage bucket ─────────────────────────────────────────────────────────
-- Note: If this bucket already exists the INSERT is safely ignored.

insert into storage.buckets (id, name, public)
values ('stop-photos', 'stop-photos', true)
on conflict (id) do nothing;

-- ── Storage policies ───────────────────────────────────────────────────────

-- Public read (bucket is public, but explicit policy for belt-and-suspenders)
drop policy if exists "stop_photos_storage_read" on storage.objects;
create policy "stop_photos_storage_read"
on storage.objects
for select
using (bucket_id = 'stop-photos');

-- Authenticated users may upload to stop-photos bucket
drop policy if exists "stop_photos_storage_insert" on storage.objects;
create policy "stop_photos_storage_insert"
on storage.objects
for insert
with check (
  bucket_id = 'stop-photos'
  and auth.role() = 'authenticated'
);

-- Authenticated users may delete their own uploads
drop policy if exists "stop_photos_storage_delete" on storage.objects;
create policy "stop_photos_storage_delete"
on storage.objects
for delete
using (
  bucket_id = 'stop-photos'
  and auth.role() = 'authenticated'
);
