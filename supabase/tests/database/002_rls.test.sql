begin;

create extension if not exists pgtap with schema extensions;
select extensions.no_plan();

-- Stable fixture identities.
insert into auth.users (id, email)
values
  ('10000000-0000-0000-0000-000000000001', 'owner@example.test'),
  ('10000000-0000-0000-0000-000000000002', 'editor@example.test'),
  ('10000000-0000-0000-0000-000000000003', 'reader@example.test'),
  ('10000000-0000-0000-0000-000000000004', 'stranger@example.test');

insert into public.trips (
  id, title, start_date, end_date, owner_id, share_code, color
)
values (
  '20000000-0000-0000-0000-000000000001',
  'ACL test trip',
  current_date,
  current_date + 1,
  '10000000-0000-0000-0000-000000000001',
  'ACLTEST1',
  '#003D79'
);

insert into public.days (id, trip_id, date, label, sort_order)
values (
  '30000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  current_date,
  'Original day',
  0
);

insert into public.shared_access (trip_id, user_id, permission)
values
  (
    '20000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000002',
    'editor'
  ),
  (
    '20000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000003',
    'viewer'
  );

-- Owner: may read and add content to an active trip, but cannot update a trip
-- row directly because colour/archive mutations must use RPCs.
set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000001',
  true
);

select extensions.is(
  (select count(*)::integer from public.trips),
  1,
  'owner can read their trip'
);

select extensions.lives_ok(
  $$
    insert into public.days (trip_id, date, label, sort_order)
    values (
      '20000000-0000-0000-0000-000000000001',
      current_date + 1,
      'Owner-created day',
      1
    )
  $$,
  'owner can add content to an active trip'
);

select extensions.throws_ok(
  $$
    update public.trips
       set title = 'Direct update must fail'
     where id = '20000000-0000-0000-0000-000000000001'
  $$,
  '42501'
);

select extensions.lives_ok(
  $$
    update public.profiles
       set display_name = 'Trip owner'
     where id = '10000000-0000-0000-0000-000000000001'
    returning id, display_name
  $$,
  'profile owner can update an allowed field and return readable columns'
);

select extensions.throws_ok(
  $$
    select email
      from public.profiles
     where id = '10000000-0000-0000-0000-000000000001'
  $$,
  '42501'
);

select extensions.throws_ok(
  $$
    update public.profiles
       set email = 'new-owner@example.test'
     where id = '10000000-0000-0000-0000-000000000001'
    returning email
  $$,
  '42501'
);

select extensions.throws_ok(
  $$select count(*) from public.join_code_attempts$$,
  '42501'
);
select extensions.throws_ok(
  $$select count(*) from public.invite_member_attempts$$,
  '42501'
);

-- Editor: may mutate child content while the trip is active.
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000002',
  true
);

select extensions.lives_ok(
  $$
    update public.days
       set label = 'Editor update'
     where id = '30000000-0000-0000-0000-000000000001'
  $$,
  'editor can update active trip content'
);

select extensions.is(
  (
    select label
    from public.days
    where id = '30000000-0000-0000-0000-000000000001'
  ),
  'Editor update',
  'editor update is visible'
);

select extensions.is(
  (
    select count(*)::integer
    from public.profiles_public
    where id = '10000000-0000-0000-0000-000000000003'
  ),
  1,
  'editor can read a shared-trip peer through profiles_public'
);

-- Reader: can read but an UPDATE silently affects no rows under RLS.
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000003',
  true
);

update public.days
set label = 'Reader must not update'
where id = '30000000-0000-0000-0000-000000000001';

select extensions.is(
  (
    select label
    from public.days
    where id = '30000000-0000-0000-0000-000000000001'
  ),
  'Editor update',
  'reader cannot update trip content'
);

select extensions.throws_ok(
  $$
    insert into public.days (trip_id, date, label, sort_order)
    values (
      '20000000-0000-0000-0000-000000000001',
      current_date,
      'Reader insert must fail',
      99
    )
  $$,
  '42501'
);

-- Stranger: RLS hides all trip rows.
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000004',
  true
);

select extensions.is(
  (select count(*)::integer from public.trips),
  0,
  'stranger cannot read the trip'
);

select extensions.is(
  public.set_owned_trip_archived(
    '20000000-0000-0000-0000-000000000001',
    true
  ),
  false,
  'stranger cannot archive another user trip'
);

-- Archive through the owner-only RPC, then confirm owner and editor writes are
-- blocked while reads remain available.
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000001',
  true
);

select extensions.is(
  public.set_owned_trip_archived(
    '20000000-0000-0000-0000-000000000001',
    true
  ),
  true,
  'owner can archive their trip through the RPC'
);

update public.days
set label = 'Archived owner update must not apply'
where id = '30000000-0000-0000-0000-000000000001';

select extensions.is(
  (
    select label
    from public.days
    where id = '30000000-0000-0000-0000-000000000001'
  ),
  'Editor update',
  'owner cannot update content while the trip is archived'
);

select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-0000-0000-000000000002',
  true
);

update public.days
set label = 'Archived editor update must not apply'
where id = '30000000-0000-0000-0000-000000000001';

select extensions.is(
  (
    select label
    from public.days
    where id = '30000000-0000-0000-0000-000000000001'
  ),
  'Editor update',
  'editor cannot update content while the trip is archived'
);

select extensions.throws_ok(
  $$
    select public.update_trip_color(
      '20000000-0000-0000-0000-000000000001',
      '#FFFFFF'
    )
  $$,
  '42501'
);

reset role;
select * from extensions.finish();
rollback;
