import { handleOptions, json } from "../_shared/cors.ts";
import { requireUser, userClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pre = handleOptions(req); if (pre) return pre;
  try { await requireUser(req); } catch { return json({ error: "unauthorized" }, 401); }

  const id = new URL(req.url).searchParams.get("id");
  if (!id) return json({ error: "bad_request" }, 400);

  const { data, error } = await userClient(req).from("generations")
    .select("status, output_path, error_code").eq("id", id).maybeSingle();
  if (error) return json({ error: "query_failed" }, 500);
  if (!data) return json({ error: "not_found" }, 404);  // RLS hides others' rows
  return json(data);
});
