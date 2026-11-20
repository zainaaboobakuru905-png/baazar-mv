-- BazaarMV in-app notifications
-- Run once in Supabase SQL Editor after the existing marketplace, enquiry,
-- and BML payment SQL have been applied.

create table if not exists public.bazaar_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  notification_type text not null,
  title text not null,
  message text not null,
  related_id uuid,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index if not exists bazaar_notifications_user_created_idx
  on public.bazaar_notifications(user_id, created_at desc);
create index if not exists bazaar_notifications_unread_idx
  on public.bazaar_notifications(user_id, created_at desc)
  where read_at is null;

alter table public.bazaar_notifications enable row level security;

drop policy if exists "Users read own BazaarMV notifications" on public.bazaar_notifications;
create policy "Users read own BazaarMV notifications"
on public.bazaar_notifications for select to authenticated
using (user_id = (select auth.uid()));

drop policy if exists "Users mark own BazaarMV notifications read" on public.bazaar_notifications;
create policy "Users mark own BazaarMV notifications read"
on public.bazaar_notifications for update to authenticated
using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));

revoke all on public.bazaar_notifications from anon, public;
grant select, update on public.bazaar_notifications to authenticated;

-- New order request -> notify the seller.
create or replace function public.bazaar_notify_new_order()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.bazaar_notifications(user_id, notification_type, title, message, related_id)
  values (new.seller_id, 'new_order', 'New order request',
          'You have received a new order request in your shop.', new.id);
  return new;
end;
$$;

drop trigger if exists bazaar_order_notification_insert on public.orders;
create trigger bazaar_order_notification_insert
after insert on public.orders
for each row execute function public.bazaar_notify_new_order();

-- Seller changes order status -> notify the buyer.
create or replace function public.bazaar_notify_order_status()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if new.status is distinct from old.status then
    insert into public.bazaar_notifications(user_id, notification_type, title, message, related_id)
    values (new.buyer_id, 'order_status',
            'Order status updated',
            'Your order status is now ' || new.status || '.', new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists bazaar_order_notification_update on public.orders;
create trigger bazaar_order_notification_update
after update of status on public.orders
for each row execute function public.bazaar_notify_order_status();

-- New buyer enquiry -> notify the seller.
create or replace function public.bazaar_notify_new_enquiry()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.bazaar_notifications(user_id, notification_type, title, message, related_id)
  values (new.seller_id, 'new_enquiry', 'New customer enquiry',
          'A buyer has sent a question about one of your products.', new.id);
  return new;
end;
$$;

drop trigger if exists bazaar_enquiry_notification_insert on public.product_enquiries;
create trigger bazaar_enquiry_notification_insert
after insert on public.product_enquiries
for each row execute function public.bazaar_notify_new_enquiry();

-- Seller reply -> notify the buyer.
create or replace function public.bazaar_notify_enquiry_reply()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if new.seller_reply is not null
     and new.seller_reply is distinct from old.seller_reply then
    insert into public.bazaar_notifications(user_id, notification_type, title, message, related_id)
    values (new.sender_id, 'enquiry_reply', 'Seller replied',
            'A seller has replied to your product enquiry.', new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists bazaar_enquiry_notification_reply on public.product_enquiries;
create trigger bazaar_enquiry_notification_reply
after update of seller_reply on public.product_enquiries
for each row execute function public.bazaar_notify_enquiry_reply();

-- Buyer submits payment proof -> notify the seller.
create or replace function public.bazaar_notify_payment_proof()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.bazaar_notifications(user_id, notification_type, title, message, related_id)
  values (new.seller_id, 'payment_proof', 'Payment proof submitted',
          'A buyer has submitted payment proof for an order. Please check your BML account before reviewing it.', new.order_id);
  return new;
end;
$$;

drop trigger if exists bazaar_payment_notification_insert on public.bazaar_payment_submissions;
create trigger bazaar_payment_notification_insert
after insert on public.bazaar_payment_submissions
for each row execute function public.bazaar_notify_payment_proof();

-- Seller reviews payment -> notify the buyer.
create or replace function public.bazaar_notify_payment_review()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  if new.status is distinct from old.status
     and new.status in ('verified', 'rejected') then
    insert into public.bazaar_notifications(user_id, notification_type, title, message, related_id)
    values (new.buyer_id, 'payment_review',
            case when new.status = 'verified' then 'Payment verified' else 'Payment needs attention' end,
            case when new.status = 'verified'
                 then 'The seller has verified your payment.'
                 else 'The seller could not verify your payment. Check the seller note and contact the shop if needed.' end,
            new.order_id);
  end if;
  return new;
end;
$$;

drop trigger if exists bazaar_payment_notification_update on public.bazaar_payment_submissions;
create trigger bazaar_payment_notification_update
after update of status on public.bazaar_payment_submissions
for each row execute function public.bazaar_notify_payment_review();

-- Notification writers are trigger-only; callers cannot invoke them directly.
revoke all on function public.bazaar_notify_new_order() from public, anon, authenticated;
revoke all on function public.bazaar_notify_order_status() from public, anon, authenticated;
revoke all on function public.bazaar_notify_new_enquiry() from public, anon, authenticated;
revoke all on function public.bazaar_notify_enquiry_reply() from public, anon, authenticated;
revoke all on function public.bazaar_notify_payment_proof() from public, anon, authenticated;
revoke all on function public.bazaar_notify_payment_review() from public, anon, authenticated;
