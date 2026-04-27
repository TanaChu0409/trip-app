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

create or replace function public.can_edit_stop(p_stop_id uuid)
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
    where stops.id = p_stop_id
      and public.is_trip_editor(days.trip_id)
  );
$$;

create or replace function public.storage_stop_id(p_name text)
returns uuid
language sql
immutable
as $$
  select case
    when split_part(p_name, '/', 3) ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
      then split_part(p_name, '/', 3)::uuid
    else null
  end
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
values ('stop-photos', 'stop-photos', false)
on conflict (id) do nothing;

update storage.buckets
set public = false
where id = 'stop-photos';

-- ── Storage policies ───────────────────────────────────────────────────────

drop policy if exists "stop_photos_storage_read" on storage.objects;
create policy "stop_photos_storage_read"
on storage.objects
for select
using (
  bucket_id = 'stop-photos'
  and public.can_read_stop(public.storage_stop_id(name))
);

-- Authenticated users may upload to stop-photos bucket
drop policy if exists "stop_photos_storage_insert" on storage.objects;
create policy "stop_photos_storage_insert"
on storage.objects
for insert
with check (
  bucket_id = 'stop-photos'
  and auth.role() = 'authenticated'
  and owner = auth.uid()
  and split_part(name, '/', 1) = auth.uid()::text
  and public.can_edit_stop(public.storage_stop_id(name))
);

-- Authenticated users may delete their own uploads
drop policy if exists "stop_photos_storage_delete" on storage.objects;
create policy "stop_photos_storage_delete"
on storage.objects
for delete
using (
  bucket_id = 'stop-photos'
  and public.can_edit_stop(public.storage_stop_id(name))
);
