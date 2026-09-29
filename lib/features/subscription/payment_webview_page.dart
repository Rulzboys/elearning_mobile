import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/config/app_config.dart';

/// Hasil dari halaman pembayaran in-app.
///
/// Ini BUKAN status pembayaran. Halaman ini hanya melaporkan apakah alur
/// Snap sudah dituntaskan atau ditutup pengguna; status sebenarnya tetap
/// ditanyakan ke server sesudahnya (webhook adalah sumber kebenaran).
enum PaymentFlowResult { finished, closed }

class PaymentWebViewPage extends StatefulWidget {
  const PaymentWebViewPage({super.key, required this.checkoutUrl});

  final String checkoutUrl;

  @override
  State<PaymentWebViewPage> createState() => _PaymentWebViewPageState();
}

class _PaymentWebViewPageState extends State<PaymentWebViewPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _closing = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) {
              setState(() {
                _loading = true;
                _loadError = null;
              });
            }
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (error) {
            // Abaikan error sub-resource (gambar/iframe) agar tidak
            // menutupi halaman yang sebenarnya tampil normal.
            if (!error.isForMainFrame.orTrue) return;
            if (mounted) {
              setState(() {
                _loading = false;
                _loadError =
                    'Halaman pembayaran gagal dimuat. '
                    'Periksa koneksi internet Anda, lalu coba lagi.';
              });
            }
          },
          onNavigationRequest: _onNavigation,
        ),
      )
      ..loadRequest(Uri.parse(widget.checkoutUrl));
  }

  Future<NavigationDecision> _onNavigation(NavigationRequest request) async {
    final url = request.url;

    // 1. Snap mengarahkan ke callbacks.finish -> alur pembayaran selesai.
    final isFinish = AppConfig.paymentFinishUrls.any(
      (u) => u.isNotEmpty && url.startsWith(u),
    );
    if (isFinish) {
      _close(PaymentFlowResult.finished);
      return NavigationDecision.prevent;
    }

    final uri = Uri.tryParse(url);
    if (uri == null) return NavigationDecision.prevent;

    // 2. intent:// milik Android -> ubah ke deeplink asli atau fallback web.
    if (uri.scheme == 'intent') {
      final resolved = _resolveIntentUrl(url);
      if (resolved != null) await _openExternal(resolved);
      return NavigationDecision.prevent;
    }

    // 3. Skema non-http (gojek://, shopeeid://, dana://, dst) tidak bisa
    //    ditangani WebView -> lempar ke aplikasi terkait. Pengguna kembali
    //    ke halaman ini setelahnya dan status dicek ulang.
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      await _openExternal(uri);
      return NavigationDecision.prevent;
    }

    return NavigationDecision.navigate;
  }

  /// Format: intent://host/path#Intent;scheme=gojek;S.browser_fallback_url=...;end
  Uri? _resolveIntentUrl(String url) {
    final fallback = RegExp(r'S\.browser_fallback_url=([^;]+)').firstMatch(url);
    if (fallback != null) {
      return Uri.tryParse(Uri.decodeComponent(fallback.group(1)!));
    }

    final scheme = RegExp(r'scheme=([^;]+)').firstMatch(url)?.group(1);
    final hashIndex = url.indexOf('#Intent');
    if (scheme != null && hashIndex > 'intent://'.length) {
      final rest = url.substring('intent://'.length, hashIndex);
      return Uri.tryParse('$scheme://$rest');
    }
    return null;
  }

  Future<void> _openExternal(Uri uri) async {
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) _notifyAppMissing();
    } catch (_) {
      if (mounted) _notifyAppMissing();
    }
  }

  void _notifyAppMissing() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Aplikasi pembayaran tidak ditemukan di perangkat ini. '
          'Silakan pilih metode pembayaran lain.',
        ),
      ),
    );
  }

  void _close(PaymentFlowResult result) {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop(result);
  }

  Future<void> _confirmExit() async {
    if (!mounted) return;
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tutup halaman pembayaran?'),
        content: const Text(
          'Pembayaran belum selesai. Anda tetap bisa melanjutkannya nanti '
          'lewat riwayat transaksi selama pesanan belum kedaluwarsa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Lanjutkan bayar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
    if (leave == true) _close(PaymentFlowResult.closed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // Kembalikan pengguna ke langkah sebelumnya di Snap lebih dulu.
        if (await _controller.canGoBack()) {
          await _controller.goBack();
          return;
        }
        await _confirmExit();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pembayaran'),
          leading: IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: 'Tutup',
            onPressed: _confirmExit,
          ),
          bottom: _loading
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(3),
                  child: LinearProgressIndicator(minHeight: 3),
                )
              : null,
        ),
        body: SafeArea(
          child: _loadError != null
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.wifi_off_rounded,
                        size: 48,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(_loadError!, textAlign: TextAlign.center),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: () => _controller.reload(),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Coba lagi'),
                      ),
                    ],
                  ),
                )
              : WebViewWidget(controller: _controller),
        ),
      ),
    );
  }
}

extension on bool? {
  bool get orTrue => this ?? true;
}
