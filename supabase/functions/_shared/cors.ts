// supabase/functions/_shared/cors.ts

import {
  createClient,
  SupabaseClient,
} from "https://esm.sh/@supabase/supabase-js@2.45.4";

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-timestamp, x-signature, x-partner-id, x-external-id, channel-id",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

/** Format respons yang dibaca SupabaseRepository. */
export function ok(order: unknown): Response {
  return json({ ok: true, order });
}

export function fail(message: string, status = 400): Response {
  return json({ ok: false, error: message }, status);
}

export function preflight(req: Request): Response | null {
  return req.method === "OPTIONS"
    ? new Response("ok", { headers: corsHeaders })
    : null;
}

/** Klien dengan JWT pengguna — semua RLS dan RPC tetap berlaku. */
export function userClient(req: Request): SupabaseClient | null {
  const authorization = req.headers.get("Authorization") ?? "";
  if (!authorization.startsWith("Bearer ")) return null;
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    },
  );
}

/** Klien service role — hanya untuk menulis kolom gateway. */
export function adminClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );
}

/** Pesan error Postgres yang aman ditampilkan ke pengguna. */
export function pgMessage(
  error: { message?: string } | null,
  fallback: string,
): string {
  const message = error?.message ?? "";
  return message && message.length < 200 ? message : fallback;
}
