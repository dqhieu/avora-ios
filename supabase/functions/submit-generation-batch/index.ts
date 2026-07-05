import { handleOptions, json } from "../_shared/cors.ts";
import { requireUser, serviceClient } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  const pre = handleOptions(req); if (pre) return pre;
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let uid: string;
  try { uid = await requireUser(req); } catch { return json({ error: "unauthorized" }, 401); }

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { /* leave empty */ }
  const { style_id, custom_prompt, input_paths, quality } = body;

  // input_paths + quality are validated the same way in both modes.
  if (!Array.isArray(input_paths)) {
    return json({ error: "bad_request" }, 400);
  }
  // Cost is derived server-side from this value, so it must be validated here.
  if (typeof quality !== "string" || !["low", "medium", "high"].includes(quality)) {
    return json({ error: "bad_request" }, 400);
  }
  if (input_paths.length < 1 || input_paths.length > 4 ||
      !input_paths.every((p) => typeof p === "string")) {
    return json({ error: "bad_batch_size" }, 400);
  }
  // every path must belong to this user: "<uid>/<file>"
  if (!input_paths.every((p) => (p as string).startsWith(`${uid}/`))) {
    return json({ error: "forbidden_path" }, 403);
  }

  // Mode: custom when a non-empty custom_prompt is present, else preset.
  const isCustom = typeof custom_prompt === "string" &&
    custom_prompt.trim().length > 0;

  let styleIdArg: string | null = null;
  let customPromptArg: string | null = null;

  const db = serviceClient();

  if (isCustom) {
    if (typeof style_id === "string") {
      return json({ error: "bad_request" }, 400); // custom must not carry a style
    }
    const trimmed = (custom_prompt as string).trim();
    if (trimmed.length < 1 || trimmed.length > 1000) {
      return json({ error: "bad_request" }, 400);
    }
    customPromptArg = trimmed;
  } else {
    if (typeof style_id !== "string") {
      return json({ error: "bad_request" }, 400);
    }
    // style must exist and be active
    const { data: style } = await db.from("styles")
      .select("id, active").eq("id", style_id).single();
    if (!style || !style.active) return json({ error: "unknown_style" }, 400);
    styleIdArg = style_id;
  }

  // validate each input file (format/size) via Storage list + metadata
  for (const path of input_paths as string[]) {
    const slashIndex = path.indexOf("/");
    const folder = path.slice(0, slashIndex);
    const filename = path.slice(slashIndex + 1);
    const { data: fileList, error: listErr } = await db.storage
      .from("inputs").list(folder, { search: filename });
    const fileMeta = fileList?.find((f) => f.name === filename);
    if (listErr || !fileMeta) return json({ error: "input_not_found" }, 400);
    const contentType = fileMeta.metadata?.mimetype ?? "";
    const size = fileMeta.metadata?.size ?? Infinity;
    if (!["image/png", "image/jpeg"].includes(contentType) || size > 10 * 1024 * 1024) {
      return json({ error: "invalid_input" }, 400);
    }
  }

  // webhook backstop, then atomic all-or-nothing batch submit
  await db.rpc("lazy_weekly_reset", { p_uid: uid });
  const { data: jobIds, error: rpcErr } = await db.rpc("submit_generations_batch", {
    p_uid: uid,
    p_style_id: styleIdArg,
    p_input_paths: input_paths,
    p_quality: quality,
    p_custom_prompt: customPromptArg,
  });
  if (rpcErr) {
    if (rpcErr.code === "P0001" && rpcErr.message.includes("insufficient_credits"))
      return json({ error: "insufficient_credits" }, 402);
    return json({ error: "submit_failed" }, 500);
  }

  return json({ job_ids: jobIds }, 202);
});
