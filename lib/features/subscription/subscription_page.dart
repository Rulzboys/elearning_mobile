import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/config/app_config.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/widgets/common.dart';
import '../spp/spp_data.dart';
import 'payment_webview_page.dart';

String subscriptionStatusLabel(String status) => switch (status) {
  'paid' => 'Pembayaran berhasil',
  'failed' => 'Pembayaran gagal',
  'expired' => 'Pembayaran kedaluwarsa',
  'cancelled' => 'Pembayaran dibatalkan',
  'refunded' => 'Pembayaran dikembalikan',
  _ => 'Menunggu pembayaran',
};

class SubscriptionPage extends ConsumerWidget {
  const SubscriptionPage({super.key});

  Future<void> _checkout(BuildContext context, AppStore s, String plan) async {
    Json? order;
    final created = await runAction(context, s, () async {
      order = await s.repository.subscriptionCheckout(plan);
    }, success: null);
    if (!created || order == null || !context.mounted) return;

    final orderId = order!['id'].toString();
    final checkoutUrl = order!['checkout_url']?.toString() ?? '';

    if (checkoutUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Pesanan tersimpan. Halaman pembayaran akan tersedia setelah payment gateway diaktifkan.',
          ),
        ),
      );
      return;
    }

    // Mode demo tidak memanggil gateway mana pun, jadi tidak ada yang dibuka.
    if (!AppConfig.isDemo) {
      await Navigator.of(context).push<PaymentFlowResult>(
        MaterialPageRoute(
          builder: (_) => PaymentWebViewPage(checkoutUrl: checkoutUrl),
          fullscreenDialog: true,
        ),
      );
      if (!context.mounted) return;
    }

    await _finalize(context, s, orderId);
  }

  /// Verifikasi status ke server lalu tampilkan hasilnya. Dipakai baik setelah
  /// checkout baru maupun saat melanjutkan pesanan yang masih pending.
  Future<void> _finalize(
    BuildContext context,
    AppStore s,
    String orderId,
  ) async {
    final status = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PaymentWaitDialog(store: s, orderId: orderId),
    );
    if (!context.mounted) return;

    // Muat ulang snapshot agar riwayat transaksi dan status langganan ikut segar.
    await runAction(context, s, () async {}, success: null);
    if (!context.mounted) return;

    if (status == 'paid') {
      await showDialog<void>(
        context: context,
        builder: (_) => const _PaymentSuccessDialog(),
      );
      return;
    }
    if (status != null && status != 'pending') {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(subscriptionStatusLabel(status))));
    }
  }

  Future<void> _resume(BuildContext context, AppStore s, String orderId) =>
      _finalize(context, s, orderId);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final config = s.items('subscription_setting').firstOrNull;
    final monthly = config?.number('monthly_price', 10000) ?? 10000;
    final annual = config?.number('annual_price', 100000) ?? 100000;
    final normalAnnual = monthly * 12;
    final orders = s.items('subscription_order');
    return PageFrame(
      title: 'Langganan aplikasi',
      subtitle: 'Pilih masa langganan yang sesuai.',
      children: [
        if (AppConfig.isPaymentSandbox && !AppConfig.isDemo)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
          ),
        _PlanCard(
          title: 'Paket Bulanan',
          period: '1 bulan',
          price: monthly,
          description: 'Akses aplikasi selama satu bulan.',
          onChoose: s.role == UserRole.student
              ? () => _checkout(context, s, 'monthly')
              : null,
        ),
        _PlanCard(
          title: 'Paket Tahunan',
          period: '1 tahun',
          price: annual,
          regularPrice: normalAnnual,
          badge: 'Hemat ${rupiah(normalAnnual - annual)}',
          description: 'Akses selama satu tahun dengan harga lebih hemat.',
          onChoose: s.role == UserRole.student
              ? () => _checkout(context, s, 'annual')
              : null,
        ),
        const SizedBox(height: 8),
        Text(
          'Riwayat pembayaran',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (orders.isEmpty) const EmptyState('Belum ada transaksi langganan'),
        for (final order in orders)
          DataTile(
            title: order.text('plan') == 'annual'
                ? 'Langganan 1 tahun'
                : 'Langganan 1 bulan',
            subtitle:
                '${rupiah(order.number('amount'))} • ${subscriptionStatusLabel(order.text('status'))}',
            icon: switch (order.text('status')) {
              'paid' => Icons.verified_outlined,
              'failed' || 'cancelled' => Icons.cancel_outlined,
              'expired' => Icons.timer_off_outlined,
              'refunded' => Icons.undo_outlined,
              _ => Icons.schedule_outlined,
            },
            onTap: order.text('status') == 'pending'
                ? () => _resume(context, s, order.id)
                : null,
          ),
      ],
    );
  }
}

