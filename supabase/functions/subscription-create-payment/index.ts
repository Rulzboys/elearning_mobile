// supabase/functions/subscription-create-payment/index.ts
//
// Membuat pesanan langganan lalu transaksi Snap di Midtrans.
//
// Request  : { id: uuid, plan: "monthly"|"annual", return_url?: string }
// Response : { ok: true, order: <baris subscription_orders> }
//
// Otorisasi tetap di database: pesanan dibuat lewat RPC subscription_action
// memakai JWT pengguna, sehingga aturan "hanya siswa" dan harga dari
// subscription_settings tidak bisa dilewati dari aplikasi.

import {
  adminClient,
  fail,
  ok,
  pgMessage,
  preflight,
  userClient,
} from "../_shared/cors.ts";
import {
  createOrder,
  getGatewayConfig,
  PaymentError,
} from "../_shared/payment-gateway.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request) => {
  const pre = preflight(req);
  if (pre) return pre;
  if (req.method !== "POST") return fail("Metode tidak diizinkan.", 405);

  const user = userClient(req);
  if (!user) return fail("Silakan masuk kembali.", 401);

  try {
    const body = await req.json().catch(() => ({}));
    const id = String(body.id ?? "");
    const plan = String(body.plan ?? "");
    const returnUrl = body.return_url ? String(body.return_url) : undefined;

    if (!UUID.test(id)) return fail("ID transaksi tidak valid.", 422);
    if (!["monthly", "annual"].includes(plan))
      return fail("Paket tidak valid.", 422);

    // 1. Pesanan dibuat oleh database (validasi peran + harga resmi).
    const { data: created, error: rpcError } = await user.rpc(
      "subscription_action",
      {
        p_action: "create",
        p_data: { id, plan },
      },
    );
    if (rpcError)
      return fail(pgMessage(rpcError, "Pesanan langganan gagal dibuat."), 400);

    const order = created as Record<string, unknown>;
    if (!order?.id) return fail("Pesanan langganan gagal dibuat.", 500);

    // Pesanan lama yang sudah lunas atau sudah punya checkout tidak perlu
    // transaksi baru (mis. pengguna refresh halaman checkout).
    if (order.status === "paid") return ok(order);
    if (String(order.checkout_url ?? "").length > 0) return ok(order);

    // 2. Transaksi Snap di Midtrans.
    const cfg = getGatewayConfig();
    const amount = Number(order.amount ?? 0);
    if (!Number.isFinite(amount) || amount <= 0)
      return fail("Nominal tagihan tidak valid.", 422);

    const admin = adminClient();

    try {
      const gateway = await createOrder(cfg, {
        partnerReferenceNo: String(order.id),
        amount,
        orderTitle:
          plan === "annual" ? "Langganan 1 tahun" : "Langganan 1 bulan",
        validMinutes: 60,
        returnUrl,
      });

      const { data: updated, error: updateError } = await admin
        .from("subscription_orders")
        .update({
          gateway: cfg.provider,
          gateway_env: cfg.env,
          // Token Snap disimpan di deeplink_url untuk kemungkinan pemakaian
          // Midtrans native SDK di masa depan; yang dipakai sekarang tetap
          // checkout_url (redirect_url) yang dibuka lewat browser.
          deeplink_url: gateway.token ?? "",
          checkout_url: gateway.checkoutUrl ?? "",
          expires_at: gateway.expiresAt,
          gateway_response: gateway.raw,
        })
        .eq("id", order.id)
        .select()
        .single();

      if (updateError) {
        return fail(
          pgMessage(updateError, "Data pembayaran gagal disimpan."),
          500,
        );
      }
      if (!updated.checkout_url) {
        return fail("Gateway tidak mengembalikan halaman pembayaran.", 502);
      }
      return ok(updated);
    } catch (gatewayError) {
      await admin
        .from("subscription_orders")
        .update({
          status: "failed",
          gateway_status: "CREATE_FAILED",
          gateway_response:
            gatewayError instanceof PaymentError
              ? { message: gatewayError.message, detail: gatewayError.detail }
              : { message: String(gatewayError) },
        })
        .eq("id", order.id);
      throw gatewayError;
    }
  } catch (error) {
    if (error instanceof PaymentError) {
      console.error("create-payment gateway error", error.code, error.detail);
      return fail(error.message, error.status);
    }
    console.error("create-payment error", error);
    return fail("Pembayaran tidak dapat diproses saat ini.", 500);
  }
});
