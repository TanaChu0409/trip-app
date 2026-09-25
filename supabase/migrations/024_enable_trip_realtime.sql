-- Publish trip updates so archive/restore state reaches all open clients.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'trips'
  ) then
    execute 'alter publication supabase_realtime add table public.trips';
  end if;
end $$;
