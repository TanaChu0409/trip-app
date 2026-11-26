-- Update only editable metadata; never grant general trips UPDATE access.
create or replace function public.update_trip_details(
  p_trip_id uuid, p_title text, p_start_date date, p_end_date date,
  p_color text, p_color_names jsonb default '{}'::jsonb
)
returns void language plpgsql security definer set search_path = public as $$
declare
  previous public.trips;
  day_ids uuid[];
  blocked text;
  wanted integer;
  total integer;
begin
  select * into previous from public.trips where id = p_trip_id for update;
  if auth.uid() is null or not public.can_edit_trip(p_trip_id) then
    raise exception 'Permission denied' using errcode = '42501';
  end if;
  if p_title is null or btrim(p_title) = '' or p_start_date is null
    or p_end_date is null or p_end_date < p_start_date then
    raise exception 'Invalid trip details' using errcode = '22023';
  end if;
  if p_color is not null and upper(p_color) !~ '^#[0-9A-F]{6}$' then
    raise exception 'Invalid colour' using errcode = '22023';
  end if;
  if p_start_date <> previous.start_date or p_end_date <> previous.end_date then
    -- FOR UPDATE conflicts with FK checks when a concurrent writer adds a stop.
    -- Lock before checking for content so a day can never be silently cascaded.
    perform 1 from public.days where trip_id = p_trip_id order by sort_order, date, id for update;
    select array_agg(id order by sort_order, date, id) into day_ids
      from public.days where trip_id = p_trip_id;
    total := coalesce(cardinality(day_ids), 0);
    wanted := p_end_date - p_start_date + 1;
    select string_agg(n::text, ', ' order by n) into blocked
      from generate_series(wanted + 1, total) n
      where exists (select 1 from public.stops where day_id = day_ids[n]);
    if blocked is not null then
      raise exception 'trip_days_have_stops' using errcode = '22023', detail = blocked;
    end if;
    if total > wanted then
      delete from public.days where id = any(day_ids[wanted + 1:total]);
    end if;
    for i in 1..least(total, wanted) loop
      update public.days set date = p_start_date + i - 1, sort_order = i - 1
        where id = day_ids[i];
    end loop;
    if wanted > total then
      for i in total + 1..wanted loop
        insert into public.days (trip_id, date, label, subtitle, sort_order)
        values (p_trip_id, p_start_date + i - 1,
          '第' || case when i <= 10 then
            (array['一','二','三','四','五','六','七','八','九','十'])[i]
            else i::text end || '天',
          case when i = 1 then '從這一天開始安排行程。' else '這一天的詳細行程尚未建立。' end,
          i - 1);
      end loop;
    end if;
  end if;
  perform public.merge_trip_color_names(p_trip_id, p_color_names);
  update public.trips set title = btrim(p_title), color = upper(p_color),
    start_date = p_start_date, end_date = p_end_date where id = p_trip_id;
end;
$$;
revoke all on function public.update_trip_details(uuid, text, date, date, text, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.update_trip_details(uuid, text, date, date, text, jsonb)
  to authenticated;


