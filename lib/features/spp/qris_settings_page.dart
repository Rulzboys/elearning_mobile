import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/services/scan_feedback.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/edit_dialog.dart';
import '../../shared/widgets/app_dialog.dart';
import 'qris_payload.dart';

class QrisSettingsPage extends ConsumerWidget {
  const QrisSettingsPage({super.key});
  Future<void> edit(BuildContext context, AppStore s, {String? scanned}) async {
    final current = s.items('qris_setting').firstOrNull;
    await editDialog(
      context,
      s,
      title: 'Pengaturan QRIS instansi',
      initial: {
        'payload': scanned ?? current?.text('payload') ?? '',
        'enabled': current?.data['enabled'] == true ? 'true' : 'false',
        'nominal_enabled': current?.data['nominal_enabled'] == true
            ? 'true'
            : 'false',
        'contact_phone':
            current?.text('contact_phone') ?? s.tenant?.contact ?? '',
      },
      fields: const [
        FieldSpec(
          'payload',
          'Data QRIS pembayaran',
          lines: 4,
          hint: 'Hasil scan QRIS yang akan digunakan, bukan URL gambar',
        ),
        FieldSpec(
          'contact_phone',
          'WhatsApp bendahara/pengelola',
          hint: '08… atau 628…',
        ),
        FieldSpec(
          'enabled',
          'Penerimaan pembayaran',
          options: {'false': 'Nonaktif', 'true': 'Aktif'},
        ),
        FieldSpec(
          'nominal_enabled',
          'Mode QRIS',
          options: {
            'false': 'Statis (nominal diisi di aplikasi bank)',
            'true': 'Nominal otomatis (dukungan penyedia wajib diuji)',
          },
        ),
      ],
      onSave: (d) async {
        final name = QrisPayload.validateStatic(d['payload'] as String);
        final ok = await confirmAction(
          context,
          title: 'Gunakan QRIS ini?',
          message:
              'Penerima pada QR: $name. Pastikan Anda berwenang menggunakan merchant ini untuk SPP instansi. Mode nominal hanya boleh diaktifkan jika didukung penyedia dan sudah diuji. Aplikasi tidak memverifikasi dana masuk secara otomatis.',
          confirmLabel: 'Simpan QRIS',
          icon: Icons.qr_code_rounded,
        );
        if (!ok) throw const AppFailure('Pengaturan belum disimpan.');
        await s.repository.billingAction('settings', {
          ...d,
          'consent': true,
          'enabled': d['enabled'] == 'true',
          'nominal_enabled': d['nominal_enabled'] == 'true',
        });
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    if (!s.isManager) {
      return const PageFrame(
        title: 'Pengaturan QRIS',
        children: [EmptyState('Pengaturan QRIS tidak dapat diakses')],
      );
    }
    final q = s.items('qris_setting').firstOrNull;
    return PageFrame(
      title: 'Pengaturan QRIS',
      subtitle: s.tenant?.name,
      children: [
        if (q != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    q.text('merchant_name'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  QrImageView(
                    data: q.text('payload'),
                    size: 240,
                    backgroundColor: Colors.white,
                    padding: const EdgeInsets.all(18),
                  ),
                  Text(
                    q.data['enabled'] == true
                        ? 'Penerimaan aktif'
                        : 'Penerimaan nonaktif',
                  ),
                  Text(
                    q.data['nominal_enabled'] == true
                        ? 'Mode nominal otomatis'
                        : 'Mode statis',
                  ),
                ],
              ),
            ),
          ),
        if (q == null)
          const EmptyState(
            'QRIS belum diatur',
            message:
                'Scan QRIS pembayaran atau tempel data hasil scan untuk memulai.',
          ),
        FilledButton.icon(
          onPressed: s.busy
              ? null
              : () async {
                  final raw = await Navigator.of(context).push<String>(
                    MaterialPageRoute(
                      builder: (_) => const MerchantQrScanner(),
                    ),
                  );
                  if (raw != null && context.mounted) {
                    await edit(context, s, scanned: raw);
                  }
                },
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan QRIS yang akan digunakan'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: s.busy ? null : () => edit(context, s),
          icon: const Icon(Icons.settings_outlined),
          label: const Text('Atur / tempel data QRIS'),
        ),
      ],
    );
  }
}

class MerchantQrScanner extends StatefulWidget {
  const MerchantQrScanner({super.key});
  @override
  State<MerchantQrScanner> createState() => _MerchantQrScannerState();
}

class _MerchantQrScannerState extends State<MerchantQrScanner> {
  final controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  final feedback = ScanFeedback();
  bool handling = false;
  String? error;
  @override
  void dispose() {
    unawaited(controller.dispose());
    unawaited(feedback.dispose());
    super.dispose();
  }

  Future<void> detect(BarcodeCapture capture) async {
    if (handling) return;
    final raw = capture.barcodes.firstOrNull?.rawValue?.trim();
    if (raw == null || raw.isEmpty) return;
    handling = true;
    try {
      QrisPayload.validateStatic(raw);
      await controller.stop();
      await feedback.success();
      if (mounted) Navigator.of(context).pop(raw);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
      await Future<void>.delayed(const Duration(seconds: 2));
      handling = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(title: const Text('Scan QRIS pembayaran')),
    body: Stack(
      fit: StackFit.expand,
      children: [
        MobileScanner(controller: controller, onDetect: detect),
        Center(
          child: Container(
            width: 270,
            height: 270,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 3),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        Positioned(
          bottom: 30,
          left: 20,
          right: 20,
          child: SafeArea(
            child: Column(
              children: [
                Text(
                  error ?? 'Arahkan kamera ke QRIS yang akan digunakan',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    backgroundColor: Colors.black87,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => controller.toggleTorch(),
                  icon: const Icon(Icons.flashlight_on),
                  label: const Text('Lampu'),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
