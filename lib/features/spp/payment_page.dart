import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/card_print_host.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/app_dialog.dart';
import 'payment_confirmation_dialog.dart';
import 'spp_data.dart';
import 'spp_page.dart';

class PaymentPage extends ConsumerStatefulWidget {
  const PaymentPage({super.key, required this.id});
  final String id;
  @override
  ConsumerState<PaymentPage> createState() => _PaymentPageState();
}

class _PaymentPageState extends ConsumerState<PaymentPage> {
  Timer? timer;
  final host = CardPrintHost();
  bool printing = false;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    unawaited(host.close());
    super.dispose();
  }

  Future<void> report(AppStore s, Entity p, Entity? invoice) async {
    final data = await showPaymentConfirmationDialog(
      context,
      payment: p,
      invoice: invoice,
      initialPayerName: s.user?.name ?? '',
    );
    if (data == null || !mounted) return;
    await runAction(context, s, () async {
      final proofPath = await s.repository.uploadPaymentProof(
        tenantId: p.tenantId,
        paymentId: p.id,
        bytes: data.proof.bytes,
        contentType: data.proof.contentType,
      );
      await s.repository.billingAction('report', {
        'id': p.id,
        'payer_name': data.payerName,
        'proof_path': proofPath,
      });
    }, success: 'Konfirmasi dan bukti pembayaran berhasil dikirim.');
  }

  Future<void> openProof(AppStore s, Entity p) async {
    try {
      final bytes = await s.repository.downloadPrivateFile(
        'spp-proofs',
        p.text('proof_path'),
      );
      if (bytes == null) throw const AppFailure('Bukti belum tersedia.');
      if (!mounted) return;
      await showAppDialog<void>(
        context,
        builder: (c) => AppDialog(
          title: 'Bukti pembayaran',
          subtitle: 'Bukti yang dikirim oleh pembayar.',
          icon: Icons.receipt_long_outlined,
          onClose: () => Navigator.pop(c),
          body: Padding(
            padding: const EdgeInsets.all(18),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          ),
          footer: DialogActions(
            label: 'Tutup',
            cancelLabel: 'Kembali',
            icon: Icons.close_rounded,
            onCancel: () => Navigator.pop(c),
            onConfirm: () => Navigator.pop(c),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Future<void> approve(AppStore s, Entity p) async {
    final confirmed = await confirmAction(
      context,
      title: 'Setujui pembayaran?',
      message:
          'Pastikan bukti pembayaran sesuai dengan siswa, tagihan, dan nominal yang tercantum.',
      confirmLabel: 'Setujui',
      icon: Icons.verified_outlined,
    );
    if (confirmed != true || !mounted) return;
    await runAction(
      context,
      s,
      () => s.repository.billingAction('approve', {'id': p.id}),
      success: 'Pembayaran berhasil disetujui.',
    );
  }

  Future<void> export(Entity p) async {
    if (printing) return;
    setState(() => printing = true);
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.white, BlendMode.src);
      canvas.translate(64, 64);
      QrPainter(
        data: p.text('payload'),
        version: QrVersions.auto,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Colors.black,
        ),
      ).paint(canvas, const Size(640, 640));
      final picture = recorder.endRecording();
      final image = await picture.toImage(768, 768);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      if (bytes == null) throw const AppFailure('QR belum dapat disiapkan.');
      final png = base64Encode(bytes.buffer.asUint8List());
      String esc(String value) => const HtmlEscape().convert(value);
      final url = await host.prepare(
        '''<!doctype html><html lang="id"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>QRIS SPP</title><style>body{font:15px Arial;color:#183e35;margin:24px;text-align:center}.card{max-width:430px;margin:auto;padding:24px;border:1px solid #ddd;border-radius:16px}img{width:78mm;max-width:100%;display:block;margin:16px auto}p{line-height:1.5;overflow-wrap:anywhere}button,a{display:inline-block;padding:12px;margin:8px;color:white;background:#17665b;border:0;border-radius:8px;text-decoration:none}@page{size:A4;margin:15mm}@media print{body{margin:0;min-height:266mm;display:flex;align-items:center;justify-content:center}.actions{display:none}.card{margin:0;width:105mm}}</style>
<div class="card"><h2>Pembayaran SPP</h2><p>${esc(p.text('merchant_name'))}</p><h1>${esc(rupiah(p.number('amount')))}</h1><img src="data:image/png;base64,$png" alt="QRIS pembayaran"><p>Sesi aplikasi: ${esc(p.text('expires_at'))}<br>ID: ${esc(p.id)}</p><p>Periksa nama merchant dan nominal di aplikasi bank. QR yang diunduh tidak otomatis dibatalkan oleh timer aplikasi. Jangan membayar ulang jika sudah berhasil. Ini bukan bukti pembayaran.</p><div class="actions"><a download="QRIS-${esc(p.id)}.png" href="data:image/png;base64,$png">Unduh QRIS PNG</a><button onclick="window.print()">Cetak / Simpan PDF</button></div></div></html>''',
      );
      if (!mounted) return;
      setState(() => printing = false);
      await showAppDialog<void>(
        context,
        builder: (c) => AppDialog(
          title: 'Unduh / cetak QRIS',
          subtitle: 'QR ditempatkan di tengah halaman A4.',
          icon: Icons.print_outlined,
          onClose: () => Navigator.pop(c),
          body: const Padding(
            padding: EdgeInsets.all(22),
            child: Text(
              'Buka halaman QRIS di browser untuk mengunduh PNG atau memilih Cetak / Simpan PDF. Biarkan aplikasi terbuka di latar belakang sampai halaman dimuat. Unduhan bukan bukti pembayaran.',
            ),
          ),
          footer: DialogActions(
            label: 'Buka QRIS',
            cancelLabel: 'Tutup',
            onCancel: () => Navigator.pop(c),
            onConfirm: () async {
              try {
                if (kIsWeb) {
                  host.openBrowser(url);
                } else if (!await launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                )) {
                  throw const AppFailure('Browser tidak tersedia.');
                }
              } catch (e) {
                if (c.mounted) {
                  ScaffoldMessenger.of(
                    c,
                  ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
                }
              }
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final p = s.entity(widget.id);
    if (p == null || p.kind != 'spp_payment') {
      return const PageFrame(
        title: 'Pembayaran',
        children: [
          EmptyState(
            'Transaksi belum tersedia',
            message:
                'Tarik layar untuk memperbarui. Pastikan Anda menggunakan akun yang benar.',
          ),
        ],
      );
    }
    final pending = p.text('status') == 'pending';
    final seconds = (DateTime.parse(
      p.text('expires_at'),
    ).difference(DateTime.now()).inSeconds).clamp(0, 300);
    final i = s.entity(p.text('invoice_id'));
    return PageFrame(
      title: 'Detail pembayaran',
      subtitle: '${i?.text('title') ?? 'SPP'} • ${i?.text('period') ?? ''}',
      children: [
        Center(
          child: Column(
            children: [
              Text(
                rupiah(p.number('amount')),
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(
                paymentLabels[p.text('status')] ?? p.text('status'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              if (pending && seconds > 0) ...[
                Text(
                  'Sesi pembayaran ${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: QrImageView(
                    data: p.text('payload'),
                    size: 260,
                    padding: const EdgeInsets.all(18),
                    backgroundColor: Colors.white,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Penerima: ${p.text('merchant_name')}',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (pending && s.role == UserRole.student) ...[
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: s.busy ? null : () => report(s, p, i),
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Konfirmasi pembayaran'),
          ),
          if (seconds > 0) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: printing ? null : () => export(p),
              icon: const Icon(Icons.download_outlined),
              label: Text(printing ? 'Menyiapkan…' : 'Unduh QRIS / Simpan PDF'),
            ),
          ],
        ],
        if (!pending) ...[
          const SizedBox(height: 16),
          if (p.text('payer_name').isNotEmpty)
            Text('Nama pembayar: ${p.text('payer_name')}'),
          if (p.text('proof_path').isNotEmpty) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => openProof(s, p),
              icon: const Icon(Icons.image_outlined),
              label: const Text('Lihat bukti pembayaran'),
            ),
          ],
          if (p.text('review_note').isNotEmpty)
            Text('Catatan pengelola: ${p.text('review_note')}'),
        ],
        if (s.isManager && p.text('status') == 'reported') ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: s.busy ? null : () => approve(s, p),
            icon: const Icon(Icons.verified_outlined),
            label: const Text('Setujui pembayaran'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => contactWali(
              context,
              s,
              p.text('student_id'),
              'Mohon klarifikasi pembayaran ${i?.text('title') ?? 'SPP'} sebesar ${rupiah(p.number('amount'))}. Referensi aplikasi: ${p.id}.',
            ),
            icon: const Icon(Icons.chat_outlined),
            label: const Text('WhatsApp wali'),
          ),
        ] else if (p.text('contact_phone').isNotEmpty) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () async {
              try {
                final url = whatsappLink(
                  p.text('contact_phone'),
                  'Mohon bantuan transaksi SPP ${p.id}, nominal ${rupiah(p.number('amount'))}.',
                );
                if (!await launchUrl(
                  Uri.parse(url),
                  mode: LaunchMode.externalApplication,
                )) {
                  throw const AppFailure('Browser tidak tersedia.');
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
                }
              }
            },
            icon: const Icon(Icons.support_agent_outlined),
            label: const Text('Hubungi pengelola'),
          ),
        ],
        const SizedBox(height: 20),
        SelectableText(
          'ID transaksi: ${p.id}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Text(
          'Dibuat: ${p.createdAt.toLocal()}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
