// supabase/functions/subscription-payment-status/index.ts
//
// Memeriksa status pembayaran langsung ke Midtrans (GET .../v2/{order_id}/status)
// lalu menyinkronkannya. Dipakai aplikasi saat pengguna kembali dari halaman
// Snap, sebagai cadangan bila webhook belum sampai.
//
// Request  : { order_id: uuid, force?: boolean }
// Response : { ok: true, order: <baris subscription_orders> }

import { adminClient, fail, ok, pgMessage, preflight, userClient } from "../_shared/cors.ts";
import { getGatewayConfig, PaymentError, queryOrder } from "../_shared/payment-gateway.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const FINAL = ["paid", "failed", "expired", "cancelled", "refunded"];

Deno.serve(async (req: Request) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return fail("Metode tidak diizinkan.", 405);

  const user = userClient(req);
  if (!user) return fail("Silakan masuk kembali.", 401);

  try {
    const body = await req.json().catch(() => ({}));
    const orderId = String(body.order_id ?? "");
    const force = body.force === true;
    if (!UUID.test(orderId)) return fail("ID transaksi tidak valid.", 422);

    // Dibaca dengan JWT pengguna supaya RLS subscription_orders_read berlaku.
    const { data: order, error: readError } = await user
      .from("subscription_orders")
      .select()
      .eq("id", orderId)
      .maybeSingle();

    if (readError) return fail(pgMessage(readError, "Transaksi tidak dapat dibaca."), 400);
    if (!order) return fail("Transaksi tidak ditemukan.", 404);

    if (FINAL.includes(order.status) && !force) return ok(order);
    if (!order.checkout_url) return ok(order); // belum sempat dibuatkan transaksi

    const cfg = getGatewayConfig();
    const result = await queryOrder(cfg, { partnerReferenceNo: String(order.id) });

    if (result.status === order.status) return ok(order);

    const { data: settled, error: settleError } = await adminClient().rpc(
      "subscription_settle",
      {
        p_order_id: orderId,
        p_status: result.status,
        p_gateway_reference: result.transactionId,
        p_gateway_status: result.gatewayStatus,
        p_paid_at: result.status === "paid" ? result.paidAt ?? new Date().toISOString() : null,
        p_payload: result.raw,
        p_source: "inquiry",
      },
    );

    if (settleError) {
      console.error("subscription_settle gagal", settleError);
      return fail("Status pembayaran gagal disimpan.", 500);
    }
    return ok(settled ?? order);
  } catch (error) {
    if (error instanceof PaymentError) {
      console.error("payment-status gateway error", error.code, error.detail);
      return fail(error.message, error.status);
    }
    console.error("payment-status error", error);
    return fail("Status pembayaran belum dapat diperiksa.", 500);
  }
});