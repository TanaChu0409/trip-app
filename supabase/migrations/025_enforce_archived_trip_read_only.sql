-- Archived trips remain readable, but content writes require an active trip.
create or replace function public.is_active_trip_owner(p_trip_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.trips
    where id = p_trip_id
      and owner_id = auth.uid()
      and not is_archived
  );
$$;

create or replace function public.is_trip_editor(p_trip_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.shared_access sa
    join public.trips t on t.id = sa.trip_id
    where sa.trip_id = p_trip_id
      and sa.user_id = auth.uid()
      and sa.permission = 'editor'
      and not t.is_archived
  );
$$;

create or replace function public.can_edit_trip(p_trip_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1
    from public.trips t
    where t.id = p_trip_id
      and not t.is_archived
      and (t.owner_id = auth.uid() or public.is_trip_editor(p_trip_id))
  );
$$;

create or replace function public.update_trip_color(
  p_trip_id uuid,
  p_color text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.can_edit_trip(p_trip_id) then
    raise exception 'Permission denied: archived trips cannot be edited.'
      using errcode = '42501';
  end if;

  update public.trips
  set color = p_color
  where id = p_trip_id;
end;
$$;

-- Client roles may update a trip only through narrowly scoped SECURITY
-- DEFINER functions. This prevents stale clients from modifying archived rows.
revoke update on public.trips from anon, authenticated;

-- Keep archived trips readable while allowing only active trips to be
-- deleted.  The archive/restore RPC below is SECURITY DEFINER, so it remains
-- available without granting general UPDATE access to client roles.
drop policy if exists "trips_owner_all" on public.trips;
create policy "trips_owner_read"
on public.trips
for select
using (owner_id = auth.uid());
create policy "trips_owner_insert"
on public.trips
for insert
with check (owner_id = auth.uid());
create policy "trips_owner_delete_active"
on public.trips
for delete
using (owner_id = auth.uid() and not is_archived);

create or replace function public.set_owned_trip_archived(
  p_trip_id uuid,
  p_is_archived boolean
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_trip_owner(p_trip_id) then
    return false;
  end if;

  update public.trips
  set is_archived = p_is_archived
  where id = p_trip_id;

  return found;
end;
$$;

revoke all on function public.set_owned_trip_archived(uuid, boolean) from public;
grant execute on function public.set_owned_trip_archived(uuid, boolean) to authenticated;

-- Keep archived child rows readable, while denying all direct content writes.
-- Editors are covered by is_trip_editor above; these policies add the same
-- protection for owners, whose previous FOR ALL policies also permitted writes.
drop policy if exists "days_owner_all" on public.days;
create policy "days_owner_read"
on public.days
for select
using (public.is_trip_owner(trip_id));
create policy "days_owner_insert"
on public.days
for insert
with check (public.is_active_trip_owner(trip_id));
create policy "days_owner_update"
on public.days
for update
using (public.is_active_trip_owner(trip_id))
with check (public.is_active_trip_owner(trip_id));
create policy "days_owner_delete"
on public.days
for delete
using (public.is_active_trip_owner(trip_id));

drop policy if exists "stops_owner_all" on public.stops;
create policy "stops_owner_read"
on public.stops
for select
using (
  exists (
    select 1 from public.days
    where days.id = stops.day_id
      and public.is_trip_owner(days.trip_id)
  )
);
create policy "stops_owner_insert"
on public.stops
for insert
with check (
  exists (
    select 1 from public.days
    where days.id = stops.day_id
      and public.is_active_trip_owner(days.trip_id)
  )
);
create policy "stops_owner_update"
on public.stops
for update
using (
  exists (
    select 1 from public.days
    where days.id = stops.day_id
      and public.is_active_trip_owner(days.trip_id)
  )
)
with check (
  exists (
    select 1 from public.days
    where days.id = stops.day_id
      and public.is_active_trip_owner(days.trip_id)
  )
);
create policy "stops_owner_delete"
on public.stops
for delete
using (
  exists (
    select 1 from public.days
    where days.id = stops.day_id
      and public.is_active_trip_owner(days.trip_id)
  )
);

drop policy if exists "parking_spots_owner_all" on public.parking_spots;
create policy "parking_spots_owner_read"
on public.parking_spots
for select
using (
  exists (
    select 1 from public.stops
    join public.days on days.id = stops.day_id
    where stops.id = parking_spots.stop_id
      and public.is_trip_owner(days.trip_id)
  )
);
create policy "parking_spots_owner_insert"
on public.parking_spots
for insert
with check (
  exists (
    select 1 from public.stops
    join public.days on days.id = stops.day_id
    where stops.id = parking_spots.stop_id
      and public.is_active_trip_owner(days.trip_id)
  )
);
create policy "parking_spots_owner_update"
on public.parking_spots
for update
using (
  exists (
    select 1 from public.stops
    join public.days on days.id = stops.day_id
    where stops.id = parking_spots.stop_id
      and public.is_active_trip_owner(days.trip_id)
  )
)
with check (
  exists (
    select 1 from public.stops
    join public.days on days.id = stops.day_id
    where stops.id = parking_spots.stop_id
      and public.is_active_trip_owner(days.trip_id)
  )
);
create policy "parking_spots_owner_delete"
on public.parking_spots
for delete
using (
  exists (
    select 1 from public.stops
    join public.days on days.id = stops.day_id
    where stops.id = parking_spots.stop_id
      and public.is_active_trip_owner(days.trip_id)
  )
);

-- Stop-photo owner policies are based on this helper. Replacing it keeps
-- photo metadata and Storage uploads read-only for archived trips as well.
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
    join public.days on days.id = stops.day_id
    where stops.id = p_stop_id
      and public.is_active_trip_owner(days.trip_id)
  );
$$;

-- Existing members can still leave an archived trip themselves, but owners
-- and stale clients cannot change membership until the trip is restored.
drop policy if exists "shared_access_owner_update" on public.shared_access;
create policy "shared_access_owner_update"
on public.shared_access
for update
using (public.is_active_trip_owner(trip_id))
with check (public.is_active_trip_owner(trip_id));

drop policy if exists "shared_access_owner_delete" on public.shared_access;
create policy "shared_access_owner_delete"
on public.shared_access
for delete
using (public.is_active_trip_owner(trip_id) or user_id = auth.uid());

create or replace function public.prevent_archived_trip_membership_changes()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_trip_id uuid;
  trip_is_archived boolean;
begin
  if tg_op = 'DELETE' then
    target_trip_id := old.trip_id;
  else
    target_trip_id := new.trip_id;
  end if;

  select is_archived
    into trip_is_archived
    from public.trips
   where id = target_trip_id;

  if trip_is_archived then
    if tg_op = 'DELETE' and old.user_id = auth.uid() then
      return old;
    end if;

    raise exception 'Archived trips cannot change membership.'
      using errcode = '42501';
  end if;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_archived_trip_membership_changes on public.shared_access;
create trigger prevent_archived_trip_membership_changes
before insert or update or delete on public.shared_access
for each row
execute function public.prevent_archived_trip_membership_changes();
