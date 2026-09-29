import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/report_charts.dart';
import '../../shared/widgets/edit_dialog.dart';
import '../../shared/widgets/app_dialog.dart';
import 'spp_data.dart';

Future<void> editInvoice(
  BuildContext context,
  AppStore s, [
  Entity? invoice,
]) => editDialog(
  context,
  s,
  title: invoice == null ? 'Tambah tagihan santri' : 'Ubah tagihan',
  initial:
      invoice?.data ??
      {
        'allow_partial': 'true',
        'due_date': DateTime.now()
            .add(const Duration(days: 30))
            .toIso8601String(),
      },
  fields: [
    FieldSpec(
      'student_id',
      invoice == null ? 'Penerima tagihan' : 'Siswa / santri',
      options: {
        if (invoice == null)
          '__all__':
              'Semua siswa / santri aktif (${s.members(UserRole.student).where((u) => u.active).length})',
        for (final u in s.members(UserRole.student).where((u) => u.active))
          u.id: '${u.name} • ${u.number}',
      },
    ),
    const FieldSpec(
      'title',
      'Jenis biaya',
      hint: 'SPP, asrama, kitab, atau kegiatan',
    ),
    const FieldSpec('period', 'Periode tagihan', hint: 'September 2026'),
    const FieldSpec(
      'amount',
      'Total tagihan (rupiah)',
      number: true,
      hint: '500000, tanpa titik',
    ),
    const FieldSpec('due_date', 'Jatuh tempo', date: true),
    const FieldSpec(
      'allow_partial',
      'Pembayaran sebagian',
      options: {
        'true': 'Boleh dicicil / nominal manual',
        'false': 'Harus sebesar sisa tagihan',
      },
    ),
  ],
  onSave: (d) async {
    final allStudents = invoice == null && d['student_id'] == '__all__';
    final payload = <String, dynamic>{
      ...d,
      'allow_partial': d['allow_partial'].toString() == 'true',
    };
    if (allStudents) {
      payload
        ..remove('student_id')
        ..['scope'] = 'all';
      await s.repository.billingAction('invoice_bulk', payload);
    } else {
      await s.repository.billingAction('invoice', {
        ...payload,
        'id': invoice?.id ?? newId(),
      });
    }
  },
);

class SppPage extends ConsumerStatefulWidget {
  const SppPage({super.key});
  @override
  ConsumerState<SppPage> createState() => _SppPageState();
}

