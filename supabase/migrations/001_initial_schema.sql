create extension if not exists pgcrypto;

create table if not exists public.trips (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  start_date date not null,
  end_date date not null,
  owner_id uuid not null,
  share_code text unique,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.days (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  date date not null,
  label text not null,
  subtitle text,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.stops (
  id uuid primary key default gen_random_uuid(),
  day_id uuid not null references public.days(id) on delete cascade,
  time time,
  title text not null,
  note text,
  badge text,
  map_url text,
  latitude double precision,
  longitude double precision,
  is_highlight boolean not null default false,
  reminder_minutes integer not null default 30,
  geofence_radius_m integer not null default 500,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.parking_spots (
  id uuid primary key default gen_random_uuid(),
  stop_id uuid not null references public.stops(id) on delete cascade,
  name text not null,
  map_url text not null,
  sort_order integer not null default 0
);

create table if not exists public.shared_access (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  user_id uuid not null,
  joined_at timestamptz not null default now(),
  unique(trip_id, user_id)
);

create index if not exists idx_days_trip_id on public.days(trip_id);
create index if not exists idx_stops_day_id on public.stops(day_id);
create index if not exists idx_parking_spots_stop_id on public.parking_spots(stop_id);
create index if not exists idx_shared_access_trip_user on public.shared_access(trip_id, user_id);

alter table public.trips enable row level security;
alter table public.days enable row level security;
alter table public.stops enable row level security;
alter table public.parking_spots enable row level security;
alter table public.shared_access enable row level security;

create policy "trips_owner_all"
on public.trips
for all
using (owner_id = auth.uid())
with check (owner_id = auth.uid());

create policy "trips_shared_read"
on public.trips
for select
using (
  exists (
    select 1
    from public.shared_access sa
    where sa.trip_id = trips.id and sa.user_id = auth.uid()
  )
);

create policy "shared_access_insert_self"
on public.shared_access
for insert
with check (user_id = auth.uid());

create policy "shared_access_read_self"
on public.shared_access
for select
using (user_id = auth.uid());
