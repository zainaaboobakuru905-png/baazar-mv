# BazaarMV

BazaarMV is a responsive marketplace for discovering products from Maldivian small businesses.

## Current website features

- Responsive marketplace with product search and category filters.
- Supabase-backed community product listings, seller applications and seller accounts.
- Seller dashboard for adding, editing and deleting listings, managing stock, viewing incoming orders and updating order status.
- Shopper cart and order requests, with stock checked and reserved by a Supabase database function.
- Shopper order-tracking page.
- Sample product cards are display examples only; they cannot be ordered.

## Open the website

The published site is hosted with GitHub Pages:
https://zainaaboobakuru905-png.github.io/baazar-mv/

## Important limitations before public launch

- Email confirmation depends on the Supabase email provider and its sending limits.
- Seller applications require manual approval by a trusted administrator in Supabase.
- BazaarMV currently records order requests only. It does not collect online payments or verify BML transfers.
- Instagram and Facebook Shop / messaging synchronisation is not connected. This requires a Meta app, approved permissions, webhooks and a secure backend.
- Product photos currently use public image URLs; direct uploads have not been configured.
- Add and review a privacy notice, terms, support contact and data-deletion process before accepting public customer information.
- Test the complete buyer and seller journeys with separate accounts before launch.

Never put a Supabase service-role key, database password, email-provider password or other secret in browser code or a public repository. Only the Supabase publishable/anon key belongs in the browser configuration.
