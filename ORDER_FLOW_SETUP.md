# BazaarMV live order requests

Run `supabase/schema.sql` first if it has not already been applied. Then run the complete `supabase/marketplace-orders.sql` file in Supabase SQL Editor.

This enables order requests only; it does not collect payment. The database function recalculates totals from current product prices, locks stock rows, checks quantities and approved sellers, creates one order per seller, and decrements inventory in one transaction. A signed-in shopper is required. Sellers can move their own orders from New to Processing/Cancelled and from Processing to Completed/Cancelled.

Before public launch, test with two separate accounts (one approved seller and one shopper). Do not treat this as payment processing. Add an approved Maldives payment integration and server-side payment verification separately.
