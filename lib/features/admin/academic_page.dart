import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/formatters.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/edit_dialog.dart';

class AcademicPage extends ConsumerWidget {
  const AcademicPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final t = s.tenant;
    if (t == null) return const SizedBox.shrink();
    return PageFrame(
      title: 'Pengaturan akademik',
      children: [
        DataTile(
          title: t.name,
          subtitle: '${t.code}\n${t.address}',
          icon: Icons.school_outlined,
        ),
        DataTile(
          title: 'Tahun ajaran ${t.academicYear}',
          subtitle: 'Semester ${t.semester}',
          icon: Icons.calendar_month_outlined,
        ),
        DataTile(
          title: 'Target hafalan awal',
          subtitle: '${t.targetCount} bagian • dapat disesuaikan per kelas',
          icon: Icons.menu_book_outlined,
        ),
        DataTile(
          title: 'Paket ${t.plan}',
          subtitle: '${t.accessLabel} sampai ${Formatters.date(t.expiresAt)}',
          icon: Icons.verified_outlined,
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Ubah pengaturan'),
          onPressed: s.busy
              ? null
              : () => editDialog(
                  context,
                  s,
                  title: 'Pengaturan instansi',
                  initial: t.toJson(),
                  fields: const [
                    FieldSpec('name', 'Nama sekolah / pesantren'),
                    FieldSpec('address', 'Alamat', required: false, lines: 2),
                    FieldSpec('contact', 'Kontak admin', required: false),
                    FieldSpec('academic_year', 'Tahun ajaran'),
                    FieldSpec(
                      'semester',
                      'Semester',
                      options: {'Ganjil': 'Ganjil', 'Genap': 'Genap'},
                    ),
                    FieldSpec(
                      'target_count',
                      'Target bagian hafalan',
                      number: true,
                    ),
                  ],
                  onSave: (d) => s.saveTenant(Tenant.fromJson(d)),
                ),
        ),
      ],
    );
  }
}
