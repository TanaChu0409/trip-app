drop policy if exists "days_owner_all" on public.days;
drop policy if exists "days_shared_read" on public.days;
drop policy if exists "stops_owner_all" on public.stops;
drop policy if exists "stops_shared_read" on public.stops;
drop policy if exists "parking_spots_owner_all" on public.parking_spots;
drop policy if exists "parking_spots_shared_read" on public.parking_spots;
drop policy if exists "shared_access_owner_read" on public.shared_access;
drop policy if exists "shared_access_owner_delete" on public.shared_access;

create policy "days_owner_all"
on public.days
for all
using (
  exists (
    select 1
    from public.trips
    where trips.id = days.trip_id and trips.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.trips
    where trips.id = days.trip_id and trips.owner_id = auth.uid()
  )
);

create policy "days_shared_read"
on public.days
for select
using (
  exists (
    select 1
    from public.shared_access
    where shared_access.trip_id = days.trip_id and shared_access.user_id = auth.uid()
  )
);

create policy "stops_owner_all"
on public.stops
for all
using (
  exists (
    select 1
    from public.days
    join public.trips on trips.id = days.trip_id
    where days.id = stops.day_id and trips.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.days
    join public.trips on trips.id = days.trip_id
    where days.id = stops.day_id and trips.owner_id = auth.uid()
  )
);

create policy "stops_shared_read"
on public.stops
for select
using (
  exists (
    select 1
    from public.days
    join public.shared_access on shared_access.trip_id = days.trip_id
    where days.id = stops.day_id and shared_access.user_id = auth.uid()
  )
);

create policy "parking_spots_owner_all"
on public.parking_spots
for all
using (
  exists (
    select 1
    from public.stops
    join public.days on days.id = stops.day_id
    join public.trips on trips.id = days.trip_id
    where stops.id = parking_spots.stop_id and trips.owner_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.stops
    join public.days on days.id = stops.day_id
    join public.trips on trips.id = days.trip_id
    where stops.id = parking_spots.stop_id and trips.owner_id = auth.uid()
  )
);

create policy "parking_spots_shared_read"
on public.parking_spots
for select
using (
  exists (
    select 1
    from public.stops
    join public.days on days.id = stops.day_id
    join public.shared_access on shared_access.trip_id = days.trip_id
    where stops.id = parking_spots.stop_id and shared_access.user_id = auth.uid()
  )
);

create policy "shared_access_owner_read"
on public.shared_access
for select
using (
  exists (
    select 1
    from public.trips
    where trips.id = shared_access.trip_id and trips.owner_id = auth.uid()
  )
);

create policy "shared_access_owner_delete"
on public.shared_access
for delete
using (
  exists (
    select 1
    from public.trips
    where trips.id = shared_access.trip_id and trips.owner_id = auth.uid()
  )
);