/// Menunggu konfirmasi pembayaran dengan memeriksa status ke gateway
/// secara berkala. Webhook tetap menjadi sumber kebenaran utama; polling
/// hanya mempercepat pembaruan tampilan.
class _PaymentWaitDialog extends StatefulWidget {
  const _PaymentWaitDialog({required this.store, required this.orderId});
  final AppStore store;
  final String orderId;

  @override
  State<_PaymentWaitDialog> createState() => _PaymentWaitDialogState();
}

class _PaymentWaitDialogState extends State<_PaymentWaitDialog>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _busy = false;
  bool _timedOut = false;
  String? _error;
  late final DateTime _deadline;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _deadline = DateTime.now().add(AppConfig.paymentPollTimeout);
    _timer = Timer.periodic(AppConfig.paymentPollInterval, (_) => _check());
    _check();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Pengguna kembali dari aplikasi e-wallet/m-banking — periksa segera.
    if (state == AppLifecycleState.resumed) _check(force: true);
  }

  Future<void> _check({bool force = false}) async {
    if (_busy || !mounted) return;
    if (DateTime.now().isAfter(_deadline) && !force) {
      _timer?.cancel();
      if (mounted) setState(() => _timedOut = true);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final order = await widget.store.repository.subscriptionPaymentStatus(
        widget.orderId,
      );
      final status = order['status']?.toString() ?? 'pending';
      if (!mounted) return;
      if (status != 'pending') {
        _timer?.cancel();
        Navigator.of(context).pop(status);
        return;
      }
    } on AppFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Status pembayaran belum dapat diperiksa.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(_timedOut ? 'Belum ada konfirmasi' : 'Memverifikasi pembayaran'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: _timedOut
                    ? Icon(
                        Icons.timer_outlined,
                        color: theme.colorScheme.outline,
                      )
                    : const CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  _timedOut
                      ? 'Konfirmasi dari penyedia pembayaran belum masuk. Jika pembayaran sudah selesai, status akan diperbarui otomatis.'
                      : 'Mohon tunggu sebentar, kami sedang memastikan pembayaran Anda diterima.',
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('pending'),
          child: const Text('Nanti saja'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _check(force: true),
          child: const Text('Cek sekarang'),
        ),
      ],
    );
  }
}

class _PaymentSuccessDialog extends StatelessWidget {
  const _PaymentSuccessDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(
        Icons.check_circle_rounded,
        size: 56,
        color: theme.colorScheme.primary,
      ),
      title: const Text('Pembayaran berhasil'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Terima kasih! Langganan Anda sudah aktif dan seluruh fitur '
            'aplikasi bisa langsung digunakan.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 10),
          Text(
            'Bukti pembayaran tersimpan di riwayat transaksi.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Mulai gunakan'),
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.title,
    required this.period,
    required this.price,
    required this.description,
    this.regularPrice,
    this.badge,
    this.onChoose,
  });
  final String title, period, description;
  final int price;
  final int? regularPrice;
  final String? badge;
  final VoidCallback? onChoose;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (badge != null) StatusPill(badge!, positive: true),
            ],
          ),
          const SizedBox(height: 14),
          if (regularPrice != null && regularPrice! > price)
            Text(
              rupiah(regularPrice!),
              style: const TextStyle(
                color: Colors.grey,
                decoration: TextDecoration.lineThrough,
              ),
            ),
          Text(
            rupiah(price),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
          ),
          Text('/ $period'),
          const SizedBox(height: 12),
          Text(description),
          if (onChoose != null) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: onChoose,
              icon: const Icon(Icons.payment_rounded),
              label: const Text('Lanjut ke pembayaran'),
            ),
          ],
        ],
      ),
    ),
  );
}