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

  if (type === "INITIAL_PURCHASE" || type === "RENEWAL") {
    const periodEnd = ev.expiration_at_ms ? new Date(ev.expiration_at_ms).toISOString() : null;
    const kind = type === "INITIAL_PURCHASE" ? "initial" : "renewal";

    // apply_purchase does ledger insert + profile grant atomically.
    // If DB errors: return 500 so RevenueCat retries; the txn rolled back, no partial state.
    // If deduped: idempotent OK.
    const { data: result, error: rpcErr } = await db.rpc("apply_purchase", {
      p_tx:          txId,
      p_uid:         uid,
      p_kind:        kind,
      p_period_end:  periodEnd,
    });
    if (rpcErr) return json({ error: "purchase_failed" }, 500);
    if (result === "deduped") return json({ ok: true, deduped: true });
    return json({ ok: true });

  } else if (type === "NON_RENEWING_PURCHASE") {
    const { data: result, error: rpcErr } = await db.rpc("apply_purchase", {
      p_tx:          txId,
      p_uid:         uid,
      p_kind:        "extra_pack",
      p_period_end:  null,
    });
    if (rpcErr) return json({ error: "purchase_failed" }, 500);
    if (result === "deduped") return json({ ok: true, deduped: true });
    return json({ ok: true });

  } else if (type === "CANCELLATION") {
    // Grace period: entitlement honored until Apple's expiry — stay active.
    const { error: upErr } = await db.from("profiles")
      .update({ subscription_active: true }).eq("id", uid);
    if (upErr) return json({ error: "update_failed" }, 500);

  } else if (type === "EXPIRATION") {
    // Period ended: deactivate and zero the weekly bucket (extra credits survive).
    const { error: upErr } = await db.from("profiles")
      .update({ subscription_active: false, weekly_credits: 0 }).eq("id", uid);
    if (upErr) return json({ error: "update_failed" }, 500);
  }

  return json({ ok: true });
});
