-- BazaarMV: secure administrator product editing.
-- Run this once in Supabase SQL Editor after admin-dashboard.sql.

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
  if not exists (
    select 1 from public.bazaar_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Administrator access required.';
  end if;

  if p_product_id is null then
    raise exception 'Product is required.';
  end if;
  if p_name is null or char_length(trim(p_name)) not between 1 and 100 then
    raise exception 'Product name must be between 1 and 100 characters.';
  end if;
  if p_category is null or char_length(trim(p_category)) not between 1 and 60 then
    raise exception 'Category must be between 1 and 60 characters.';
  end if;
  if p_price is null or p_price <= 0 or p_price > 9999999999.99 then
    raise exception 'Enter a valid positive price.';
  end if;
  if p_stock is null or p_stock < 0 then
    raise exception 'Stock must be zero or more.';
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

revoke all on function public.bazaar_admin_update_product(uuid, text, text, numeric, integer) from public;
grant execute on function public.bazaar_admin_update_product(uuid, text, text, numeric, integer) to authenticated;
