import { handleOptions, json } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";

// ADAPTATION: The brief calls `db.storage.from("inputs").info(input_path)` to validate
// the uploaded file. The supabase-js v2 storage client does not expose an `.info()` method.
// Instead, we split the path into prefix (uid folder) + filename, call `.list()` on the
// prefix, and locate the file entry to read its metadata (contentType, size). The same
// validation intent is preserved: file must exist, be png/jpeg, and be <= 10 MB.
//
// ADAPTATION: The brief uses `.catch()` chained on `db.rpc(...)` calls. supabase-js v2
// PostgREST builders are thenables but not full Promises, so `.catch()` is not available
// as a method. All such calls are wrapped in try/catch blocks instead.

Deno.serve(async (req) => {
  const pre = handleOptions(req); if (pre) return pre;
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let uid: string;
  try { uid = await requireUser(req); } catch { return json({ error: "unauthorized" }, 401); }

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { /* leave empty */ }
  const { style_id, input_path } = body;
  if (typeof style_id !== "string" || typeof input_path !== "string") {
    return json({ error: "bad_request" }, 400);
  }
  // input_path must belong to this user: "<uid>/<file>"
  if (!input_path.startsWith(`${uid}/`)) return json({ error: "forbidden_path" }, 403);

  const db = serviceClient();

  // style must exist and be active
  const { data: style } = await db.from("styles")
    .select("id, default_quality, active").eq("id", style_id).single();
  if (!style || !style.active) return json({ error: "unknown_style" }, 400);

  // server-side input validation (format/size) via Storage list + metadata
  // ADAPTATION: using .list() on the uid prefix folder, then finding the file entry,
  // because supabase-js v2 does not have a .info() method on the storage client.
  const slashIndex = input_path.indexOf("/");
  const folder = input_path.slice(0, slashIndex);       // "<uid>"
  const filename = input_path.slice(slashIndex + 1);    // "<file>"

  const { data: fileList, error: listErr } = await db.storage
    .from("inputs")
    .list(folder, { search: filename });

  const fileMeta = fileList?.find((f) => f.name === filename);
  if (listErr || !fileMeta) return json({ error: "input_not_found" }, 400);

  const contentType = fileMeta.metadata?.mimetype ?? "";
  const size = fileMeta.metadata?.size ?? Infinity;
  const okType = ["image/png", "image/jpeg"].includes(contentType);
  const okSize = size <= 10 * 1024 * 1024; // 10 MB cap
  if (!okType || !okSize) return json({ error: "invalid_input" }, 400);

  // webhook backstop, then atomic deduction
  await db.rpc("lazy_weekly_reset", { p_uid: uid });
  const { data: bucket, error: deductErr } = await db.rpc("deduct_credit", { p_uid: uid });
  if (deductErr) {
    // Key on SQLSTATE P0001 first (raised by deduct_credit for insufficient_credits);
    // fall back to message substring for safety.
    if (deductErr.code === "P0001" || deductErr.message.includes("insufficient_credits"))
      return json({ error: "insufficient_credits" }, 402);
    return json({ error: "deduct_failed" }, 500);
  }

  const { data: gen, error: insErr } = await db.from("generations").insert({
    user_id: uid, style_id, status: "pending",
    charged_bucket: bucket, charged_amount: 25,
    input_path, quality: style.default_quality,
  }).select("id").single();
  if (insErr || !gen) {
    // compensate: refund directly since no row persisted — re-credit the charged bucket.
    try {
      await db.rpc("refund_credit_direct", { p_uid: uid, p_bucket: bucket, p_amount: 25 });
    } catch (refundErr) {
      console.error("compensating refund failed", { uid, bucket, error: refundErr });
    }
    return json({ error: "insert_failed" }, 500);
  }

  try {
    await db.rpc("pgmq_send", { queue_name: "generations", msg: { job_id: gen.id } });
  } catch {
    // fall back to direct SQL if RPC wrapper absent
    try {
      await db.schema("pgmq").rpc("send", { queue_name: "generations", msg: { job_id: gen.id } });
    } catch { /* pgmq fallback also failed — generation row is still persisted */ }
  }

  return json({ job_id: gen.id }, 202);
});
