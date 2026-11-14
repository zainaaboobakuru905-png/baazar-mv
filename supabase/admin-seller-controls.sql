-- BazaarMV administrator seller suspension controls.
-- Run once in Supabase SQL Editor after the seller-directory setup.
-- Suspension preserves seller accounts, shop details, products and orders.
-- It hides active products publicly, blocks new orders and blocks seller product writes.

alter table public.seller_profiles
  add column if not exists is_suspended boolean not null default false,
  add column if not exists suspended_at timestamptz;

drop function if exists public.bazaar_admin_list_sellers();
create function public.bazaar_admin_list_sellers()
returns table (
  user_id uuid,
  seller_name text,
  shop_name text,
  island text,
  description text,
  approval_status text,
  created_at timestamptz,
  is_suspended boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.bazaar_admins a where a.user_id = auth.uid()) then
    raise exception 'Administrator access required.';
  end if;
  return query
    select s.user_id, coalesce(p.display_name, 'Seller'), s.shop_name,
           s.island, s.description, s.approval_status, s.created_at, s.is_suspended
    from public.seller_profiles s
    left join public.profiles p on p.id = s.user_id
    order by case s.approval_status when 'approved' then 0 when 'pending' then 1 else 2 end,
             s.created_at desc;
end;
$$;

create or replace function public.bazaar_admin_set_seller_suspended(
  p_user_id uuid,
  p_is_suspended boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.bazaar_admins a where a.user_id = auth.uid()) then
    raise exception 'Administrator access required.';
  end if;
  if p_user_id is null or p_is_suspended is null then
    raise exception 'Seller and suspension status are required.';
  end if;
  update public.seller_profiles
     set is_suspended = p_is_suspended,
         suspended_at = case when p_is_suspended then now() else null end
   where user_id = p_user_id;
  if not found then
    raise exception 'Seller profile not found.';
  end if;
end;
$$;

revoke all on function public.bazaar_admin_list_sellers() from public;
revoke all on function public.bazaar_admin_set_seller_suspended(uuid, boolean) from public;
grant execute on function public.bazaar_admin_list_sellers() to authenticated;
grant execute on function public.bazaar_admin_set_seller_suspended(uuid, boolean) to authenticated;

drop policy if exists "Anyone can view active products" on public.products;
create policy "Anyone can view active products" on public.products
for select to anon, authenticated
using (
  (is_active = true and not exists (
    select 1 from public.seller_profiles s
    where s.user_id = products.seller_id and s.is_suspended = true
  ))
  or seller_id = (select auth.uid())
);

drop policy if exists "Approved sellers insert own products" on public.products;
create policy "Approved sellers insert own products" on public.products
for insert to authenticated with check (
  seller_id = (select auth.uid()) and exists (
    select 1 from public.seller_profiles s
    where s.user_id = (select auth.uid())
      and s.approval_status = 'approved' and s.is_suspended = false
  )
);

drop policy if exists "Approved sellers update own products" on public.products;
create policy "Approved sellers update own products" on public.products
for update to authenticated using (
  seller_id = (select auth.uid()) and exists (
    select 1 from public.seller_profiles s
    where s.user_id = (select auth.uid())
      and s.approval_status = 'approved' and s.is_suspended = false
  )
) with check (
  seller_id = (select auth.uid()) and exists (
    select 1 from public.seller_profiles s
    where s.user_id = (select auth.uid())
      and s.approval_status = 'approved' and s.is_suspended = false
  )
);

drop policy if exists "Approved sellers delete own products" on public.products;
create policy "Approved sellers delete own products" on public.products
for delete to authenticated using (
  seller_id = (select auth.uid()) and exists (
    select 1 from public.seller_profiles s
    where s.user_id = (select auth.uid())
      and s.approval_status = 'approved' and s.is_suspended = false
  )
);

create or replace function public.bazaar_prevent_orders_for_suspended_sellers()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if exists (
    select 1 from public.seller_profiles s
    where s.user_id = new.seller_id and s.is_suspended = true
  ) then
    raise exception 'This seller is temporarily unavailable to receive new orders.';
  end if;
  return new;
end;
$$;

drop trigger if exists bazaar_block_suspended_seller_orders on public.orders;
create trigger bazaar_block_suspended_seller_orders
before insert on public.orders
for each row execute function public.bazaar_prevent_orders_for_suspended_sellers();
