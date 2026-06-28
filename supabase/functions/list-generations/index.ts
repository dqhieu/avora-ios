import { handleOptions, json } from "../_shared/cors.ts";
import { requireUser, userClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pre = handleOptions(req); if (pre) return pre;
  try { await requireUser(req); } catch { return json({ error: "unauthorized" }, 401); }

  const url = new URL(req.url);
  const limit = Math.min(Number(url.searchParams.get("limit") ?? "20"), 50);
  const cursor = url.searchParams.get("cursor");

  let q = userClient(req).from("generations")
    .select("id, style_id, status, output_path, created_at")
    .order("created_at", { ascending: false })
    .limit(limit + 1);
  if (cursor) q = q.lt("created_at", cursor);

  const { data, error } = await q;
  if (error) return json({ error: "query_failed" }, 500);

  const items = (data ?? []).slice(0, limit);
  const next_cursor = (data ?? []).length > limit ? items[items.length - 1].created_at : undefined;
  return json({ items, next_cursor });
});
