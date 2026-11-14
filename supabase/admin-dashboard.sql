-- BazaarMV admin dashboard: marketplace-wide product and order oversight.
-- Run once in Supabase SQL Editor after the admin-seller-approvals.sql setup.

create or replace function public.bazaar_admin_list_products()
returns table (
  product_id uuid,
  product_name text,
  category text,
  price_mvr numeric,
  stock_quantity integer,
  is_active boolean,
  created_at timestamptz,
  seller_id uuid,
  seller_name text,
  shop_name text
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
    select p.id, p.name, p.category, p.price_mvr, p.stock_quantity, p.is_active,
           p.created_at, p.seller_id, coalesce(pr.display_name, ''),
           coalesce(sp.shop_name, 'Seller account')
    from public.products p
    left join public.profiles pr on pr.id = p.seller_id
    left join public.seller_profiles sp on sp.user_id = p.seller_id
    order by p.created_at desc;
end;
$$;

create or replace function public.bazaar_admin_set_product_active(p_product_id uuid, p_is_active boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.bazaar_admins a where a.user_id = auth.uid()) then
    raise exception 'Administrator access required.';
  end if;
  if p_product_id is null or p_is_active is null then
    raise exception 'Product and visibility status are required.';
  end if;
  update public.products
     set is_active = p_is_active, updated_at = now()
   where id = p_product_id;
  if not found then
    raise exception 'Product not found.';
  end if;
end;
$$;

create or replace function public.bazaar_admin_list_orders()
returns table (
  order_id uuid,
  order_status text,
  total_mvr numeric,
  created_at timestamptz,
  buyer_name text,
  seller_name text,
  shop_name text,
  item_count bigint
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
    select o.id, o.status, o.total_mvr, o.created_at,
           coalesce(bp.display_name, 'Buyer'),
           coalesce(spf.display_name, 'Seller'),
           coalesce(s.shop_name, 'Seller account'),
           (select count(*) from public.order_items oi where oi.order_id = o.id)
    from public.orders o
    left join public.profiles bp on bp.id = o.buyer_id
    left join public.profiles spf on spf.id = o.seller_id
    left join public.seller_profiles s on s.user_id = o.seller_id
    order by o.created_at desc;
end;
$$;

revoke all on function public.bazaar_admin_list_products() from public;
revoke all on function public.bazaar_admin_set_product_active(uuid, boolean) from public;
revoke all on function public.bazaar_admin_list_orders() from public;
grant execute on function public.bazaar_admin_list_products() to authenticated;
grant execute on function public.bazaar_admin_set_product_active(uuid, boolean) to authenticated;
grant execute on function public.bazaar_admin_list_orders() to authenticated;
