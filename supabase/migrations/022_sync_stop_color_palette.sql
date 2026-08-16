-- Keep trip palettes current while older clients still write stops directly.
create or replace function public.sync_trip_custom_stop_color()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  trip_id uuid;
  normalized_color text := upper(trim(coalesce(new.color, '')));
begin
  if tg_op = 'UPDATE' and new.color is not distinct from old.color then
    return new;
  end if;

  -- Invalid values remain compatible with the legacy direct-write path, but
  -- are not eligible to become reusable palette colours.
  if normalized_color = '' or normalized_color !~ '^#[0-9A-F]{6}$' then
    return new;
  end if;

  select trip_id into trip_id
  from public.days
  where id = new.day_id;

  if trip_id is not null then
    perform public.add_custom_stop_color(trip_id, normalized_color);
  end if;

  return new;
end;
$$;

drop trigger if exists stops_sync_custom_color_palette on public.stops;
create trigger stops_sync_custom_color_palette
after insert or update of color on public.stops
for each row execute function public.sync_trip_custom_stop_color();

revoke all on function public.sync_trip_custom_stop_color() from public;
