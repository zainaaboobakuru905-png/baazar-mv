# BazaarMV browser push setup

Browser permission and the service worker are only the first part. This Edge Function sends actual Web Push messages.

## Required secrets

Create a VAPID key pair locally (never paste the private key into GitHub or ChatGPT). One option on a computer with Node.js installed:

```bash
npx web-push generate-vapid-keys
```

In Supabase Dashboard → Edge Functions → Secrets, add:

- `VAPID_PUBLIC_KEY` — the generated public key
- `VAPID_PRIVATE_KEY` — the generated private key (keep secret)
- `PUSH_WEBHOOK_SECRET` — a long, randomly generated secret used only by the database webhook

Supabase provides `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions automatically. Never put the service-role key in website code.

## Deploy

Deploy the `bazaar-push` Edge Function from `supabase/functions/bazaar-push/index.ts`. The function's JWT verification must be disabled because the database webhook authenticates with `PUSH_WEBHOOK_SECRET`; the function itself checks that secret before processing POST requests.

## Database webhook

After the function is deployed and secrets are set, create a Database Webhook for:

- Table: `public.bazaar_notifications`
- Event: INSERT
- Method: POST
- URL: `https://uoxwcbbkiqmasfpujggk.supabase.co/functions/v1/bazaar-push`
- Header: `Authorization: Bearer <the same PUSH_WEBHOOK_SECRET>`
- Header: `Content-Type: application/json`

The function uses the notification row's `user_id`, `title`, and `message` to send the alert to that user's saved browser subscriptions.

## Important remaining frontend step

The homepage currently requests browser permission and registers the service worker, but it does not yet create and save a PushSubscription. The next code change must fetch the public key from this function, subscribe the signed-in user, and upsert the endpoint and keys into `public.bazaar_push_subscriptions`. Until that is completed and tested, browser push messages will not be delivered.

Test with a non-sensitive test notification only. Do not use real payment details or private customer data in notification text.
