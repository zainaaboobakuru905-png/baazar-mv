-- BazaarMV admin management and seller suspension.
-- Run after schema.sql, admin-seller-approvals.sql and admin-dashboard.sql.
-- This migration is additive and keeps administrator checks inside the database.

alter table public.seller_profiles
  add column if not exists is_suspended boolean not null default false;

-- Public shoppers can only see active products from approved, non-suspended sellers.
drop policy if exists "Anyone can view active products" on public.products;
create policy "Public can view active approved seller products"
on public.products for select to anon, authenticated
using (
  (seller_id = (select auth.uid()))
  or (
    is_active = true
    and exists (
      select 1 from public.seller_profiles s
      where s.user_id = products.seller_id
        and s.approval_status = 'approved'
        and s.is_suspended = false
    )
  )
);

-- Approved sellers only; suspension blocks listing changes.
drop policy if exists "Approved sellers insert own products" on public.products;
create policy "Approved non-suspended sellers insert own products"
on public.products for insert to authenticated
with check (
  seller_id = (select auth.uid())
  and exists (
    select 1 from public.seller_profiles s
    where s.user_id = (select auth.uid())
      and s.approval_status = 'approved'
      and s.is_suspended = false
  )
);

drop policy if exists "Approved sellers update own products" on public.products;
create policy "Approved non-suspended sellers update own products"
on public.products for update to authenticated
using (
  seller_id = (select auth.uid())
  and exists (
    select 1 from public.seller_profiles s
    where s.user_id = (select auth.uid())
      and s.approval_status = 'approved'
      and s.is_suspended = false
  )
)
with check (
  seller_id = (select auth.uid())
  and exists (
    select 1 from public.seller_profiles s
    where s.user_id = (select auth.uid())
      and s.approval_status = 'approved'
      and s.is_suspended = false
  )
);

drop policy if exists "Approved sellers delete own products" on public.products;
create policy "Approved non-suspended sellers delete own products"
on public.products for delete to authenticated
using (
  seller_id = (select auth.uid())
  and exists (
    select 1 from public.seller_profiles s
    where s.user_id = (select auth.uid())
      and s.approval_status = 'approved'
      and s.is_suspended = false
  )
);

drop policy if exists "Public can view approved seller shops" on public.seller_profiles;
create policy "Public can view approved active seller shops"
on public.seller_profiles for select to anon, authenticated
using (approval_status = 'approved' and is_suspended = false);

