class AppConfig {
  static const mode = String.fromEnvironment('APP_MODE', defaultValue: 'demo');
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Lingkungan payment gateway: 'sandbox' atau 'production'.
  /// Kredensial gateway TIDAK pernah disimpan di aplikasi — nilainya hanya
  /// dipakai untuk menampilkan penanda sandbox di layar pembayaran.
  static const paymentMode = String.fromEnvironment(
    'PAYMENT_MODE',
    defaultValue: 'sandbox',
  );

  /// Deeplink tujuan setelah pengguna selesai membayar di halaman gateway.
  /// Skema harus sama dengan yang terdaftar di AndroidManifest.xml/Info.plist.
  /// Harus persis sama dengan secret PAYMENT_RETURN_URL di Supabase
  /// (dikirim ke Snap sebagai callbacks.finish). Gunakan URL https statis,
  /// bukan deeplink custom: halamannya tidak pernah benar-benar dibuka,
  /// hanya dicegat oleh WebView sebagai penanda alur selesai.
  static const String paymentReturnUrl = String.fromEnvironment(
    'PAYMENT_RETURN_URL',
    defaultValue: 'https://payment.rulz.id/finish',
  );

  /// Semua URL yang menandakan alur pembayaran Snap sudah selesai/ditutup.
  static const List<String> paymentFinishUrls = [
    paymentReturnUrl,
    'https://app.midtrans.com/snap/v4/redirection/finish',
    'https://app.midtrans.com/snap/v4/redirection/error',
    'https://app.midtrans.com/snap/v4/redirection/unfinish',
    'https://app.sandbox.midtrans.com/snap/v4/redirection/finish',
    'https://app.sandbox.midtrans.com/snap/v4/redirection/error',
    'https://app.sandbox.midtrans.com/snap/v4/redirection/unfinish',
  ];

  /// Nama Edge Function pembayaran langganan.
  static const fnCreatePayment = 'subscription-create-payment';
  static const fnPaymentStatus = 'subscription-payment-status';

  /// Jeda dan batas waktu polling status pembayaran.
  static const paymentPollInterval = Duration(seconds: 3);
  static const paymentPollTimeout = Duration(minutes: 5);

  static bool get isDemo => mode == 'demo';
  static bool get isPaymentSandbox => paymentMode != 'production';

  static void validate() {
    if (!['demo', 'supabase'].contains(mode)) {
      throw StateError('APP_MODE harus demo atau supabase.');
    }
    if (!['sandbox', 'production'].contains(paymentMode)) {
      throw StateError('PAYMENT_MODE harus sandbox atau production.');
    }
    if (!isDemo &&
        (!url.startsWith('https://') ||
            anonKey.isEmpty ||
            url.contains('YOUR_PROJECT') ||
            anonKey.startsWith('YOUR_'))) {
      throw StateError('Isi SUPABASE_URL dan SUPABASE_ANON_KEY pada env.json.');
    }
    if (!isDemo && !paymentReturnUrl.contains('://')) {
      throw StateError('PAYMENT_RETURN_URL harus berupa deeplink yang valid.');
    }
  }
}
