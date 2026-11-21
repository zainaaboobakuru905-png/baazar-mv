import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://zainaaboobakuru905-png.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Content-Type": "application/json",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: corsHeaders });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const publicKey = Deno.env.get("VAPID_PUBLIC_KEY");
  const privateKey = Deno.env.get("VAPID_PRIVATE_KEY");
  const webhookSecret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  if (req.method === "GET") {
    if (!publicKey) return json({ error: "Push is not configured yet." }, 503);
    return json({ publicKey });
  }

  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);
  if (!webhookSecret || req.headers.get("Authorization") !== `Bearer ${webhookSecret}`) {
    return json({ error: "Unauthorized." }, 401);
  }
  if (!publicKey || !privateKey || !supabaseUrl || !serviceRoleKey) {
    return json({ error: "Push sender is not fully configured." }, 503);
  }

  let payload: any;
  try { payload = await req.json(); } catch { return json({ error: "Invalid JSON." }, 400); }
  const record = payload?.record ?? payload;
  const userId = record?.user_id;
  const title = String(record?.title ?? "BazaarMV").slice(0, 100);
  const body = String(record?.message ?? record?.body ?? "You have a new update.").slice(0, 240);
  if (typeof userId !== "string") return json({ error: "Missing notification user_id." }, 400);

  const db = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: subscriptions, error } = await db
    .from("bazaar_push_subscriptions")
    .select("endpoint,p256dh,auth")
    .eq("user_id", userId);

  if (error) return json({ error: "Could not load push subscriptions." }, 500);
  if (!subscriptions?.length) return json({ sent: 0, message: "No subscribed browsers." });

  webpush.setVapidDetails("mailto:support@bazaarmv.com", publicKey, privateKey);
  let sent = 0;
  let expired = 0;
  for (const sub of subscriptions) {
    try {
      await webpush.sendNotification(
        { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
        JSON.stringify({
          title,
          body,
          url: record?.related_id ? "./my-orders.html" : "./",
        }),
      );
      sent++;
    } catch (err) {
      const statusCode = (err as { statusCode?: number })?.statusCode;
      if (statusCode === 404 || statusCode === 410) {
        await db.from("bazaar_push_subscriptions").delete().eq("endpoint", sub.endpoint);
        expired++;
      }
    }
  }
  return json({ sent, expired });
});
