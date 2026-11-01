-- Run with the repository Supabase database test suite.
-- Isolated fixtures and all writes are rolled back, including on assertion failure.
begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(1);
insert into auth.users (id, email) values
 ('91000000-0000-0000-0000-000000000001', 'colors-owner@example.test'),
 ('91000000-0000-0000-0000-000000000002', 'colors-editor@example.test'),
 ('91000000-0000-0000-0000-000000000003', 'colors-viewer@example.test');
insert into public.trips (id, title, start_date, end_date, owner_id, color) values
 ('92000000-0000-0000-0000-000000000001', 'Colors one', current_date, current_date, '91000000-0000-0000-0000-000000000001', '#123456'),
 ('92000000-0000-0000-0000-000000000002', 'Colors two', current_date, current_date, '91000000-0000-0000-0000-000000000001', '#123456');
insert into public.days (id, trip_id, date, label) values
 ('93000000-0000-0000-0000-000000000001', '92000000-0000-0000-0000-000000000001', current_date, 'One');
insert into public.shared_access (trip_id, user_id, permission) values
 ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000002', 'editor'),
 ('92000000-0000-0000-0000-000000000001', '91000000-0000-0000-0000-000000000003', 'viewer');

set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
do $$
declare t uuid := '92000000-0000-0000-0000-000000000001';
  other uuid := '92000000-0000-0000-0000-000000000002';
  day uuid := '93000000-0000-0000-0000-000000000001';
  saved public.stops; bad jsonb; before_names jsonb;
begin
  insert into public.trips (title, start_date, end_date, owner_id, custom_color_names)
  values ('New named trip', current_date, current_date, auth.uid(), '{"#123456":"  新旅程  "}');
  assert exists (select 1 from public.trips where title = 'New named trip'
    and custom_color_names->>'#123456' = '新旅程'), 'new trip inserts normalize names';
  begin
    insert into public.trips (title, start_date, end_date, owner_id, custom_color_names)
    values ('Invalid new trip', current_date, current_date, auth.uid(), '{"#123456":"  "}');
    raise exception 'invalid new trip accepted';
  exception when sqlstate '22023' then null;
  end;
  assert not exists (select 1 from public.trips where title = 'Invalid new trip'), 'new trip validation is atomic';
  assert (select custom_color_names = '{}'::jsonb from public.trips where id = t), 'legacy map defaults empty';
  perform public.update_trip_color_with_names(t, '#123456', '{"#123456":"  海洋藍  "}');
  assert (select custom_color_names->>'#123456' = '海洋藍' from public.trips where id = t), 'names trimmed';
  perform public.update_trip_color_with_names(other, '#123456', '{"#123456":"另一趟"}');
  select * into saved from public.create_stop_with_color_names(day,
    '{"title":"original","color":"#123456"}', '{"#123456":"深海藍"}');
  assert saved.color = '#123456', 'stop and trip use same identity';
  assert (select custom_color_names->>'#123456' = '深海藍' from public.trips where id = t), 'stop rename updates shared metadata';
  assert (select custom_color_names->>'#123456' = '另一趟' from public.trips where id = other), 'trips isolated';
  perform public.update_stop_with_color_names(saved.id,
    '{"title":"updated","color":"#123456"}', '{"#ABCDEF":"深海藍"}');
  assert (select custom_color_names ? '#123456' and custom_color_names ? '#ABCDEF' from public.trips where id = t), 'merge preserves unrelated entries and duplicate labels';
  select custom_color_names into before_names from public.trips where id = t;
  foreach bad in array array[
    'null'::jsonb, '[]'::jsonb, '{"#123456":null}'::jsonb,
    '{"#123456":"   "}'::jsonb, jsonb_build_object('#123456', repeat('長',21)),
    '{"#abcdef":"lowercase"}'::jsonb, '{"bad":"invalid hex"}'::jsonb,
    '{"#003D79":"preset"}'::jsonb
  ] loop
    begin
      perform public.update_stop_with_color_names(saved.id, '{"title":"must rollback","color":"#654321"}', bad);
      raise exception 'invalid names accepted: %', bad;
    exception when sqlstate '22023' then null;
    end;
    assert (select title = 'updated' and color = '#123456' from public.stops where id = saved.id), 'invalid name rolls back stop';
    assert (select custom_color_names = before_names from public.trips where id = t), 'invalid name leaves map unchanged';
  end loop;
  begin
    perform public.create_stop_with_color_names(day, '{"time":"invalid time","color":"#987654"}', '{"#987654":"must rollback"}');
    raise exception 'invalid stop accepted';
  exception when invalid_datetime_format then null;
  end;
  assert (select custom_color_names = before_names from public.trips where id = t), 'stop failure rolls back name merge';
  begin
    perform public.update_trip_color_with_names(t, 'bad', '{"#987654":"must rollback"}');
    raise exception 'invalid color accepted';
  exception when sqlstate '22023' then null;
  end;
  assert (select custom_color_names = before_names and color = '#123456' from public.trips where id = t), 'trip color failure rolls back name merge';
  perform public.remove_trip_custom_stop_color(t, '#123456');
  assert (select custom_color_names->>'#123456' = '深海藍' from public.trips where id = t), 'removing palette keeps name';
  assert not has_function_privilege('anon', 'public.update_trip_color_with_names(uuid,text,jsonb)', 'execute'), 'anon denied';
  assert not has_function_privilege('authenticated', 'public.merge_trip_color_names(uuid,jsonb)', 'execute'), 'internal helper private';
end;
$$;

select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000002', true);
select public.update_trip_color_with_names('92000000-0000-0000-0000-000000000001', '#123456', '{"#123456":"編輯者命名"}');
select public.create_stop_with_color_names('93000000-0000-0000-0000-000000000001', '{"title":"editor","color":"#123456"}', '{}');
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000003', true);
do $$
begin
  begin
    perform public.update_trip_color_with_names('92000000-0000-0000-0000-000000000001', '#123456', '{"#123456":"denied"}');
    raise exception 'viewer allowed';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.create_stop_with_color_names('93000000-0000-0000-0000-000000000001', '{"title":"denied"}', '{}');
    raise exception 'viewer created stop';
  exception when insufficient_privilege then null;
  end;
end;
$$;
reset role;
update public.trips set is_archived = true where id = '92000000-0000-0000-0000-000000000001';
set local role authenticated;
select set_config('request.jwt.claim.sub', '91000000-0000-0000-0000-000000000001', true);
do $$
begin
  begin
    perform public.update_trip_color_with_names('92000000-0000-0000-0000-000000000001', '#123456', '{}');
    raise exception 'archived trip changed';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.create_stop_with_color_names('93000000-0000-0000-0000-000000000001', '{"title":"denied"}', '{}');
    raise exception 'archived stop created';
  exception when insufficient_privilege then null;
  end;
end;
$$;
select extensions.pass('custom colour name permissions, validation, merge and atomicity');
select * from extensions.finish();
rollback;
