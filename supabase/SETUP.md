# BazaarMV database setup (Supabase)

This folder contains the first database foundation for BazaarMV.

## What it creates
- profiles: basic account display names linked to Supabase Auth users
- products: seller-owned listings, prices, stock and active/inactive status
- orders and order_items: buyer/seller order records
- Row Level Security: public visitors can browse active listings; signed-in sellers can manage only their own products; order records are visible only to their buyer and seller

## Setup
1. Create a Supabase project (ask a trusted adult to help with account setup if needed).
2. Open SQL Editor in the Supabase dashboard.
3. Paste and run schema.sql.
4. In Project Settings → API, locate the Project URL and publishable/anon key.
5. Never put a service_role or secret key in website JavaScript or share it in chat.

## Important limitations
This is the database structure, not a live connection yet. The current GitHub Pages site still uses browser storage for demo listings/cart/orders. The schema intentionally blocks direct browser order creation and order updates. A trusted server/Edge Function must validate prices, stock, ownership and order status before writing orders or changing inventory.

Do not accept real customer details or payments until authentication, server-side order processing, privacy rules, backups and payment verification have been reviewed and tested. BML integration requires appropriate merchant setup and server-side confirmation.
