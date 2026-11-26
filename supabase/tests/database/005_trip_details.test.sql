begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(1);
insert into auth.users (id, email) values
 ('a1000000-0000-0000-0000-000000000001','details-owner@example.test'),
 ('a1000000-0000-0000-0000-000000000002','details-editor@example.test'),
 ('a1000000-0000-0000-0000-000000000003','details-viewer@example.test'),
 ('a1000000-0000-0000-0000-000000000004','details-stranger@example.test');
insert into public.trips(id,title,start_date,end_date,owner_id) values
 ('a2000000-0000-0000-0000-000000000001','Original','2026-01-01','2026-01-02','a1000000-0000-0000-0000-000000000001');
insert into public.days(id,trip_id,date,label,sort_order) values
 ('a3000000-0000-0000-0000-000000000001','a2000000-0000-0000-0000-000000000001','2026-01-01','第一天',0),
 ('a3000000-0000-0000-0000-000000000002','a2000000-0000-0000-0000-000000000001','2026-01-02','第二天',1);
insert into public.stops(id,day_id,title) values
 ('a4000000-0000-0000-0000-000000000001','a3000000-0000-0000-0000-000000000002','Keep me');
insert into public.shared_access(trip_id,user_id,permission) values
 ('a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000002','editor'),
 ('a2000000-0000-0000-0000-000000000001','a1000000-0000-0000-0000-000000000003','viewer');
set local role authenticated;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
do $$
declare t uuid := 'a2000000-0000-0000-0000-000000000001';
begin
  perform public.update_trip_details(t,' Updated ','2026-02-01','2026-02-03','#abcdef','{"#ABCDEF":"新色"}');
  assert (select title = 'Updated' and color = '#ABCDEF' and custom_color_names->>'#ABCDEF' = '新色' from public.trips where id=t), 'metadata updated';
  assert (select date='2026-02-02' from public.days where id='a3000000-0000-0000-0000-000000000002'), 'existing days shifted with same ID';
  assert (select count(*)=3 from public.days where trip_id=t), 'extended';
  begin
    perform public.update_trip_details(t,'must rollback','2026-03-01','2026-03-01',null);
    raise exception 'accepted content removal';
  exception when sqlstate '22023' then
    assert sqlerrm = 'trip_days_have_stops', 'blocked due to content';
  end;
  assert (select title='Updated' and start_date='2026-02-01' from public.trips where id=t), 'failed update atomic';
  perform public.update_trip_details(t,'Shorter','2026-02-01','2026-02-02',null);
  assert (select count(*)=2 from public.days where trip_id=t), 'empty tail removed';
  assert (select color is null from public.trips where id=t), 'color cleared';
  assert exists(select 1 from public.stops where id='a4000000-0000-0000-0000-000000000001'), 'stop preserved';
  begin
    perform public.update_trip_details(t,' ','2026-01-01','2026-01-02',null);
    raise exception 'accepted blank title';
  exception when sqlstate '22023' then null; end;
  begin
    perform public.update_trip_details(t,'Invalid','2026-01-02','2026-01-01',null);
    raise exception 'accepted reversed dates';
  exception when sqlstate '22023' then null; end;
  begin
    perform public.update_trip_details(t,'Invalid','2026-01-01','2026-01-02','bad');
    raise exception 'accepted invalid color';
  exception when sqlstate '22023' then null; end;
  begin
    perform public.update_trip_details(t,'Invalid','2026-01-01','2026-01-04',null,'[]');
    raise exception 'accepted invalid names';
  exception when sqlstate '22023' then null; end;
  assert (select count(*)=2 from public.days where trip_id=t), 'name validation rolls back day extension';
end $$;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000002',true);
select public.update_trip_details('a2000000-0000-0000-0000-000000000001','Editor','2026-02-01','2026-02-02','#123456');
do $$
declare uid text;
begin
  foreach uid in array array['a1000000-0000-0000-0000-000000000003','a1000000-0000-0000-0000-000000000004',''] loop
    perform set_config('request.jwt.claim.sub',uid,true);
    begin
      perform public.update_trip_details('a2000000-0000-0000-0000-000000000001','Denied','2026-02-01','2026-02-02',null);
      raise exception 'unauthorized caller accepted';
    exception when sqlstate '42501' then null; end;
  end loop;
end $$;
select set_config('request.jwt.claim.sub','a1000000-0000-0000-0000-000000000001',true);
select public.set_owned_trip_archived('a2000000-0000-0000-0000-000000000001',true);
do $$
begin
  begin
    perform public.update_trip_details('a2000000-0000-0000-0000-000000000001','Denied','2026-02-01','2026-02-02',null);
    raise exception 'archived trip editable';
  exception when sqlstate '42501' then null; end;
  assert not has_function_privilege('anon','public.update_trip_details(uuid,text,date,date,text,jsonb)','EXECUTE'), 'anonymous denied';
end $$;
select extensions.pass('trip details metadata, date safety, atomicity and permissions');
select * from extensions.finish();
rollback;
