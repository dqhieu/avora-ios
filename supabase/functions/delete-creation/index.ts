import { handleOptions, json } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;

  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let uid: string;
  try {
    uid = await requireUser(req);
  } catch {
    return json({ error: "unauthorized" }, 401);
  }

  let id: string;
  try {
    const body = await req.json();
    id = body?.id;
    if (typeof id !== "string" || id.length === 0) throw new Error("bad id");
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const db = serviceClient();

  const { data: gen } = await db
    .from("generations")
    .select("user_id, input_path, output_path")
    .eq("id", id)
    .maybeSingle();

  if (!gen) return json({ error: "not_found" }, 404);
  if (gen.user_id !== uid) return json({ error: "forbidden" }, 403);

  // Delete the row first (user-facing source of truth); FK cascade removes the
  // likes and drops it from the community feed. A leftover storage object is
  // invisible and gets swept by account deletion, so storage cleanup is
  // best-effort and its errors are ignored.
  const { error: delErr } = await db.from("generations").delete().eq("id", id);
  if (delErr) return json({ error: "delete_failed" }, 500);

  if (gen.output_path) {
    await db.storage.from("outputs").remove([gen.output_path]);
  }
  await db.storage.from("inputs").remove([gen.input_path]);

  return json({ ok: true });
});
