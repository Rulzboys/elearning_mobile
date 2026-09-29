import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/formatters.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/edit_dialog.dart';

class TenantsPage extends ConsumerStatefulWidget {
  const TenantsPage({super.key});
  @override
  ConsumerState<TenantsPage> createState() => _TenantsPageState();
}

class _TenantsPageState extends ConsumerState<TenantsPage> {
  String query = '';
  Future<void> _edit(AppStore s, [Tenant? t]) => editDialog(
    context,
    s,
    title: t == null ? 'Tambah instansi' : 'Ubah instansi',
    initial:
        (t == null
            ? null
            : {
                ...t.toJson(),
                'expires_at': Formatters.dayKey(
                  t.expiresAt.toLocal().subtract(const Duration(seconds: 1)),
                ),
              }) ??
        Tenant(
          id: newId(),
          name: '',
          code: '',
          expiresAt: DateTime.now().add(const Duration(days: 365)),
        ).toJson(),
    fields: const [
      FieldSpec('name', 'Nama instansi'),
      FieldSpec('code', 'Kode instansi (huruf besar)'),
      FieldSpec(
        'plan',
        'Paket',
        options: {
          'Dasar': 'Dasar',
          'Sekolah': 'Sekolah',
          'Pesantren': 'Pesantren',
        },
      ),
      FieldSpec(
        'status',
        'Status',
        options: {'active': 'Aktif', 'suspended': 'Ditangguhkan'},
      ),
      FieldSpec('expires_at', 'Aktif sampai tanggal', date: true),
      FieldSpec('contact', 'Kontak penanggung jawab', required: false),
    ],
    onSave: (d) {
      d['code'] = (d['code'] as String).toUpperCase();
      final selected = DateTime.parse(d['expires_at'] as String).toLocal();
      d['expires_at'] = DateTime(
        selected.year,
        selected.month,
        selected.day + 1,
      ).toUtc().toIso8601String();
      return s.saveTenant(Tenant.fromJson(d));
    },
  );
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final tenants = s.tenants
        .where(
          (t) =>
              '${t.name} ${t.code}'.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    return PageFrame(
      title: 'Instansi & masa aktif',
      subtitle: 'Status dan masa aktif berlaku untuk seluruh akun di instansi.',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: s.busy ? null : () => _edit(s),
        icon: const Icon(Icons.add),
        label: const Text('Tambah instansi'),
      ),
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: 'Cari nama atau kode instansi',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 20),
        if (tenants.isEmpty) const EmptyState('Instansi tidak ditemukan'),
        for (final t in tenants)
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.name, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text('${t.code} • Paket ${t.plan}'),
                  const SizedBox(height: 10),
                  StatusPill(t.accessLabel, positive: t.isActive),
                  const SizedBox(height: 10),
                  Text(
                    'Masa aktif: ${Formatters.date(t.expiresAt.subtract(const Duration(seconds: 1)))}',
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: s.busy ? null : () => _edit(s, t),
                        icon: const Icon(Icons.edit_outlined),
                        label: const Text('Ubah'),
                      ),
                      TextButton(
                        onPressed: s.busy
                            ? null
                            : () async {
                                final suspend = t.status == 'active';
                                final yes = await confirmAction(
                                  context,
                                  title: suspend
                                      ? 'Tangguhkan instansi?'
                                      : 'Aktifkan instansi?',
                                  message: suspend
                                      ? 'Akun guru, siswa, dan admin pada ${t.name} akan kehilangan akses sampai diaktifkan kembali.'
                                      : 'Akses akan dibuka jika masa aktif instansi masih berlaku.',
                                  confirmLabel: suspend
                                      ? 'Tangguhkan'
                                      : 'Aktifkan',
                                  icon: suspend
                                      ? Icons.pause_circle_outline
                                      : Icons.check_circle_outline,
                                  danger: suspend,
                                );
                                if (yes == true && context.mounted) {
                                  await runAction(
                                    context,
                                    s,
                                    () => s.saveTenant(
                                      Tenant.fromJson({
                                        ...t.toJson(),
                                        'status': suspend
                                            ? 'suspended'
                                            : 'active',
                                      }),
                                    ),
                                  );
                                }
                              },
                        child: Text(
                          t.status == 'active' ? 'Tangguhkan' : 'Aktifkan',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
