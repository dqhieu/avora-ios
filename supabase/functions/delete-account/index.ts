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

  const db = serviceClient();

  for (const bucket of ["inputs", "outputs"]) {
    const { data: files } = await db.storage.from(bucket).list(uid);
    if (files?.length) {
      await db.storage.from(bucket).remove(files.map((f) => `${uid}/${f.name}`));
    }
  }

  // Deleting the auth user cascades generations + profiles via FK on delete cascade
  await db.auth.admin.deleteUser(uid);

  return json({ ok: true });
});
