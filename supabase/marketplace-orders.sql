-- BazaarMV live order-request flow (no online payment).
-- Run after supabase/schema.sql in Supabase SQL Editor.

create policy "Public can view approved seller shops"
on public.seller_profiles for select to anon, authenticated
using (approval_status = 'approved');

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

  -- Lock inventory rows in a consistent order to prevent overselling.
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
      where s.user_id = v_item.seller_id and s.approval_status = 'approved'
    ) then raise exception 'A seller is not currently approved to receive orders.'; end if;
  end loop;

  -- Count only products that actually exist, so unknown IDs are rejected.
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
    join jsonb_to_recordset(p_items) as i(product_id uuid, quantity integer) on i.product_id = p.id
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

create or replace function public.seller_update_bazaar_order_status(p_order_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_current text;
begin
  if v_user is null then raise exception 'Please sign in.'; end if;
  if p_status not in ('Processing','Completed','Cancelled') then raise exception 'Invalid order status.'; end if;
  select status into v_current from public.orders
  where id = p_order_id and seller_id = v_user for update;
  if not found then raise exception 'Order not found for this seller.'; end if;
  if not ((v_current = 'New' and p_status in ('Processing','Cancelled'))
       or (v_current = 'Processing' and p_status in ('Completed','Cancelled'))) then
    raise exception 'This order status change is not allowed.';
  end if;

  -- Restore reserved stock exactly once when the seller cancels an order.
  if p_status = 'Cancelled' then
    update public.products p
    set stock_quantity = p.stock_quantity + oi.quantity, updated_at = now()
    from public.order_items oi
    where oi.order_id = p_order_id and p.id = oi.product_id;
  end if;

  update public.orders set status = p_status, updated_at = now() where id = p_order_id;
end;
$$;

revoke all on function public.seller_update_bazaar_order_status(uuid, text) from public;
grant execute on function public.seller_update_bazaar_order_status(uuid, text) to authenticated;
