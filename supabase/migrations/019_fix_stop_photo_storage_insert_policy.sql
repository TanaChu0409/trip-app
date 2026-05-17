-- 019_fix_stop_photo_storage_insert_policy.sql
-- Removes the legacy ownership check from stop photo storage uploads.

drop policy if exists "stop_photos_storage_insert" on storage.objects;

create policy "stop_photos_storage_insert"
on storage.objects
for insert
with check (
  bucket_id = 'stop-photos'
  and auth.role() = 'authenticated'
  and split_part(name, '/', 1) = auth.uid()::text
  and public.can_edit_stop(public.storage_stop_id(name))
);
