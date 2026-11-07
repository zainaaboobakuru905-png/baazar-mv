# BazaarMV Supabase setup

The repository now contains a database foundation. The published website is still a static prototype and is not connected to Supabase yet.

## Set up the project
1. Create a Supabase project at https://supabase.com/dashboard.
2. Keep the database password private.
3. In Project Settings → API, copy the Project URL and publishable/anon key. Never use a service_role key in browser code or send it in chat.
4. Open SQL Editor and run the complete `supabase/schema.sql` file from this repository.
5. Enable Email under Authentication → Providers. Set the published BazaarMV URL as the Site URL and add it to allowed redirect URLs.

## What the schema creates
- Profiles linked to authenticated accounts.
- Seller applications with pending/approved/rejected status.
- Products with MVR price and stock quantity.
- Orders and order items.
- Row Level Security policies. Product listing writes are restricted to sellers whose application is approved.

A trusted administrator must approve seller applications from the Supabase dashboard. Do not make approval a public self-service action.

## Still required before the site is live
- Add a signup/login UI and connect it to Supabase Auth.
- Replace localStorage product reads/writes with authenticated database calls.
- Build a trusted server-side checkout function that recalculates prices, checks stock, creates orders and decrements stock atomically.
- Add safe seller order-status actions, image storage rules and moderation.
- Add privacy policy, terms, customer support and a data deletion process.
- Test with separate buyer and seller accounts before launch.

## Payments and social integrations
BML payments need an approved merchant account and integration. Payment status must be confirmed server-side; a screenshot alone is not proof of payment. Instagram/Facebook syncing requires Meta app setup, approved permissions and a backend. Never ask sellers for their social account passwords.

Do not accept real customer data or payments until the authentication, checkout, security and privacy work is complete and tested.
