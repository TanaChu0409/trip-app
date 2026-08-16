-- Fix the trigger variable/column ambiguity introduced in migration 022.
create or replace function public.sync_trip_custom_stop_color()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  target_trip_id uuid;
  normalized_color text := upper(trim(coalesce(new.color, '')));
begin
  if tg_op = 'UPDATE' and new.color is not distinct from old.color then
    return new;
  end if;

  if normalized_color = '' or normalized_color !~ '^#[0-9A-F]{6}$' then
    return new;
  end if;

  select days.trip_id
  into target_trip_id
  from public.days
  where days.id = new.day_id;

  if target_trip_id is not null then
    perform public.add_custom_stop_color(target_trip_id, normalized_color);
  end if;

  return new;
end;
$$;

drop trigger if exists stops_sync_custom_color_palette on public.stops;
create trigger stops_sync_custom_color_palette
after insert or update of color on public.stops
for each row execute function public.sync_trip_custom_stop_color();

revoke all on function public.sync_trip_custom_stop_color() from public;
