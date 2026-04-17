-- Add foreign key from shared_access.user_id to profiles.id so that
-- PostgREST can resolve the profiles(...) join in the fetchTripMembers query.
-- Migration 008 already backfilled all existing users into profiles, so
-- this constraint is safe to add.

alter table public.shared_access
  add constraint shared_access_user_id_fkey
  foreign key (user_id)
  references public.profiles(id)
  on delete cascade;
