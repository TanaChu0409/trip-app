-- Keep colour identities backwards compatible; names are per-trip metadata.
alter table public.trips
  add column custom_color_names jsonb not null default '{}'::jsonb;

-- Validate direct inserts as well as RPC writes. Legacy empty maps remain valid.
create function public.validate_custom_color_names()
returns trigger language plpgsql security invoker set search_path = public as $$
declare item record; normalized jsonb := '{}'::jsonb; label text;
begin
  if jsonb_typeof(new.custom_color_names) is distinct from 'object' then
    raise exception 'Invalid colour names' using errcode = '22023';
  end if;
  for item in select key, value from jsonb_each(new.custom_color_names) loop
    if item.key !~ '^#[0-9A-F]{6}$'
      or item.key in ('#003D79', '#F97316', '#E11D48', '#15803D', '#0F766E', '#7C3AED', '#DB2777', '#92400E')
      or jsonb_typeof(item.value) <> 'string' then
      raise exception 'Invalid colour name entry' using errcode = '22023';
    end if;
    label := regexp_replace(item.value #>> '{}', '^\s+|\s+$', '', 'g');
    if char_length(label) not between 1 and 20 then
      raise exception 'Colour name must contain 1 to 20 characters' using errcode = '22023';
    end if;
    normalized := normalized || jsonb_build_object(item.key, label);
  end loop;
  new.custom_color_names := normalized;
  return new;
end;
$$;
create trigger trips_validate_custom_color_names
before insert or update of custom_color_names on public.trips
for each row execute function public.validate_custom_color_names();

-- Internal merge: lock the trip before checking permissions, and update only
-- keys supplied by this form so unrelated concurrent edits are preserved.
create function public.merge_trip_color_names(p_trip_id uuid, p_color_names jsonb)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform 1 from public.trips where id = p_trip_id for update;
  if not public.can_edit_trip(p_trip_id) then
    raise exception 'Permission denied' using errcode = '42501';
  end if;
  if jsonb_typeof(p_color_names) is distinct from 'object' then
    raise exception 'Invalid colour names' using errcode = '22023';
  end if;
  if p_color_names <> '{}'::jsonb then
    update public.trips
      set custom_color_names = custom_color_names || p_color_names
      where id = p_trip_id;
  end if;
end;
$$;

create function public.update_trip_color_with_names(
  p_trip_id uuid, p_color text, p_color_names jsonb default '{}'::jsonb
)
returns void language plpgsql security definer set search_path = public as $$
begin
  perform public.merge_trip_color_names(p_trip_id, p_color_names);
  if p_color is not null and upper(p_color) !~ '^#[0-9A-F]{6}$' then
    raise exception 'Invalid colour' using errcode = '22023';
  end if;
  perform public.update_trip_color(p_trip_id, upper(p_color));
end;
$$;

create function public.create_stop_with_color_names(
  p_day_id uuid, p_stop jsonb, p_color_names jsonb default '{}'::jsonb
)
returns public.stops language plpgsql security definer set search_path = public as $$
declare trip uuid; saved public.stops;
begin
  select trip_id into trip from public.days where id = p_day_id;
  perform public.merge_trip_color_names(trip, p_color_names);
  select * into saved from public.create_stop_with_palette(p_day_id, p_stop);
  return saved;
end;
$$;

create function public.update_stop_with_color_names(
  p_stop_id uuid, p_stop jsonb, p_color_names jsonb default '{}'::jsonb
)
returns public.stops language plpgsql security definer set search_path = public as $$
declare trip uuid; saved public.stops;
begin
  select d.trip_id into trip from public.stops s
    join public.days d on d.id = s.day_id where s.id = p_stop_id;
  perform public.merge_trip_color_names(trip, p_color_names);
  select * into saved from public.update_stop_with_palette(p_stop_id, p_stop);
  return saved;
end;
$$;

revoke all on function public.validate_custom_color_names() from public, anon, authenticated, service_role;
revoke all on function public.merge_trip_color_names(uuid, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.update_trip_color_with_names(uuid, text, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.create_stop_with_color_names(uuid, jsonb, jsonb) from public, anon, authenticated, service_role;
revoke all on function public.update_stop_with_color_names(uuid, jsonb, jsonb) from public, anon, authenticated, service_role;
grant execute on function
  public.update_trip_color_with_names(uuid, text, jsonb),
  public.create_stop_with_color_names(uuid, jsonb, jsonb),
  public.update_stop_with_color_names(uuid, jsonb, jsonb)
to authenticated, service_role;
