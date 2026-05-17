-- 020_fix_stop_photo_owner_edit_access.sql
-- Allows trip owners and shared editors to edit stop photos consistently.

create or replace function public.can_edit_stop(p_stop_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select
    public.is_stop_trip_owner(p_stop_id)
    or exists (
      select 1
      from public.stops
      join public.days on days.id = stops.day_id
      where stops.id = p_stop_id
        and public.is_trip_editor(days.trip_id)
    );
$$;
