-- BazaarMV administrator seller directory.
-- Run once in Supabase SQL Editor. This adds a read-only directory of seller accounts.
create or replace function public.bazaar_admin_list_sellers()
returns table (
  user_id uuid,
  seller_name text,
  shop_name text,
  island text,
  description text,
  approval_status text,
  created_at timestamptz
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
    select s.user_id,
           coalesce(p.display_name, 'Seller'),
           s.shop_name,
           s.island,
           s.description,
           s.approval_status,
           s.created_at
    from public.seller_profiles s
    left join public.profiles p on p.id = s.user_id
    order by case s.approval_status when 'approved' then 0 when 'pending' then 1 else 2 end,
             s.created_at desc;
end;
$$;

revoke all on function public.bazaar_admin_list_sellers() from public;
grant execute on function public.bazaar_admin_list_sellers() to authenticated;