create or replace function public.bazaar_admin_list_sellers()
returns table (
  user_id uuid,
  shop_name text,
  seller_name text,
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
  if auth.uid() is null or not exists (
    select 1 from public.bazaar_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Administrator access required.';
  end if;
  return query
    select s.user_id, s.shop_name,
           coalesce(p.display_name, 'Seller'),
           s.island, s.description, s.approval_status,
           s.created_at, s.is_suspended
    from public.seller_profiles s
    left join public.profiles p on p.id = s.user_id
    order by s.created_at desc;
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
  if auth.uid() is null or not exists (
    select 1 from public.bazaar_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Administrator access required.';
  end if;
  if p_user_id is null or p_is_suspended is null then
    raise exception 'Seller and suspension status are required.';
  end if;
  if p_user_id = auth.uid() then
    raise exception 'You cannot suspend your own administrator account as a seller.';
  end if;
  update public.seller_profiles
     set is_suspended = p_is_suspended
   where user_id = p_user_id and approval_status = 'approved';
  if not found then
    raise exception 'Approved seller account not found.';
  end if;
end;
$$;

create or replace function public.bazaar_admin_update_product(
  p_product_id uuid,
  p_name text,
  p_category text,
  p_price numeric,
  p_stock integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.bazaar_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Administrator access required.';
  end if;
  if p_product_id is null
     or p_name is null or char_length(trim(p_name)) not between 1 and 100
     or p_category is null or char_length(trim(p_category)) not between 1 and 60
     or p_price is null or p_price <= 0
     or p_stock is null or p_stock < 0 then
    raise exception 'Enter a valid product name, category, price and stock quantity.';
  end if;
  update public.products
     set name = trim(p_name),
         category = trim(p_category),
         price_mvr = p_price,
         stock_quantity = p_stock,
         updated_at = now()
   where id = p_product_id;
  if not found then
    raise exception 'Product not found.';
  end if;
end;
$$;

create or replace function public.bazaar_admin_list_users()
returns table (
  display_name text,
  account_type text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not exists (
    select 1 from public.bazaar_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Administrator access required.';
  end if;
  return query
    select p.display_name,
      case
        when a.user_id is not null then 'Administrator'
        when s.user_id is not null then 'Seller'
        else 'Buyer'
      end::text,
      p.created_at
    from public.profiles p
    left join public.bazaar_admins a on a.user_id = p.id
    left join public.seller_profiles s on s.user_id = p.id
    order by p.created_at desc;
end;
$$;

revoke all on function public.bazaar_admin_list_sellers() from public;
revoke all on function public.bazaar_admin_set_seller_suspended(uuid,boolean) from public;
revoke all on function public.bazaar_admin_update_product(uuid,text,text,numeric,integer) from public;
revoke all on function public.bazaar_admin_list_users() from public;
grant execute on function public.bazaar_admin_list_sellers() to authenticated;
grant execute on function public.bazaar_admin_set_seller_suspended(uuid,boolean) to authenticated;
grant execute on function public.bazaar_admin_update_product(uuid,text,text,numeric,integer) to authenticated;
grant execute on function public.bazaar_admin_list_users() to authenticated;

-- place_bazaar_orders must also reject suspended sellers.
create or replace function public.place_bazaar_orders(p_items jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_item record;
  v_seller uuid;
  v_order_id uuid;
  v_total numeric(12,2);
  v_result jsonb := '[]'::jsonb;
  v_quantity integer;
  v_count integer;
begin
  if v_user is null then raise exception 'Please sign in before placing an order.'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) < 1 or jsonb_array_length(p_items) > 30 then
    raise exception 'Your cart must contain between 1 and 30 products.';
  end if;
  if exists (
    select 1 from jsonb_to_recordset(p_items) as i(product_id uuid, quantity integer)
    group by i.product_id having count(*) > 1
  ) then raise exception 'A product appears more than once in your cart.'; end if;
  if exists (
    select 1 from jsonb_to_recordset(p_items) as i(product_id uuid, quantity integer)
    where i.product_id is null or i.quantity is null or i.quantity < 1 or i.quantity > 50
  ) then raise exception 'One or more cart quantities are invalid.'; end if;

  for v_item in
    select p.id, p.seller_id, p.stock_quantity, p.is_active
    from public.products p
    join jsonb_to_recordset(p_items) as i(product_id uuid, quantity integer) on i.product_id = p.id
    order by p.id
    for update of p
  loop
    select i.quantity into v_quantity
    from jsonb_to_recordset(p_items) as i(product_id uuid, quantity integer)
    where i.product_id = v_item.id;
    if not v_item.is_active or v_item.stock_quantity < v_quantity then
      raise exception 'A product is unavailable or has insufficient stock. Refresh your cart.';
    end if;
    if v_item.seller_id = v_user then raise exception 'You cannot order your own product.'; end if;
    if not exists (
      select 1 from public.seller_profiles s
      where s.user_id = v_item.seller_id
        and s.approval_status = 'approved'
        and s.is_suspended = false
    ) then raise exception 'A seller is not currently approved to receive orders.'; end if;
  end loop;

  select count(*) into v_count
  from jsonb_to_recordset(p_items) as i(product_id uuid, quantity integer)
  join public.products p on p.id = i.product_id;
  if v_count <> jsonb_array_length(p_items) then raise exception 'One or more products could not be found.'; end if;

  for v_seller in
    select distinct p.seller_id
    from public.products p
    join jsonb_to_recordset(p_items) as i(product_id uuid, quantity integer) on i.product_id = p.id
    order by p.seller_id
  loop
    select coalesce(sum(p.price_mvr * i.quantity), 0)::numeric(12,2) into v_total
    from public.products p
    join jsonb_to_recordset(p_items) as i(product_id uuid, quantity integer) on i.product_id = p.id
    where p.seller_id = v_seller;

    insert into public.orders (buyer_id, seller_id, status, total_mvr)
    values (v_user, v_seller, 'New', v_total)
    returning id into v_order_id;

    insert into public.order_items (order_id, product_id, product_name, unit_price_mvr, quantity)
    select v_order_id, p.id, p.name, p.price_mvr, i.quantity
    from public.products p
    join jsonb_to_recordset(p_items) as i(product_id uuid, quantity integer) on p.id = i.product_id
    where p.seller_id = v_seller;

    update public.products p
    set stock_quantity = p.stock_quantity - i.quantity, updated_at = now()
    from jsonb_to_recordset(p_items) as i(product_id uuid, quantity integer)
    where p.id = i.product_id and p.seller_id = v_seller;

    v_result := v_result || jsonb_build_array(
      jsonb_build_object('order_id', v_order_id, 'seller_id', v_seller, 'total_mvr', v_total)
    );
  end loop;
  return v_result;
end;
$$;

revoke all on function public.place_bazaar_orders(jsonb) from public;
grant execute on function public.place_bazaar_orders(jsonb) to authenticated;
