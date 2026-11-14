-- BazaarMV customer-to-seller enquiry inbox.
-- Run once in Supabase SQL Editor after the main schema.

create table if not exists public.product_enquiries (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  sender_id uuid not null references public.profiles(id) on delete cascade,
  message text not null check (char_length(trim(message)) between 5 and 1000),
  created_at timestamptz not null default now()
);

create index if not exists product_enquiries_seller_created_idx
  on public.product_enquiries(seller_id, created_at desc);
create index if not exists product_enquiries_sender_created_idx
  on public.product_enquiries(sender_id, created_at desc);

alter table public.product_enquiries enable row level security;

drop policy if exists "Buyers send product enquiries" on public.product_enquiries;
create policy "Buyers send product enquiries"
on public.product_enquiries for insert to authenticated
with check (
  sender_id = (select auth.uid())
  and seller_id <> (select auth.uid())
  and exists (
    select 1 from public.products p
    join public.seller_profiles s on s.user_id = p.seller_id
    where p.id = product_id
      and p.seller_id = seller_id
      and p.is_active = true
      and s.approval_status = 'approved'
  )
);

drop policy if exists "Buyers view their sent enquiries" on public.product_enquiries;
create policy "Buyers view their sent enquiries"
on public.product_enquiries for select to authenticated
using (sender_id = (select auth.uid()));

drop policy if exists "Sellers view received enquiries" on public.product_enquiries;
create policy "Sellers view received enquiries"
on public.product_enquiries for select to authenticated
using (seller_id = (select auth.uid()));

-- Seller replies stay inside BazaarMV; buyers can read them through their own enquiry rows.
alter table public.product_enquiries
  add column if not exists seller_reply text,
  add column if not exists replied_at timestamptz;

create or replace function public.seller_reply_to_product_enquiry(
  p_enquiry_id uuid,
  p_reply text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_reply text := trim(coalesce(p_reply, ''));
begin
  if auth.uid() is null then raise exception 'Please sign in.'; end if;
  if char_length(v_reply) < 2 or char_length(v_reply) > 1000 then
    raise exception 'Replies must be between 2 and 1000 characters.';
  end if;
  update public.product_enquiries
  set seller_reply = v_reply, replied_at = now()
  where id = p_enquiry_id and seller_id = auth.uid();
  if not found then raise exception 'Enquiry not found for this seller.'; end if;
end;
$$;

revoke all on function public.seller_reply_to_product_enquiry(uuid,text) from public;
grant execute on function public.seller_reply_to_product_enquiry(uuid,text) to authenticated;
