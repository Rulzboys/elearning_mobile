import { adminClient, corsHeaders, preflight } from "../_shared/cors.ts";
import {
  getGatewayConfig,
  normalizeStatus,
  verifyWebhookSignature,
} from "../_shared/payment-gateway.ts";

function respond(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "POST")
    return respond(405, { message: "Method Not Allowed" });

  const rawBody = await req.text();
  const cfg = getGatewayConfig();
  const admin = adminClient();

  let payload: Record<string, unknown> = {};
  try {
    payload = rawBody ? JSON.parse(rawBody) : {};
  } catch {
    return respond(400, { message: "Bad Request" });
  }

  const orderId = String(payload.order_id ?? "");

  // Semua notifikasi dicatat untuk audit, termasuk yang signature-nya gagal.
  const { data: event } = await admin
    .from("subscription_webhook_events")
    .insert({
      gateway: cfg.provider,
      gateway_env: cfg.env,
      order_id: UUID.test(orderId) ? orderId : null,
      gateway_reference: (payload.transaction_id as string) ?? null,
      signature_valid: false,
      headers: Object.fromEntries(req.headers),
      payload,
    })
    .select("id")
    .single();

  const skipVerify = Deno.env.get("PAYMENT_SKIP_SIGNATURE_VERIFY") === "true";
  const valid = skipVerify || (await verifyWebhookSignature({ cfg, payload }));

  if (!valid) {
    console.warn("Signature webhook Midtrans tidak valid", { orderId });
    return respond(401, { message: "Unauthorized" });
  }
  if (event?.id) {
    await admin
      .from("subscription_webhook_events")
      .update({ signature_valid: true })
      .eq("id", event.id);
  }

  if (!UUID.test(orderId)) return respond(400, { message: "Invalid order_id" });

  const transactionStatus = String(payload.transaction_status ?? "");
  const fraudStatus = String(payload.fraud_status ?? "");
  const status = normalizeStatus(transactionStatus, fraudStatus);
  const paidAt =
    status === "paid"
      ? ((payload.settlement_time as string) ??
        (payload.transaction_time as string) ??
        new Date().toISOString())
      : null;

  const { error } = await admin.rpc("subscription_settle", {
    p_order_id: orderId,
    p_status: status,
    p_gateway_reference: (payload.transaction_id as string) ?? null,
    p_gateway_status: transactionStatus,
    p_paid_at: paidAt,
    p_payload: payload,
    p_source: "webhook",
  });

  if (error) {
    if (error.message?.includes("tidak ditemukan")) {
      return respond(404, { message: "Transaction Not Found" });
    }
    console.error("subscription_settle gagal", error);
    return respond(500, { message: "Internal Server Error" });
  }

  return respond(200, { message: "ok" });
});
