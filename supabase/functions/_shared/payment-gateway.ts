// supabase/functions/_shared/payment-gateway.ts
//
// Helper bersama untuk payment gateway Midtrans (Snap API).
// Sandbox -> production cukup ganti secrets, tanpa mengubah kode.
//
// Jauh lebih sederhana dari SNAP BI (DANA dkk): autentikasi cukup Basic Auth
// dengan Server Key, tanpa RSA key pair dan tanpa access-token flow.
//
// Secrets yang dibaca:
//   PAYMENT_ENV              = "sandbox" | "production"   (default sandbox)
//   MIDTRANS_SERVER_KEY      = Server Key (dari Settings > Access Keys)
//   MIDTRANS_CLIENT_KEY      = Client Key (tidak dipakai di server, hanya
//                              didokumentasikan di sini untuk referensi FE)
//   PAYMENT_RETURN_URL       = deeplink aplikasi setelah pembayaran selesai
//                              (dikirim sebagai callbacks.finish ke Snap)
//
// Yang WAJIB dikonfigurasi manual di Midtrans Dashboard (tidak bisa lewat
// API/secrets): Settings > Configuration > Payment Notification URL, untuk
// sandbox dan production terpisah. Midtrans mengirim SEMUA notifikasi ke satu
// URL itu, bukan per-transaksi seperti urlParams pada SNAP BI.

export type PaymentEnv = "sandbox" | "production";

export interface GatewayConfig {
  env: PaymentEnv;
  provider: string;
  snapBaseUrl: string;
  apiBaseUrl: string;
  serverKey: string;
  returnUrl: string;
}

export class PaymentError extends Error {
  constructor(
    message: string,
    public code = "PAYMENT_ERROR",
    public status = 400,
    public detail: unknown = null,
  ) {
    super(message);
    this.name = "PaymentError";
  }
}

function env(key: string, fallback = ""): string {
  const v = Deno.env.get(key);
  return v === undefined || v === null || v === "" ? fallback : v;
}

function requireEnv(key: string): string {
  const v = env(key);
  if (!v)
    throw new PaymentError(
      `Konfigurasi ${key} belum diisi.`,
      "CONFIG_MISSING",
      500,
    );
  return v;
}

export function getGatewayConfig(): GatewayConfig {
  const mode: PaymentEnv =
    env("PAYMENT_ENV", "sandbox") === "production" ? "production" : "sandbox";

  return {
    env: mode,
    provider: "midtrans",
    snapBaseUrl:
      mode === "production"
        ? "https://app.midtrans.com/snap/v1"
        : "https://app.sandbox.midtrans.com/snap/v1",
    apiBaseUrl:
      mode === "production"
        ? "https://api.midtrans.com/v2"
        : "https://api.sandbox.midtrans.com/v2",
    serverKey: requireEnv("MIDTRANS_SERVER_KEY"),
    returnUrl: env("PAYMENT_RETURN_URL", ""),
  };
}

function basicAuthHeader(serverKey: string): string {
  // Username = Server Key, password kosong: "serverKey:".
  return `Basic ${btoa(`${serverKey}:`)}`;
}

async function sha512Hex(input: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-512",
    new TextEncoder().encode(input),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function midtransFetch(
  cfg: GatewayConfig,
  url: string,
  init: RequestInit,
): Promise<{ ok: boolean; status: number; body: Record<string, unknown> }> {
  const res = await fetch(url, {
    ...init,
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      Authorization: basicAuthHeader(cfg.serverKey),
      ...(init.headers ?? {}),
    },
  });

  const text = await res.text();
  let json: Record<string, unknown> = {};
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    throw new PaymentError(
      "Respons Midtrans tidak valid.",
      "GATEWAY_ERROR",
      502,
      text,
    );
  }

  if (Deno.env.get("PAYMENT_DEBUG") === "true") {
    console.log("midtrans-request-debug", {
      url,
      status: res.status,
      statusCode: json.status_code,
      statusMessage: json.status_message,
    });
  }

  return { ok: res.ok, status: res.status, body: json };
}

// ---------------------------------------------------------------------------
// Create transaction (Snap)
// ---------------------------------------------------------------------------

export interface CreateOrderInput {
  partnerReferenceNo: string; // dipakai sebagai order_id
  amount: number;
  orderTitle: string;
  validMinutes?: number;
  returnUrl?: string;
}

export interface CreateOrderResult {
  token: string | null;
  checkoutUrl: string | null;
  expiresAt: string;
  raw: Record<string, unknown>;
}

