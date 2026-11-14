# BazaarMV Supabase setup and current status

The published BazaarMV site uses Supabase for accounts, seller applications, product listings, inventory and order requests.

## Configuration already present in this repository

- `supabase/schema.sql`: profiles, seller applications, products, orders, order items, row-level security and the profile-creation trigger.
- `supabase/marketplace-orders.sql`: secure database functions for placing order requests, reserving stock and seller order-status updates.\n- `supabase/admin-seller-approvals.sql` and `supabase/admin-dashboard.sql`: administrator role table, seller application review and marketplace overview functions.\n- `supabase/admin-management.sql`: functions used by the admin seller/user/product controls, seller suspension, and database checks that prevent unapproved or suspended sellers from publishing products or receiving orders.
- `supabase-config.js`: the project URL and browser-safe publishable key.
- `auth.html`: shopper account creation/sign-in and seller application form.
- `seller.html`: seller product and order dashboard.
- `index.html`: marketplace, search, cart and order-request flow.
- `my-orders.html`: buyer order tracking.

The project owner previously reported that the base schema and marketplace-orders migration ran successfully in Supabase SQL Editor. The admin-management migration is newly added and has not been run against the live database. Compare the live Supabase database with the SQL files before re-running migrations.

## Seller approvals

Seller applications start as `pending`. A trusted administrator must review applications. Admin access is separate from seller access; do not create a public approval button or allow users to approve themselves. Run the admin SQL files in this order: `admin-seller-approvals.sql`, `admin-dashboard.sql`, then `admin-management.sql`. A trusted adult/qualified developer must provision the admin user securely.

## Email confirmation

The email template controls the contents of the message, but it cannot fix provider sending limits or SMTP delivery errors. The built-in Supabase email service has rate limits. Avoid repeatedly requesting messages when a send error appears. Do not share confirmation URLs, passwords, API keys or SMTP credentials in chat.

## What is not connected yet

- **Online payments / BML:** BazaarMV does not collect payments. A real BML merchant integration and server-side payment verification are required. A screenshot by itself is not proof of payment.
- **Instagram and Facebook integration:** Requires a Meta developer app, approved permissions, webhooks and a secure backend. Never ask sellers for their social-media passwords.
- **Direct product photo uploads:** Seller dashboard supports Supabase Storage uploads. Run `supabase/product-images-storage.sql` and verify its policies before using uploads.
- **Launch essentials:** Add and review privacy notice, terms, support contact and data-deletion process. Test with separate buyer and approved seller accounts before inviting customers.

## Security reminders

Use only the Supabase publishable/anon key in `supabase-config.js`. Never put a service-role key, database password or SMTP password in the website or GitHub repository.
