-- Enable Supabase Realtime for BazaarMV buyer-seller messages.
-- Run this once in the Supabase SQL Editor.
-- The messages table already has row-level security policies restricting access.

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'bazaar_messages'
  ) then
    alter publication supabase_realtime add table public.bazaar_messages;
  end if;
end
$$;
