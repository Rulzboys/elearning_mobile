import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../../core/services/private_image_picker.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/common.dart';
import 'spp_data.dart';

class PaymentConfirmationData {
  const PaymentConfirmationData({required this.payerName, required this.proof});

  final String payerName;
  final PrivateImageUpload proof;
}

Future<PaymentConfirmationData?> showPaymentConfirmationDialog(
  BuildContext context, {
  required Entity payment,
  required Entity? invoice,
  required String initialPayerName,
}) => showAppDialog<PaymentConfirmationData>(
  context,
  barrierDismissible: false,
  builder: (_) => _PaymentConfirmationDialog(
    payment: payment,
    invoice: invoice,
    initialPayerName: initialPayerName,
  ),
);

class _PaymentConfirmationDialog extends StatefulWidget {
  const _PaymentConfirmationDialog({
    required this.payment,
    required this.invoice,
    required this.initialPayerName,
  });

  final Entity payment;
  final Entity? invoice;
  final String initialPayerName;

  @override
  State<_PaymentConfirmationDialog> createState() =>
      _PaymentConfirmationDialogState();
}

class _PaymentConfirmationDialogState
    extends State<_PaymentConfirmationDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _payer;
  PrivateImageUpload? _proof;
  bool _picking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _payer = TextEditingController(text: widget.initialPayerName);
  }

  @override
  void dispose() {
    _payer.dispose();
    super.dispose();
  }

  Future<void> _pickProof() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final proof = await pickPrivateImage();
      if (mounted && proof != null) setState(() => _proof = proof);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    if (_proof == null) {
      setState(() => _error = 'Unggah foto bukti pembayaran terlebih dahulu.');
      return;
    }
    Navigator.pop(
      context,
      PaymentConfirmationData(payerName: _payer.text.trim(), proof: _proof!),
    );
  }

  Widget _summaryRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: AppTheme.muted),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF7F9F8),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  );

  @override
  Widget build(BuildContext context) => AppDialog(
    title: 'Konfirmasi pembayaran',
    subtitle: 'Lengkapi data dan unggah bukti setelah pembayaran berhasil.',
    icon: Icons.receipt_long_outlined,
    onClose: () => Navigator.pop(context),
    body: Padding(
      padding: const EdgeInsets.all(22),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F5F2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _summaryRow(
                    'Pembayaran untuk',
                    widget.invoice?.text('title') ?? 'SPP',
                  ),
                  _summaryRow('Periode', widget.invoice?.text('period') ?? '—'),
                  _summaryRow(
                    'Nominal',
                    rupiah(widget.payment.number('amount')),
                  ),
                  _summaryRow('Penerima', widget.payment.text('merchant_name')),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Nama pemilik rekening / dompet *',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _payer,
              decoration: _decoration('Nama yang digunakan saat membayar'),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Nama pembayar wajib diisi.'
                  : value.trim().length > 160
                  ? 'Nama pembayar terlalu panjang.'
                  : null,
            ),
            const SizedBox(height: 16),
            const Text(
              'Bukti pembayaran *',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _picking ? null : _pickProof,
              icon: Icon(
                _proof == null
                    ? Icons.add_photo_alternate_outlined
                    : Icons.change_circle_outlined,
              ),
              label: Text(
                _picking
                    ? 'Membuka galeri…'
                    : _proof == null
                    ? 'Pilih foto bukti pembayaran'
                    : 'Ganti foto bukti',
              ),
            ),
            if (_proof != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _proof!.bytes,
                  height: 180,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 90,
                    child: Center(child: Text('Pratinjau tidak tersedia.')),
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(color: Color(0xFFA34E37), fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            const Text(
              'Konfirmasi merupakan laporan dari pembayar. Status lunas tetap diberikan setelah pengelola mencocokkan mutasi.',
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: AppTheme.muted,
              ),
            ),
          ],
        ),
      ),
    ),
    footer: DialogActions(
      label: 'Kirim konfirmasi',
      cancelLabel: 'Batal',
      icon: Icons.send_outlined,
      onCancel: () => Navigator.pop(context),
      onConfirm: _submit,
    ),
  );
}
