# BazaarMV Supabase setup

These files prepare the database; they do not connect the current static website automatically.

1. Create a project at https://supabase.com/dashboard.
2. In Project Settings → API, copy the project URL and publishable/anon key. Keep the database password and service_role key private.
3. Open SQL Editor and run `supabase/schema.sql` from this repository.
4. Enable Email in Authentication → Providers. Set the published BazaarMV URL as Site URL and add it to allowed redirect URLs.
5. New seller profiles start pending. A trusted administrator must approve them in the Supabase dashboard.
6. Connect the frontend with the Supabase JavaScript client and publishable/anon key only. Keep Row Level Security enabled.
7. Before launch, implement server-side order validation, stock deduction, secure image storage, privacy terms, account deletion and tests with separate buyer/seller accounts.

Limitations: the current marketplace and seller dashboard still use browser localStorage and are not connected to these tables. BML needs an approved merchant integration and server-side payment confirmation. Meta/Instagram/Facebook syncing needs approved Meta app permissions and a backend. Do not accept real payments or private customer data until those pieces are built and security-tested.
