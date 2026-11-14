-- BazaarMV admin user directory.
-- Run once in Supabase SQL Editor. This is read-only and does not expose email addresses.

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
  if not exists (
    select 1 from public.bazaar_admins a where a.user_id = auth.uid()
  ) then
    raise exception 'Administrator access required.';
  end if;

  return query
    select
      coalesce(nullif(p.display_name, ''), 'Unnamed account')::text,
      case
        when exists (select 1 from public.bazaar_admins a where a.user_id = p.id) then 'Administrator'
        when exists (select 1 from public.seller_profiles s where s.user_id = p.id) then 'Seller'
        else 'Buyer'
      end::text,
      p.created_at
    from public.profiles p
    order by p.created_at desc;
end;
$$;

revoke all on function public.bazaar_admin_list_users() from public;
grant execute on function public.bazaar_admin_list_users() to authenticated;
