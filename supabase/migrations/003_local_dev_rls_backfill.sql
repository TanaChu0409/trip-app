do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'days'
      and policyname = 'days_owner_all'
  ) then
    execute $policy$
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
      )
    $policy$;
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'days'
      and policyname = 'days_shared_read'
  ) then
    execute $policy$
      create policy "days_shared_read"
      on public.days
      for select
      using (
        exists (
          select 1
          from public.shared_access
          where shared_access.trip_id = days.trip_id and shared_access.user_id = auth.uid()
        )
      )
    $policy$;
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'stops'
      and policyname = 'stops_owner_all'
  ) then
    execute $policy$
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
      )
    $policy$;
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'stops'
      and policyname = 'stops_shared_read'
  ) then
    execute $policy$
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
      )
    $policy$;
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'parking_spots'
      and policyname = 'parking_spots_owner_all'
  ) then
    execute $policy$
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
      )
    $policy$;
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'parking_spots'
      and policyname = 'parking_spots_shared_read'
  ) then
    execute $policy$
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
      )
    $policy$;
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'shared_access'
      and policyname = 'shared_access_owner_read'
  ) then
    execute $policy$
      create policy "shared_access_owner_read"
      on public.shared_access
      for select
      using (
        exists (
          select 1
          from public.trips
          where trips.id = shared_access.trip_id and trips.owner_id = auth.uid()
        )
      )
    $policy$;
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'shared_access'
      and policyname = 'shared_access_owner_delete'
  ) then
    execute $policy$
      create policy "shared_access_owner_delete"
      on public.shared_access
      for delete
      using (
        exists (
          select 1
          from public.trips
          where trips.id = shared_access.trip_id and trips.owner_id = auth.uid()
        )
      )
    $policy$;
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'shared_access'
      and policyname = 'shared_access_delete_self'
  ) then
    execute $policy$
      create policy "shared_access_delete_self"
      on public.shared_access
      for delete
      using (user_id = auth.uid())
    $policy$;
  end if;
end
$$;