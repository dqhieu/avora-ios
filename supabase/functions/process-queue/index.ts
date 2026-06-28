import { json } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { runEdit, OpenAIError } from "../_shared/openai.ts";

const VISIBILITY = 120;          // seconds a claimed job is hidden
const MAX_BATCH = Number(Deno.env.get("WORKER_MAX_BATCH") ?? "5");   // <= tier IPM
const DAILY_TOKEN_CAP = Number(Deno.env.get("DAILY_TOKEN_CAP") ?? "50000000");

Deno.serve(async () => {
  const db = serviceClient();

  // spend cap check
  const today = new Date().toISOString().slice(0, 10);
  const { data: spend } = await db.from("daily_spend").select("total_tokens").eq("day", today).maybeSingle();
  if ((spend?.total_tokens ?? 0) >= DAILY_TOKEN_CAP) return json({ skipped: "spend_cap" });

  // ADAPTATION: PostgREST only exposes the public schema. db.schema("pgmq").rpc() returns
  // PGRST106 "Invalid schema: pgmq". We use public wrapper RPCs (pgmq_read / pgmq_archive)
  // defined in migration 000009_pgmq_wrappers.sql that call into the pgmq schema via security
  // definer, and return jsonb so PostgREST can serialise the result correctly.
  const { data: msgsRaw } = await db.rpc("pgmq_read", { queue_name: "generations", vt: VISIBILITY, qty: MAX_BATCH });
  const msgs: Array<{ msg_id: number; read_ct: number; message: { job_id: string } }> = Array.isArray(msgsRaw) ? msgsRaw : [];
  if (!msgs?.length) return json({ processed: 0 });

  let processed = 0;
  for (const m of msgs) {
    const jobId = m.message.job_id as string;
    const msgId = m.msg_id as number;
    try {
      const { data: gen } = await db.from("generations")
        .select("id,user_id,style_id,input_path,quality,status").eq("id", jobId).single();
      if (!gen || gen.status !== "pending") { await archive(db, msgId); continue; }

      const { data: style } = await db.from("styles")
        .select("prompt_template,default_size").eq("id", gen.style_id).single();

      const { data: blob } = await db.storage.from("inputs").download(gen.input_path);
      const bytes = new Uint8Array(await blob!.arrayBuffer());

      const result = await runEdit({
        imageBytes: bytes, filename: "input.png",
        prompt: style!.prompt_template, size: style!.default_size, quality: gen.quality,
      });

      const outPath = `${gen.user_id}/${jobId}.png`;
      await db.storage.from("outputs").upload(outPath, decodeB64(result.b64), {
        contentType: "image/png", upsert: true,
      });

      await db.from("generations").update({
        status: "completed", output_path: outPath, size: result.size,
        input_tokens: result.inputTokens, output_tokens: result.outputTokens,
        completed_at: new Date().toISOString(),
      }).eq("id", jobId).eq("status", "pending");

      await bumpSpend(db, today, result.inputTokens + result.outputTokens);
      await archive(db, msgId);
      processed++;
    } catch (e) {
      if (e instanceof OpenAIError && e.retryable) {
        // leave message un-archived: visibility timeout returns it for retry.
        // mark failed + refund only after pgmq read_ct exceeds threshold:
        if ((m.read_ct ?? 1) >= 3) {
          await db.from("generations").update({ error_code: e.code }).eq("id", jobId);
          await db.rpc("refund_credit", { p_generation_id: jobId });
          await archive(db, msgId);
        }
        continue;
      }
      // non-retryable (incl. moderation_blocked): fail + always refund
      const code = e instanceof OpenAIError ? e.code : "worker_error";
      await db.from("generations").update({ error_code: code }).eq("id", jobId);
      await db.rpc("refund_credit", { p_generation_id: jobId });
      await archive(db, msgId);
    }
  }
  return json({ processed });
});

function decodeB64(b64: string): Uint8Array {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function archive(db: ReturnType<typeof serviceClient>, msgId: number) {
  await db.rpc("pgmq_archive", { queue_name: "generations", msg_id: msgId });
}

async function bumpSpend(db: ReturnType<typeof serviceClient>, day: string, tokens: number) {
  await db.rpc("bump_daily_tokens", { p_day: day, p_tokens: tokens });
}
