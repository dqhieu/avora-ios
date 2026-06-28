import { json } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // shared-secret auth (configured in RevenueCat dashboard as Authorization header)
  const expected = `Bearer ${Deno.env.get("REVENUECAT_WEBHOOK_TOKEN")}`;
  if (req.headers.get("Authorization") !== expected) return json({ error: "unauthorized" }, 401);

  const body = await req.json().catch(() => null);
  const ev = body?.event;
  if (!ev) return json({ error: "bad_request" }, 400);

  const txId: string = ev.transaction_id ?? ev.id;
  const uid: string | undefined = ev.app_user_id;
  const type: string = ev.type;
  if (!txId || !uid) return json({ error: "bad_request" }, 400);

  const db = serviceClient();

  // idempotency: ledger insert; if it already exists, we've processed this event
  const kind = type === "NON_RENEWING_PURCHASE" ? "extra_pack"
             : type === "INITIAL_PURCHASE" ? "initial"
             : type === "RENEWAL" ? "renewal" : "other";
  if (kind !== "other") {
    const { error: dupe } = await db.from("purchases")
      .insert({ transaction_id: txId, user_id: uid, kind });
    if (dupe) {
      if (dupe.code === "23505") return json({ ok: true, deduped: true });  // PK conflict => already done
      return json({ error: "ledger_failed" }, 500);  // transient/unexpected error => let RC retry
    }
  }

  if (type === "INITIAL_PURCHASE" || type === "RENEWAL") {
    const periodEnd = ev.expiration_at_ms ? new Date(ev.expiration_at_ms).toISOString() : null;
    await db.from("profiles").update({
      weekly_credits: 1000, subscription_period_end: periodEnd, subscription_active: true,
    }).eq("id", uid);
  } else if (type === "NON_RENEWING_PURCHASE") {
    await db.rpc("grant_extra", { p_uid: uid, p_amount: 500 });
  } else if (type === "CANCELLATION") {
    // Grace period: entitlement honored until Apple's expiry — stay active.
    await db.from("profiles").update({ subscription_active: true }).eq("id", uid);
  } else if (type === "EXPIRATION") {
    // Period ended: deactivate and zero the weekly bucket (extra credits survive).
    await db.from("profiles").update({ subscription_active: false, weekly_credits: 0 }).eq("id", uid);
  }

  return json({ ok: true });
});
