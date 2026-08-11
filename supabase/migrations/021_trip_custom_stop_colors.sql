-- Shared, per-trip custom colours for itinerary stops.
alter table public.trips
  add column if not exists custom_stop_colors jsonb not null default '[]'::jsonb;

-- Preserve the first occurrence order of colours already used by stops.
with colors as (
  select d.trip_id, upper(s.color) as color, min(s.created_at) as first_used_at
  from public.stops s
  join public.days d on d.id = s.day_id
  where s.color ~ '^#[0-9A-Fa-f]{6}$'
    and upper(s.color) not in ('#003D79', '#F97316', '#E11D48', '#15803D', '#0F766E', '#7C3AED', '#DB2777', '#92400E')
  group by d.trip_id, upper(s.color)
)
update public.trips t
set custom_stop_colors = coalesce((
  select jsonb_agg(upper(color) order by first_used_at)
  from colors c where c.trip_id = t.id
), '[]'::jsonb)
where t.custom_stop_colors = '[]'::jsonb;

create or replace function public.can_edit_trip(p_trip_id uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select public.is_trip_owner(p_trip_id) or public.is_trip_editor(p_trip_id);
$$;

create or replace function public.add_custom_stop_color(p_trip_id uuid, p_color text)
returns void language plpgsql security definer set search_path = public as $$
declare normalized text := upper(trim(coalesce(p_color, '')));
begin
  if not public.can_edit_trip(p_trip_id) then raise exception 'Permission denied' using errcode = '42501'; end if;
  if normalized = '' then return; end if;
  if normalized !~ '^#[0-9A-F]{6}$' then raise exception 'Invalid colour' using errcode = '22023'; end if;
  if normalized in ('#003D79', '#F97316', '#E11D48', '#15803D', '#0F766E', '#7C3AED', '#DB2777', '#92400E') then return; end if;
  update public.trips set custom_stop_colors = case
    when custom_stop_colors @> jsonb_build_array(normalized) then custom_stop_colors
    else custom_stop_colors || jsonb_build_array(normalized) end
  where id = p_trip_id;
end;
$$;

create or replace function public.remove_trip_custom_stop_color(p_trip_id uuid, p_color text)
returns void language plpgsql security definer set search_path = public as $$
declare normalized text := upper(trim(coalesce(p_color, '')));
begin
  if not public.can_edit_trip(p_trip_id) then raise exception 'Permission denied' using errcode = '42501'; end if;
  update public.trips set custom_stop_colors = coalesce((
    select jsonb_agg(value) from jsonb_array_elements_text(custom_stop_colors) value where value <> normalized
  ), '[]'::jsonb) where id = p_trip_id;
end;
$$;

create or replace function public.create_stop_with_palette(p_day_id uuid, p_stop jsonb)
returns public.stops language plpgsql security definer set search_path = public as $$
declare saved public.stops; trip uuid;
begin
  select trip_id into trip from public.days where id = p_day_id;
  if trip is null or not public.can_edit_trip(trip) then raise exception 'Permission denied' using errcode = '42501'; end if;
  insert into public.stops (day_id, time, title, note, badge, map_url, color, is_highlight, sort_order)
  values (p_day_id, nullif(p_stop->>'time','')::time, coalesce(p_stop->>'title',''), p_stop->>'note', p_stop->>'badge', p_stop->>'map_url', upper(nullif(p_stop->>'color','')), coalesce((p_stop->>'is_highlight')::boolean, false), coalesce((p_stop->>'sort_order')::integer, 0)) returning * into saved;
  perform public.add_custom_stop_color(trip, saved.color); return saved;
end;
$$;

create or replace function public.update_stop_with_palette(p_stop_id uuid, p_stop jsonb)
returns public.stops language plpgsql security definer set search_path = public as $$
declare saved public.stops; trip uuid; previous_color text;
begin
  select d.trip_id, s.color into trip, previous_color
  from public.stops s join public.days d on d.id = s.day_id
  where s.id = p_stop_id;
  if trip is null or not public.can_edit_trip(trip) then raise exception 'Permission denied' using errcode = '42501'; end if;
  update public.stops set time = nullif(p_stop->>'time','')::time, title = coalesce(p_stop->>'title',''), note = p_stop->>'note', badge = p_stop->>'badge', map_url = p_stop->>'map_url', color = upper(nullif(p_stop->>'color','')), is_highlight = coalesce((p_stop->>'is_highlight')::boolean, false), sort_order = coalesce((p_stop->>'sort_order')::integer, 0) where id = p_stop_id returning * into saved;
  if saved.color is distinct from previous_color then
    perform public.add_custom_stop_color(trip, saved.color);
  end if;
  return saved;
end;
$$;

revoke all on function public.can_edit_trip(uuid) from public;
revoke all on function public.add_custom_stop_color(uuid, text) from public;
revoke all on function public.remove_trip_custom_stop_color(uuid, text) from public;
revoke all on function public.create_stop_with_palette(uuid, jsonb) from public;
revoke all on function public.update_stop_with_palette(uuid, jsonb) from public;
grant execute on function public.remove_trip_custom_stop_color(uuid, text), public.create_stop_with_palette(uuid, jsonb), public.update_stop_with_palette(uuid, jsonb) to authenticated;
