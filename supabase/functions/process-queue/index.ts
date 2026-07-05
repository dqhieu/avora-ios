import { json } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/supabase.ts";
import { runEdit, OpenAIError } from "../_shared/openai.ts";
import { Image } from "https://deno.land/x/imagescript@1.3.0/mod.ts";

const JPEG_QUALITY = Number(Deno.env.get("OUTPUT_JPEG_QUALITY") ?? "85");

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
    let inputPath: string | undefined;
    try {
      const { data: gen } = await db.from("generations")
        .select("id,user_id,style_id,custom_prompt,input_path,quality,status").eq("id", jobId).single();
      if (!gen || gen.status !== "pending") { await archive(db, msgId); continue; }
      inputPath = gen.input_path;

      // Custom jobs carry their own words (no preset row); preset jobs load the
      // curated template. size "auto" matches styles.default_size for custom.
      let prompt: string;
      let size: string;
      if (gen.custom_prompt) {
        prompt = `Restyle this photo: ${gen.custom_prompt}. Preserve the subject's likeness and pose. Do not add text or watermarks.`;
        size = "auto";
      } else {
        const { data: style } = await db.from("styles")
          .select("prompt_template,default_size").eq("id", gen.style_id).single();
        prompt = style!.prompt_template;
        size = style!.default_size;
      }

      const { data: blob } = await db.storage.from("inputs").download(gen.input_path);
      const bytes = new Uint8Array(await blob!.arrayBuffer());
      const contentType = blob!.type || "image/png";
      const filename = contentType === "image/jpeg" ? "input.jpg" : "input.png";

      const result = await runEdit({
        imageBytes: bytes, filename, contentType,
        prompt, size, quality: gen.quality,
      });

      const jpeg = await toJpeg(decodeB64(result.b64));
      const outPath = `${gen.user_id}/${jobId}.jpg`;
      await db.storage.from("outputs").upload(outPath, jpeg, {
        contentType: "image/jpeg", upsert: true,
      });

      await db.from("generations").update({
        status: "completed", output_path: outPath, size: result.size,
        input_tokens: result.inputTokens, output_tokens: result.outputTokens,
        completed_at: new Date().toISOString(),
      }).eq("id", jobId).eq("status", "pending");

      await bumpSpend(db, today, result.inputTokens + result.outputTokens);
      await archive(db, msgId);
      await removeInput(db, inputPath);
      processed++;
    } catch (e) {
      if (e instanceof OpenAIError && e.retryable) {
        // leave message un-archived: visibility timeout returns it for retry.
        // mark failed + refund only after pgmq read_ct exceeds threshold:
        if ((m.read_ct ?? 1) >= 3) {
          await db.from("generations").update({ error_code: e.code }).eq("id", jobId);
          await db.rpc("refund_credit", { p_generation_id: jobId });
          await archive(db, msgId);
          await removeInput(db, inputPath);
        }
        continue;
      }
      // non-retryable (incl. moderation_blocked): fail + always refund
      const code = e instanceof OpenAIError ? e.code : "worker_error";
      await db.from("generations").update({ error_code: code }).eq("id", jobId);
      await db.rpc("refund_credit", { p_generation_id: jobId });
      await archive(db, msgId);
      await removeInput(db, inputPath);
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

// Re-encode the PNG returned by the image model as JPEG to shrink stored file size.
// gpt-image outputs are opaque (no transparent background requested), so dropping
// the alpha channel is safe.
async function toJpeg(pngBytes: Uint8Array): Promise<Uint8Array> {
  const img = await Image.decode(pngBytes);
  return await img.encodeJPEG(JPEG_QUALITY);
}

async function archive(db: ReturnType<typeof serviceClient>, msgId: number) {
  await db.rpc("pgmq_archive", { queue_name: "generations", msg_id: msgId });
}

// Drop the input image once the job is terminal — it's never read again. Best-effort:
// a storage error here must not throw, or it would refund/re-queue a finished job.
async function removeInput(db: ReturnType<typeof serviceClient>, path: string | undefined) {
  if (!path) return;
  try { await db.storage.from("inputs").remove([path]); } catch { /* ignore */ }
}

async function bumpSpend(db: ReturnType<typeof serviceClient>, day: string, tokens: number) {
  await db.rpc("bump_daily_tokens", { p_day: day, p_tokens: tokens });
}
