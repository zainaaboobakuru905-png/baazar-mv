-- BazaarMV secure seller-application administration.
-- Run this once in Supabase SQL Editor after merging the website changes.
-- A trusted adult should add the administrator account using the setup instructions below.

create table if not exists public.bazaar_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.bazaar_admins enable row level security;
-- Deliberately no browser policies: only database administrators manage this table.

create or replace function public.bazaar_admin_list_seller_applications()
returns table (
  user_id uuid,
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
    select s.user_id, s.shop_name, s.island, s.description, s.approval_status, s.created_at
    from public.seller_profiles s
    order by case s.approval_status when 'pending' then 0 else 1 end, s.created_at asc;
end;
$$;

create or replace function public.bazaar_admin_review_seller(p_user_id uuid, p_status text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (select 1 from public.bazaar_admins a where a.user_id = auth.uid()) then
    raise exception 'Administrator access required.';
  end if;
  if p_user_id is null or p_user_id = auth.uid() then
    raise exception 'You cannot review your own seller application.';
  end if;
  if p_status not in ('approved','rejected') then
    raise exception 'Choose approved or rejected.';
  end if;
  update public.seller_profiles
     set approval_status = p_status
   where user_id = p_user_id and approval_status = 'pending';
  if not found then
    raise exception 'Pending seller application not found.';
  end if;
end;
$$;

revoke all on function public.bazaar_admin_list_seller_applications() from public;
revoke all on function public.bazaar_admin_review_seller(uuid,text) from public;
grant execute on function public.bazaar_admin_list_seller_applications() to authenticated;
grant execute on function public.bazaar_admin_review_seller(uuid,text) to authenticated;

-- To grant admin access, first create/sign in to a separate trusted administrator
-- account. Then run this SQL with that account's Auth user UUID:
-- insert into public.bazaar_admins (user_id) values ('PASTE-ADMIN-USER-UUID-HERE');
-- Never use a seller's account as the administrator account.
