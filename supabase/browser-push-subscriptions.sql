-- BazaarMV browser push notification subscriptions
-- Run this once in the Supabase SQL Editor.

create table if not exists public.bazaar_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.bazaar_push_subscriptions enable row level security;

drop policy if exists "Users can view their own push subscriptions"
  on public.bazaar_push_subscriptions;
create policy "Users can view their own push subscriptions"
  on public.bazaar_push_subscriptions
  for select to authenticated
  using (auth.uid() = user_id);

drop policy if exists "Users can add their own push subscriptions"
  on public.bazaar_push_subscriptions;
create policy "Users can add their own push subscriptions"
  on public.bazaar_push_subscriptions
  for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "Users can update their own push subscriptions"
  on public.bazaar_push_subscriptions;
create policy "Users can update their own push subscriptions"
  on public.bazaar_push_subscriptions
  for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "Users can delete their own push subscriptions"
  on public.bazaar_push_subscriptions;
create policy "Users can delete their own push subscriptions"
  on public.bazaar_push_subscriptions
  for delete to authenticated
  using (auth.uid() = user_id);

create index if not exists bazaar_push_subscriptions_user_id_idx
  on public.bazaar_push_subscriptions(user_id);
