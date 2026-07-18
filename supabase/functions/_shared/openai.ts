export class OpenAIError extends Error {
  constructor(public code: string, public retryable: boolean) {
    super(code);
  }
}

export interface EditResult {
  b64: string;
  size: string;
  inputTokens: number;
  outputTokens: number;
}

export async function runEdit(opts: {
  imageBytes: Uint8Array;
  filename: string;
  contentType?: string;
  prompt: string;
  size: string;
  quality: string;
}): Promise<EditResult> {
  const form = new FormData();
  form.append("model", "gpt-image-2");
  form.append("prompt", opts.prompt);
  form.append("size", opts.size);
  form.append("quality", opts.quality);
  // The Blob MUST carry a MIME type or the multipart part defaults to
  // application/octet-stream and OpenAI rejects it as unsupported_file_mimetype.
  form.append(
    "image",
    new Blob([opts.imageBytes], { type: opts.contentType || "image/png" }),
    opts.filename,
  );

  const res = await fetch("https://api.openai.com/v1/images/edits", {
    method: "POST",
    headers: { Authorization: `Bearer ${Deno.env.get("OPENAI_API_KEY")}` },
    body: form,
  });

  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    const code = body?.error?.code ?? `http_${res.status}`;
    if (code === "moderation_blocked") throw new OpenAIError("moderation_blocked", false);
    const retryable = res.status === 429 || res.status >= 500;
    throw new OpenAIError(code, retryable);
  }

  const data = await res.json();
  const item = data.data[0];
  return {
    b64: item.b64_json,
    size: item.size ?? opts.size,
    inputTokens: data.usage?.input_tokens ?? 0,
    outputTokens: data.usage?.output_tokens ?? 0,
  };
}
