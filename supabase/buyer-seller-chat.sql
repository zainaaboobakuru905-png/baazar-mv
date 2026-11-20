-- BazaarMV buyer-seller chat
-- Run once in Supabase SQL Editor. Messages are private to the buyer and seller.

create table if not exists public.bazaar_messages (
  id uuid primary key default gen_random_uuid(),
  product_id uuid references public.products(id) on delete set null,
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 2000),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  constraint bazaar_messages_distinct_participants check (buyer_id <> seller_id),
  constraint bazaar_messages_sender_is_participant check (sender_id = buyer_id or sender_id = seller_id)
);

create index if not exists bazaar_messages_conversation_idx
  on public.bazaar_messages(buyer_id, seller_id, product_id, created_at);
create index if not exists bazaar_messages_seller_inbox_idx
  on public.bazaar_messages(seller_id, created_at desc);
create index if not exists bazaar_messages_buyer_inbox_idx
  on public.bazaar_messages(buyer_id, created_at desc);

alter table public.bazaar_messages enable row level security;

drop policy if exists "Chat participants read messages" on public.bazaar_messages;
create policy "Chat participants read messages"
on public.bazaar_messages for select to authenticated
using (buyer_id = (select auth.uid()) or seller_id = (select auth.uid()));

drop policy if exists "Participants send chat messages" on public.bazaar_messages;
create policy "Participants send chat messages"
on public.bazaar_messages for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and (buyer_id = (select auth.uid()) or seller_id = (select auth.uid()))
  and exists (
    select 1 from public.seller_profiles s
    where s.user_id = seller_id and s.approval_status = 'approved'
  )
  and (
    product_id is null
    or exists (
      select 1 from public.products p
      where p.id = product_id and p.seller_id = seller_id
    )
  )
);

drop policy if exists "Recipients mark chat messages read" on public.bazaar_messages;
create policy "Recipients mark chat messages read"
on public.bazaar_messages for update to authenticated
using (
  (buyer_id = (select auth.uid()) or seller_id = (select auth.uid()))
  and sender_id <> (select auth.uid())
)
with check (
  (buyer_id = (select auth.uid()) or seller_id = (select auth.uid()))
  and sender_id <> (select auth.uid())
);

revoke all on public.bazaar_messages from anon, public;
grant select, insert on public.bazaar_messages to authenticated;
grant update (read_at) on public.bazaar_messages to authenticated;

-- Notify the other participant when a message is sent.
create or replace function public.bazaar_notify_chat_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  recipient_id uuid;
begin
  recipient_id := case when new.sender_id = new.buyer_id then new.seller_id else new.buyer_id end;
  insert into public.bazaar_notifications(user_id, notification_type, title, message, related_id)
  values (
    recipient_id,
    'chat_message',
    'New chat message',
    'You have a new message in BazaarMV.',
    new.id
  );
  return new;
end;
$$;

drop trigger if exists bazaar_chat_message_notification on public.bazaar_messages;
create trigger bazaar_chat_message_notification
after insert on public.bazaar_messages
for each row execute function public.bazaar_notify_chat_message();

revoke all on function public.bazaar_notify_chat_message() from public, anon, authenticated;
