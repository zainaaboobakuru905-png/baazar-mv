create extension if not exists pgcrypto;

create table if not exists public.profiles (
 id uuid primary key references auth.users(id) on delete cascade,
 display_name text not null default '',
 created_at timestamptz not null default now()
);
create table if not exists public.products (
 id uuid primary key default gen_random_uuid(),
 seller_id uuid not null references public.profiles(id) on delete cascade,
 name text not null check (char_length(name) between 1 and 100),
 description text not null default '',
 category text not null default 'Other',
 price_mvr numeric(12,2) not null check (price_mvr > 0),
 stock_quantity integer not null default 0 check (stock_quantity >= 0),
 image_url text,
 is_active boolean not null default true,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists products_seller_id_idx on public.products(seller_id);
create index if not exists products_active_created_idx on public.products(is_active, created_at desc);

create table if not exists public.orders (
 id uuid primary key default gen_random_uuid(),
 buyer_id uuid not null references public.profiles(id),
 seller_id uuid not null references public.profiles(id),
 status text not null default 'New' check (status in ('New','Processing','Completed','Cancelled')),
 total_mvr numeric(12,2) not null check (total_mvr >= 0),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create table if not exists public.order_items (
 id uuid primary key default gen_random_uuid(),
 order_id uuid not null references public.orders(id) on delete cascade,
 product_id uuid not null references public.products(id),
 product_name text not null,
 unit_price_mvr numeric(12,2) not null check (unit_price_mvr > 0),
 quantity integer not null check (quantity > 0)
);
create index if not exists orders_buyer_created_idx on public.orders(buyer_id, created_at desc);
create index if not exists orders_seller_created_idx on public.orders(seller_id, created_at desc);
create index if not exists order_items_order_id_idx on public.order_items(order_id);

alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

drop policy if exists "Users read own profile" on public.profiles;
create policy "Users read own profile" on public.profiles for select to authenticated using (id = (select auth.uid()));
drop policy if exists "Users create own profile" on public.profiles;
create policy "Users create own profile" on public.profiles for insert to authenticated with check (id = (select auth.uid()));
drop policy if exists "Users update own profile" on public.profiles;
create policy "Users update own profile" on public.profiles for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

drop policy if exists "Anyone can view active products" on public.products;
create policy "Anyone can view active products" on public.products for select to anon, authenticated using (is_active = true or seller_id = (select auth.uid()));
drop policy if exists "Sellers insert own products" on public.products;
create policy "Sellers insert own products" on public.products for insert to authenticated with check (seller_id = (select auth.uid()));
drop policy if exists "Sellers update own products" on public.products;
create policy "Sellers update own products" on public.products for update to authenticated using (seller_id = (select auth.uid())) with check (seller_id = (select auth.uid()));
drop policy if exists "Sellers delete own products" on public.products;
create policy "Sellers delete own products" on public.products for delete to authenticated using (seller_id = (select auth.uid()));

drop policy if exists "Buyer and seller can view order" on public.orders;
create policy "Buyer and seller can view order" on public.orders for select to authenticated using (buyer_id = (select auth.uid()) or seller_id = (select auth.uid()));
drop policy if exists "Buyer and seller can view order items" on public.order_items;
create policy "Buyer and seller can view order items" on public.order_items for select to authenticated using (
 exists (select 1 from public.orders o where o.id = order_id and (o.buyer_id = (select auth.uid()) or o.seller_id = (select auth.uid())))
);

-- No direct browser policies for order creation, status changes or stock updates.
-- Add a trusted server/Edge Function before enabling real checkout.


-- Seller applications and approval gate.
create table if not exists public.seller_profiles (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 shop_name text not null,
 island text not null default '',
 description text not null default '',
 approval_status text not null default 'pending'
   check (approval_status in ('pending','approved','rejected')),
 created_at timestamptz not null default now()
);
alter table public.seller_profiles enable row level security;

drop policy if exists "Seller reads own application" on public.seller_profiles;
create policy "Seller reads own application" on public.seller_profiles
 for select to authenticated using (user_id = (select auth.uid()));

drop policy if exists "User submits seller application" on public.seller_profiles;
create policy "User submits seller application" on public.seller_profiles
 for insert to authenticated with check (
   user_id = (select auth.uid()) and approval_status = 'pending'
 );

-- Replace the earlier product write policies: only approved sellers may manage listings.
drop policy if exists "Sellers insert own products" on public.products;
drop policy if exists "Sellers update own products" on public.products;
drop policy if exists "Sellers delete own products" on public.products;

create policy "Approved sellers insert own products" on public.products
 for insert to authenticated with check (
   seller_id = (select auth.uid()) and exists (
     select 1 from public.seller_profiles s
     where s.user_id = (select auth.uid()) and s.approval_status = 'approved'
   )
);
create policy "Approved sellers update own products" on public.products
 for update to authenticated using (
   seller_id = (select auth.uid()) and exists (
     select 1 from public.seller_profiles s
     where s.user_id = (select auth.uid()) and s.approval_status = 'approved'
   )
) with check (
   seller_id = (select auth.uid()) and exists (
     select 1 from public.seller_profiles s
     where s.user_id = (select auth.uid()) and s.approval_status = 'approved'
   )
);
create policy "Approved sellers delete own products" on public.products
 for delete to authenticated using (
   seller_id = (select auth.uid()) and exists (
     select 1 from public.seller_profiles s
     where s.user_id = (select auth.uid()) and s.approval_status = 'approved'
   )
);

-- Orders remain read-only from the browser until a trusted checkout function
-- validates product prices, checks stock, writes order rows and decrements stock atomically.

-- Automatically create a profile when an account is registered.
create or replace function public.handle_new_bazaar_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
 insert into public.profiles (id, display_name)
 values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', ''))
 on conflict (id) do nothing;
 return new;
end;
$$;

do $$
begin
 if not exists (
   select 1 from pg_trigger
   where tgname = 'on_bazaar_auth_user_created'
     and tgrelid = 'auth.users'::regclass
 ) then
   create trigger on_bazaar_auth_user_created
   after insert on auth.users
   for each row execute procedure public.handle_new_bazaar_user();
 end if;
end;
$$;