class _SppPageState extends ConsumerState<SppPage> {
  bool history = false, archived = false;
  String query = '', filter = 'all';
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final invoices = s.items('spp_invoice');
    final payments = s.items('spp_payment');
    final active = invoices.where((i) => i.data['archived'] != true);
    final total = active.fold(0, (sum, i) => sum + i.number('amount'));
    final verified = active.fold(
      0,
      (sum, i) => sum + credited(payments, i.id, verifiedOnly: true),
    );
    final reported = active.fold(0, (sum, i) => sum + credited(payments, i.id));
    final selected = (history ? payments : invoices).where((e) {
      final invoice = history ? s.entity(e.text('invoice_id')) : e;
      final name = s.member(e.text('student_id'))?.name ?? '';
      return '$name ${invoice?.text('title')} ${invoice?.text('period')}'
              .toLowerCase()
              .contains(query.toLowerCase()) &&
          (history
              ? filter == 'all' || e.text('status') == filter
              : (e.data['archived'] == true) == archived);
    }).toList();
    return PageFrame(
      title: 'Pembayaran SPP',
      subtitle: s.isManager
          ? 'Kelola tagihan dan setujui bukti pembayaran dari wali.'
          : 'Tagihan pendidikan dan riwayat pembayaran santri.',
      actions: [
        if (s.isManager)
          IconButton(
            tooltip: 'Pengaturan QRIS',
            onPressed: () => context.push('/spp/settings'),
            icon: const Icon(Icons.qr_code_rounded),
          ),
      ],
      floatingActionButton: s.isManager && !history
          ? FloatingActionButton.extended(
              onPressed: s.busy ? null : () => editInvoice(context, s),
              icon: const Icon(Icons.add),
              label: const Text('Tagihan'),
            )
          : null,
      children: [
        Card(
          color: AppTheme.primary,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TOTAL TAGIHAN AKTIF',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  rupiah(total),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Dana dicocokkan: ${rupiah(verified)}\nDilaporkan, belum dicocokkan: ${rupiah(reported - verified)}',
                  style: const TextStyle(color: Colors.white, height: 1.7),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (s.isManager) ...[
          ReportChartCard(
            title: 'Status pembayaran',
            subtitle:
                'Pie chart transaksi menunggu, dilaporkan, dan disetujui.',
            child: SimplePieChart(
              values: [
                payments
                    .where((p) => p.text('status') == 'pending')
                    .length
                    .toDouble(),
                payments
                    .where((p) => p.text('status') == 'reported')
                    .length
                    .toDouble(),
                payments
                    .where((p) => p.text('status') == 'matched')
                    .length
                    .toDouble(),
              ],
              labels: const ['Menunggu', 'Perlu disetujui', 'Disetujui'],
            ),
          ),
          ReportChartCard(
            title: 'Nominal tagihan aktif',
            subtitle: 'Bar chart delapan tagihan terbaru.',
            child: SimpleBarChart(
              values: active
                  .take(8)
                  .map((i) => i.number('amount').toDouble())
                  .toList(),
              labels: active
                  .take(8)
                  .map(
                    (i) =>
                        s.member(i.text('student_id'))?.name.split(' ').first ??
                        'Siswa',
                  )
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Tagihan'),
              selected: !history,
              onSelected: (_) => setState(() => history = false),
            ),
            ChoiceChip(
              label: const Text('Riwayat pembayaran'),
              selected: history,
              onSelected: (_) => setState(() => history = true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          decoration: const InputDecoration(
            hintText: 'Cari santri, biaya, atau periode',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 10),
        if (history)
          Wrap(
            spacing: 6,
            runSpacing: 8,
            children: [
              for (final entry in {'all': 'Semua', ...paymentLabels}.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: filter == entry.key,
                  onSelected: (_) => setState(() => filter = entry.key),
                ),
            ],
          )
        else
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Tampilkan arsip'),
            value: archived,
            onChanged: (v) => setState(() => archived = v),
          ),
        if (selected.isEmpty)
          const EmptyState(
            'Belum ada data SPP',
            message: 'Tagihan yang dibuat pengelola akan tampil di sini.',
          ),
        for (final e in selected)
          if (history)
            PaymentTile(payment: e)
          else
            Card(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => context.push('/spp/invoice/${e.id}'),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.text('title'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${s.member(e.text('student_id'))?.name ?? 'Santri'} • ${e.text('period')}',
                      ),
                      const SizedBox(height: 14),
                      InvoiceProgress(invoice: e, payments: payments),
                    ],
                  ),
                ),
              ),
            ),
      ],
    );
  }
}

class InvoiceProgress extends StatelessWidget {
  const InvoiceProgress({
    super.key,
    required this.invoice,
    required this.payments,
  });
  final Entity invoice;
  final List<Entity> payments;
  @override
  Widget build(BuildContext context) {
    final amount = invoice.number('amount');
    final reported = credited(payments, invoice.id);
    final verified = credited(payments, invoice.id, verifiedOnly: true);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: amount > 0 ? (reported / amount).clamp(0, 1).toDouble() : 0,
          minHeight: 8,
          borderRadius: BorderRadius.circular(8),
        ),
        const SizedBox(height: 8),
        Text(
          '${rupiah(reported)} dari ${rupiah(amount)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        Text(
          'Termasuk laporan wali • Dicocokkan ${rupiah(verified)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (verified >= amount && amount > 0)
          const Text(
            'Lunas berdasarkan mutasi',
            style: TextStyle(
              color: AppTheme.primary,
              fontWeight: FontWeight.w700,
            ),
          )
        else if (reported >= amount)
          const Text('Dilaporkan penuh • belum seluruhnya dicocokkan'),
      ],
    );
  }
}

class PaymentTile extends ConsumerWidget {
  const PaymentTile({super.key, required this.payment});
  final Entity payment;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    return DataTile(
      title:
          '${rupiah(payment.number('amount'))} • ${paymentLabels[payment.text('status')] ?? payment.text('status')}',
      subtitle:
          '${s.member(payment.text('student_id'))?.name ?? 'Santri'}\n${s.entity(payment.text('invoice_id'))?.text('title') ?? 'Tagihan'} • ${s.entity(payment.text('invoice_id'))?.text('period') ?? ''}',
      icon: Icons.receipt_long_outlined,
      onTap: () => context.push('/spp/payment/${payment.id}'),
    );
  }
}

