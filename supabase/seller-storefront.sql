-- Public storefront details for approved sellers only.
-- Deliberately excludes payment instructions, QR URLs and other private seller settings.
create or replace view public.bazaar_public_seller_stores as
select user_id, shop_name, island, description
from public.seller_profiles
where approval_status = 'approved';

grant select on public.bazaar_public_seller_stores to anon, authenticated;
