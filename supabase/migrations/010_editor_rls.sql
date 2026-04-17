-- RLS policies that allow trip editors (guests with permission='editor')
-- to mutate days, stops, parking_spots, and update the trip color.

-- Helper: returns true when the caller is an editor (not owner) of the given trip.
create or replace function public.is_trip_editor(p_trip_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.shared_access
    where trip_id    = p_trip_id
      and user_id    = auth.uid()
      and permission = 'editor'
  );
$$;

-- ── days ────────────────────────────────────────────────────────────────────

drop policy if exists "days_editor_all" on public.days;
create policy "days_editor_all"
on public.days
for all
using (public.is_trip_editor(trip_id))
with check (public.is_trip_editor(trip_id));

-- ── stops ───────────────────────────────────────────────────────────────────

drop policy if exists "stops_editor_all" on public.stops;
create policy "stops_editor_all"
on public.stops
for all
using (
  exists (
    select 1
    from public.days
    where days.id = stops.day_id
      and public.is_trip_editor(days.trip_id)
  )
)
with check (
  exists (
    select 1
    from public.days
    where days.id = stops.day_id
      and public.is_trip_editor(days.trip_id)
  )
);

-- ── parking_spots ────────────────────────────────────────────────────────────

drop policy if exists "parking_spots_editor_all" on public.parking_spots;
create policy "parking_spots_editor_all"
on public.parking_spots
for all
using (
  exists (
    select 1
    from public.stops
    join public.days on days.id = stops.day_id
    where stops.id = parking_spots.stop_id
      and public.is_trip_editor(days.trip_id)
  )
)
with check (
  exists (
    select 1
    from public.stops
    join public.days on days.id = stops.day_id
    where stops.id = parking_spots.stop_id
      and public.is_trip_editor(days.trip_id)
  )
);

-- ── trips – allow editors to update the color column only ──────────────────
-- NOTE: Supabase RLS does not support column-level grants via policies alone,
-- but we can allow UPDATE on the trips table for editors (same as owner_all).
-- The application layer ensures editors only call updateTripColor().

drop policy if exists "trips_editor_update_color" on public.trips;
create policy "trips_editor_update_color"
on public.trips
for update
using (public.is_trip_editor(id))
with check (public.is_trip_editor(id));
