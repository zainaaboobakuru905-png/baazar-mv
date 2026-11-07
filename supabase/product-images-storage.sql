-- BazaarMV product photo storage setup
-- Run this once in Supabase SQL Editor after merging the website changes.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'product-images',
  'product-images',
  true,
  5242880,
  array['image/jpeg','image/png','image/webp','image/gif']
)
on conflict (id) do update
set public = true,
    file_size_limit = 5242880,
    allowed_mime_types = array['image/jpeg','image/png','image/webp','image/gif'];

drop policy if exists "Public can view BazaarMV product photos" on storage.objects;
create policy "Public can view BazaarMV product photos"
on storage.objects for select
to public
using (bucket_id = 'product-images');

drop policy if exists "Sellers can upload their own product photos" on storage.objects;
create policy "Sellers can upload their own product photos"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'product-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Sellers can update their own product photos" on storage.objects;
create policy "Sellers can update their own product photos"
on storage.objects for update
to authenticated
using (
  bucket_id = 'product-images'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'product-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Sellers can delete their own product photos" on storage.objects;
create policy "Sellers can delete their own product photos"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'product-images'
  and (storage.foldername(name))[1] = auth.uid()::text
);
