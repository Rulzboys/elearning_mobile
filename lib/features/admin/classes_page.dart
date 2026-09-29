import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/edit_dialog.dart';

class ClassesPage extends ConsumerStatefulWidget {
  const ClassesPage({super.key});
  @override
  ConsumerState<ClassesPage> createState() => _ClassesPageState();
}

class _ClassesPageState extends ConsumerState<ClassesPage> {
  bool subjects = false;
  Future<void> _edit(AppStore s, [Entity? e]) => editDialog(
    context,
    s,
    title:
        '${e == null ? 'Tambah' : 'Ubah'} ${subjects ? 'mata pelajaran' : 'kelas'}',
    initial:
        e?.data ??
        {
          'academicYear': s.tenant!.academicYear,
          'targetCount': s.tenant!.targetCount,
        },
    fields: [
      const FieldSpec('name', 'Nama'),
      if (subjects)
        const FieldSpec('description', 'Keterangan', required: false, lines: 3)
      else ...[
        FieldSpec(
          'teacherId',
          'Guru pembimbing',
          options: {
            for (final u in s.members(UserRole.teacher).where((u) => u.active))
              u.id: u.name,
          },
        ),
        const FieldSpec('academicYear', 'Tahun ajaran'),
        const FieldSpec('targetCount', 'Target bagian hafalan', number: true),
      ],
    ],
    onSave: (d) => s.save(subjects ? 'subject' : 'classroom', d, previous: e),
  );
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final items = s.items(subjects ? 'subject' : 'classroom');
    return PageFrame(
      title: 'Kelas & mata pelajaran',
      floatingActionButton: FloatingActionButton.extended(
        onPressed: s.busy ? null : () => _edit(s),
        icon: const Icon(Icons.add),
        label: const Text('Tambah'),
      ),
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Kelas')),
            ButtonSegment(value: true, label: Text('Pelajaran')),
          ],
          selected: {subjects},
          onSelectionChanged: (v) => setState(() => subjects = v.first),
        ),
        const SizedBox(height: 20),
        if (items.isEmpty) const EmptyState('Data belum ditambahkan'),
        for (final e in items)
          DataTile(
            title: e.text('name'),
            subtitle: subjects
                ? e.text('description')
                : '${s.member(e.text('teacherId'))?.name ?? 'Guru pembimbing'} • ${e.text('academicYear')}\nTarget ${e.number('targetCount')} bagian hafalan',
            icon: subjects ? Icons.menu_book_outlined : Icons.class_outlined,
            onTap: () => _edit(s, e),
            trailing: IconButton(
              tooltip: 'Hapus',
              icon: const Icon(Icons.delete_outline),
              onPressed: s.busy
                  ? null
                  : () async {
                      if (await confirmDelete(context, e.text('name')) &&
                          context.mounted) {
                        await runAction(context, s, () => s.remove(e));
                      }
                    },
            ),
          ),
      ],
    );
  }
}
