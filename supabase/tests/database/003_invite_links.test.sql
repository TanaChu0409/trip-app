begin;
create extension if not exists pgtap with schema extensions;
select extensions.no_plan();
insert into auth.users (id,email) values
 ('40000000-0000-0000-0000-000000000001','link-owner@example.test'),
 ('40000000-0000-0000-0000-000000000002','link-guest@example.test'),
 ('40000000-0000-0000-0000-000000000003','link-other@example.test');
insert into public.trips(id,title,start_date,end_date,owner_id) values
 ('50000000-0000-0000-0000-000000000001','Link trip',current_date,current_date,
 '40000000-0000-0000-0000-000000000001');
create temp table link_tokens (label text primary key, token text);
grant all on link_tokens to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','40000000-0000-0000-0000-000000000001',true);
select extensions.is(public.create_trip_invite_link('50000000-0000-0000-0000-000000000001','admin')->>'status',
 'invalid_permission','invalid permission rejected');
insert into link_tokens values ('old', public.create_trip_invite_link('50000000-0000-0000-0000-000000000001','viewer')->>'token');
select extensions.ok((select token ~ '^[0-9a-f]{64}$' from link_tokens where label='old'),'256-bit token');
select extensions.is(public.get_trip_invite_link('50000000-0000-0000-0000-000000000001')->>'active','true','owner can see status');
select extensions.is(public.preview_trip_invite_link((select token from link_tokens where label='old'))->>'status','owner','self invite recognized');
select extensions.throws_ok($$select * from public.trip_invite_links$$,'42501');
select set_config('request.jwt.claim.sub','40000000-0000-0000-0000-000000000002',true);
select extensions.is(public.get_trip_invite_link('50000000-0000-0000-0000-000000000001')->>'status','not_owner','non-owner cannot manage');
select extensions.is(public.create_trip_invite_link('50000000-0000-0000-0000-000000000001','editor')->>'status','not_owner','non-owner cannot reset');
select extensions.is(public.revoke_trip_invite_link('50000000-0000-0000-0000-000000000001')->>'status','not_owner','non-owner cannot revoke');
select extensions.is(public.preview_trip_invite_link((select token from link_tokens where label='old'))->>'title','Link trip','valid preview exposes only summary');
select extensions.is((select count(*)::integer from public.shared_access),0,'preview does not join');
select extensions.is(public.accept_trip_invite_link((select token from link_tokens where label='old'))->>'status','success','guest accepts');
select extensions.is(public.accept_trip_invite_link((select token from link_tokens where label='old'))->>'status','already_member','repeat is idempotent');
select extensions.is(public.preview_trip_invite_link('bad')::text,'{"status": "invalid_link"}','invalid token leaks no trip');
select extensions.throws_ok($$select public.join_trip_by_code('OLD')$$,'42501');
select extensions.throws_ok($$insert into public.shared_access(trip_id,user_id,permission) values
 ('50000000-0000-0000-0000-000000000001','40000000-0000-0000-0000-000000000003','editor')$$,'42501');
select set_config('request.jwt.claim.sub','40000000-0000-0000-0000-000000000001',true);
insert into link_tokens values ('new',public.create_trip_invite_link('50000000-0000-0000-0000-000000000001','editor')->>'token');
select extensions.is(public.preview_trip_invite_link((select token from link_tokens where label='old'))->>'status','invalid_link','reset invalidates old link');
select set_config('request.jwt.claim.sub','40000000-0000-0000-0000-000000000002',true);
select extensions.is(public.accept_trip_invite_link((select token from link_tokens where label='new'))->>'permission','viewer','existing permission never upgraded');
select set_config('request.jwt.claim.sub','40000000-0000-0000-0000-000000000003',true);
select extensions.is(public.accept_trip_invite_link((select token from link_tokens where label='new'))->>'permission','editor','same link invites multiple members');
select set_config('request.jwt.claim.sub','40000000-0000-0000-0000-000000000001',true);
select public.revoke_trip_invite_link('50000000-0000-0000-0000-000000000001');
select extensions.is(public.preview_trip_invite_link((select token from link_tokens where label='new'))->>'status','invalid_link','revoke invalidates token');
insert into link_tokens values ('archive',public.create_trip_invite_link('50000000-0000-0000-0000-000000000001','viewer')->>'token');
select public.set_owned_trip_archived('50000000-0000-0000-0000-000000000001',true);
select extensions.is(public.create_trip_invite_link('50000000-0000-0000-0000-000000000001','viewer')->>'status','trip_archived','archived cannot create');
select public.set_owned_trip_archived('50000000-0000-0000-0000-000000000001',false);
select extensions.is(public.preview_trip_invite_link((select token from link_tokens where label='archive'))->>'status','invalid_link','restore does not revive token');
reset role;
select extensions.is((select count(*)::integer from public.trip_invite_links),1,'one link row per trip');
select extensions.ok((select token_hash not in (select token from link_tokens) from public.trip_invite_links),'only hash stored');
set local role anon;
select extensions.throws_ok($$select public.preview_trip_invite_link('bad')$$,'42501');
reset role;
select * from extensions.finish();
rollback;