class InvoicePage extends ConsumerWidget {
  const InvoicePage({super.key, required this.id});
  final String id;
  Future<void> pay(BuildContext context, AppStore s, Entity i) async {
    final remaining = i.number('amount') - credited(s.items('spp_payment'), id);
    Json? checkout;
    final requestId = newId();
    await editDialog(
      context,
      s,
      title: 'Nominal pembayaran',
      initial: {'amount': remaining},
      fields: [
        FieldSpec(
          'amount',
          'Nominal (rupiah)',
          number: true,
          hint: i.data['allow_partial'] == true
              ? 'Tanpa titik; tidak melebihi sisa tagihan'
              : 'Wajib sebesar sisa tagihan: $remaining',
        ),
      ],
      onSave: (d) async {
        checkout = await s.repository.billingAction('checkout', {
          'id': requestId,
          'invoice_id': id,
          'amount': d['amount'],
        });
      },
    );
    if (context.mounted && checkout != null) {
      context.push('/spp/payment/${checkout!['id']}');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final i = s.entity(id);
    if (i == null || i.kind != 'spp_invoice') {
      return const PageFrame(
        title: 'Tagihan',
        children: [EmptyState('Tagihan tidak tersedia')],
      );
    }
    final payments = s
        .items('spp_payment')
        .where((p) => p.text('invoice_id') == id)
        .toList();
    final remaining = i.number('amount') - credited(payments, id);
    return PageFrame(
      title: i.text('title'),
      subtitle:
          '${s.member(i.text('student_id'))?.name ?? 'Santri'} • ${i.text('period')}',
      children: [
        Text(
          rupiah(i.number('amount')),
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        Text('Jatuh tempo: ${i.text('due_date')}'),
        const SizedBox(height: 20),
        InvoiceProgress(invoice: i, payments: payments),
        const SizedBox(height: 18),
        if (s.role == UserRole.student &&
            remaining > 0 &&
            i.data['archived'] != true)
          FilledButton.icon(
            onPressed: s.busy ? null : () => pay(context, s, i),
            icon: const Icon(Icons.qr_code),
            label: const Text('Bayar dengan QRIS'),
          ),
        if (s.isManager)
          Wrap(
            spacing: 8,
            runSpacing: 10,
            children: [
              if (payments.isEmpty)
                OutlinedButton.icon(
                  onPressed: s.busy ? null : () => editInvoice(context, s, i),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Ubah tagihan'),
                ),
              OutlinedButton(
                onPressed: s.busy
                    ? null
                    : () async {
                        if (await confirmAction(
                              context,
                              title: 'Ubah status arsip?',
                              message:
                                  'Riwayat pembayaran tetap disimpan. Tagihan dalam arsip tidak menerima sesi QR baru.',
                              confirmLabel: 'Lanjutkan',
                            ) &&
                            context.mounted) {
                          await runAction(context, s, () async {
                            await s.repository.billingAction('archive', {
                              'id': id,
                            });
                          });
                        }
                      },
                child: Text(
                  i.data['archived'] == true ? 'Aktifkan kembali' : 'Arsipkan',
                ),
              ),
              OutlinedButton.icon(
                onPressed: () async {
                  await contactWali(
                    context,
                    s,
                    i.text('student_id'),
                    'Mohon konfirmasi pembayaran ${i.text('title')} periode ${i.text('period')}.',
                  );
                },
                icon: const Icon(Icons.chat_outlined),
                label: const Text('WhatsApp wali'),
              ),
            ],
          ),
        const SizedBox(height: 24),
        Text(
          'Riwayat transaksi',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (payments.isEmpty) const EmptyState('Belum ada pembayaran'),
        for (final p in payments) PaymentTile(payment: p),
      ],
    );
  }
}

Future<void> contactWali(
  BuildContext context,
  AppStore s,
  String studentId,
  String message,
) async {
  try {
    final url = whatsappLink(s.member(studentId)?.phone ?? '', message);
    if (!await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    )) {
      throw const AppFailure('WhatsApp/browser tidak tersedia.');
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }
}
