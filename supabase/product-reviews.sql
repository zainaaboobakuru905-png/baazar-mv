-- BazaarMV product ratings and reviews
-- Run once in Supabase SQL Editor after schema.sql and marketplace-orders.sql.

create table if not exists public.product_reviews (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  order_id uuid not null references public.orders(id) on delete cascade,
  buyer_id uuid not null references public.profiles(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  review_text text not null default '' check (char_length(review_text) <= 1000),
  created_at timestamptz not null default now(),
  constraint product_reviews_one_per_order unique (order_id, product_id)
);

create index if not exists product_reviews_product_created_idx
  on public.product_reviews(product_id, created_at desc);
create index if not exists product_reviews_buyer_idx
  on public.product_reviews(buyer_id, created_at desc);

alter table public.product_reviews enable row level security;

drop policy if exists "Anyone can read product reviews" on public.product_reviews;
create policy "Anyone can read product reviews"
on public.product_reviews for select to anon, authenticated
using (true);

drop policy if exists "Buyers review products from completed orders" on public.product_reviews;
create policy "Buyers review products from completed orders"
on public.product_reviews for insert to authenticated
with check (
  buyer_id = (select auth.uid())
  and exists (
    select 1
    from public.orders o
    join public.order_items oi on oi.order_id = o.id
    where o.id = product_reviews.order_id
      and o.buyer_id = (select auth.uid())
      and o.status = 'Completed'
      and oi.product_id = product_reviews.product_id
  )
);

-- Reviews are immutable after submission. No browser update/delete grants or policies.
revoke all on public.product_reviews from anon, public;
grant select on public.product_reviews to anon, authenticated;
grant insert on public.product_reviews to authenticated;