export async function createOrder(
  cfg: GatewayConfig,
  input: CreateOrderInput,
): Promise<CreateOrderResult> {
  const validMinutes = input.validMinutes ?? 60;
  const finish = input.returnUrl || cfg.returnUrl;

  const body: Record<string, unknown> = {
    transaction_details: {
      order_id: input.partnerReferenceNo,
      // Midtrans mewajibkan gross_amount berupa bilangan bulat (rupiah).
      gross_amount: Math.round(input.amount),
    },
    item_details: [
      {
        id: "subscription",
        name: input.orderTitle.slice(0, 50),
        price: Math.round(input.amount),
        quantity: 1,
      },
    ],
    expiry: { unit: "minute", duration: validMinutes },
    ...(finish ? { callbacks: { finish } } : {}),
  };

  const res = await midtransFetch(cfg, `${cfg.snapBaseUrl}/transactions`, {
    method: "POST",
    body: JSON.stringify(body),
  });

  if (!res.ok || !res.body.token) {
    throw new PaymentError(
      String(
        res.body.status_message ?? "Gateway menolak permintaan pembayaran.",
      ),
      String(res.body.status_code ?? res.status),
      502,
      res.body,
    );
  }

  return {
    token: (res.body.token as string) ?? null,
    checkoutUrl: (res.body.redirect_url as string) ?? null,
    expiresAt: new Date(Date.now() + validMinutes * 60 * 1000).toISOString(),
    raw: res.body,
  };
}

// ---------------------------------------------------------------------------
// Query status (inquiry langsung, tidak butuh verifikasi signature —
// otentikasinya sudah lewat Basic Auth + HTTPS pada permintaan ini).
// ---------------------------------------------------------------------------

export type OrderStatus =
  | "pending"
  | "paid"
  | "failed"
  | "expired"
  | "cancelled"
  | "refunded";

export interface QueryOrderResult {
  status: OrderStatus;
  gatewayStatus: string;
  transactionId: string | null;
  paidAt: string | null;
  raw: Record<string, unknown>;
}

export async function queryOrder(
  cfg: GatewayConfig,
  params: { partnerReferenceNo: string },
): Promise<QueryOrderResult> {
  const res = await midtransFetch(
    cfg,
    `${cfg.apiBaseUrl}/${encodeURIComponent(params.partnerReferenceNo)}/status`,
    { method: "GET" },
  );

  // 404 dari Midtrans berarti transaksi belum pernah dibayar sama sekali —
  // bukan error, cukup dianggap masih pending.
  if (res.status === 404) {
    return {
      status: "pending",
      gatewayStatus: "not_found",
      transactionId: null,
      paidAt: null,
      raw: res.body,
    };
  }

  if (!res.ok) {
    throw new PaymentError(
      String(
        res.body.status_message ?? "Status pembayaran tidak dapat diperiksa.",
      ),
      String(res.body.status_code ?? res.status),
      502,
      res.body,
    );
  }

  const transactionStatus = String(res.body.transaction_status ?? "");
  const fraudStatus = String(res.body.fraud_status ?? "");

  return {
    status: normalizeStatus(transactionStatus, fraudStatus),
    gatewayStatus: transactionStatus,
    transactionId: (res.body.transaction_id as string) ?? null,
    paidAt:
      (res.body.settlement_time as string) ??
      (res.body.transaction_time as string) ??
      null,
    raw: res.body,
  };
}

/**
 * Peta status Midtrans -> status internal.
 * capture: hasil kartu kredit, perlu cek fraud_status (accept/challenge/deny).
 * settlement: pembayaran non-kartu (VA, e-wallet, dst) sudah lunas.
 */
export function normalizeStatus(
  transactionStatus: string,
  fraudStatus = "",
): OrderStatus {
  const status = transactionStatus.toLowerCase();
  const fraud = fraudStatus.toLowerCase();

  if (status === "capture") {
    if (fraud === "accept") return "paid";
    if (fraud === "deny") return "failed";
    return "pending"; // challenge — menunggu review manual
  }
  if (status === "settlement") return "paid";
  if (status === "pending" || status === "authorize") return "pending";
  if (status === "deny") return "failed";
  if (status === "cancel") return "cancelled";
  if (status === "expire") return "expired";
  if (status === "refund" || status === "partial_refund") return "refunded";
  return "pending";
}

// ---------------------------------------------------------------------------
// Verifikasi webhook (HTTP notification)
// ---------------------------------------------------------------------------

/**
 * signature_key = SHA512(order_id + status_code + gross_amount + ServerKey)
 * Dihitung dari field yang ADA di body notifikasi itu sendiri (bukan dari
 * data kita), lalu dibandingkan dengan field signature_key yang dikirim.
 */
export async function verifyWebhookSignature(params: {
  cfg: GatewayConfig;
  payload: Record<string, unknown>;
}): Promise<boolean> {
  const { payload, cfg } = params;
  const signatureKey = String(payload.signature_key ?? "");
  if (!signatureKey) return false;

  const orderId = String(payload.order_id ?? "");
  const statusCode = String(payload.status_code ?? "");
  const grossAmount = String(payload.gross_amount ?? "");
  if (!orderId || !statusCode || !grossAmount) return false;

  const expected = await sha512Hex(
    orderId + statusCode + grossAmount + cfg.serverKey,
  );
  return timingSafeEqual(expected, signatureKey.toLowerCase());
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}
