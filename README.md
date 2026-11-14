# BazaarMV

BazaarMV is a responsive marketplace for discovering products from Maldivian small businesses.

## Current website features

- Responsive marketplace with product search and category filters.
- Supabase-backed community product listings, seller applications and seller accounts.
- Seller dashboard for adding, editing and deleting listings, managing stock, viewing incoming orders and updating order status.
- Shopper cart and order requests, with stock checked and reserved by a Supabase database function.
- Shopper order-tracking page and buyer-to-seller product enquiries with seller replies.
- Sample product cards are clearly labelled previews and cannot be ordered.
- Featured products display active community listings when available, otherwise clearly labelled previews.

## Open the website

The published site is hosted with GitHub Pages:
https://zainaaboobakuru905-png.github.io/baazar-mv/

## Important limitations before public launch

- Email confirmation depends on the Supabase email provider and its sending limits.
- Seller applications require manual approval by a trusted administrator. An administrator account is separate from a seller account; never bypass the self-review restriction.\n- The admin dashboard needs `supabase/admin-management.sql` in addition to `admin-seller-approvals.sql` and `admin-dashboard.sql`.
- BazaarMV currently records order requests only. It does not collect online payments or verify BML transfers.
- Instagram and Facebook Shop / messaging synchronisation is not connected. This requires a Meta app, approved permissions, webhooks and a secure backend.
- Seller dashboard supports direct product photo uploads to the public `product-images` Supabase Storage bucket (maximum 5 MB). Run `supabase/product-images-storage.sql` once in the Supabase SQL Editor after merging this feature.
- Add and review a privacy notice, terms, support contact and data-deletion process before accepting public customer information.
- The homepage loads the Supabase JavaScript library and public configuration before marketplace scripts run.
- Before public launch, test the complete buyer and seller journeys with separate accounts, including enquiries, replies, order creation, stock handling, and status updates.
- Confirm the Supabase SQL migrations and Storage policies listed in this repository have been run successfully in the intended project.
- Review database access policies and security-definer functions with a trusted adult or qualified developer. Do not grant admin privileges to an account by weakening database checks.

Never put a Supabase service-role key, database password, email-provider password or other secret in browser code or a public repository. Only the Supabase publishable/anon key belongs in the browser configuration.
