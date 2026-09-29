import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/formatters.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/edit_dialog.dart';

const memorizationStatuses = {
  'inProgress': 'Dalam proses',
  'review': 'Perlu diulang',
  'completed': 'Tuntas',
};

Future<void> editMemorization(
  BuildContext context,
  AppStore s,
  String studentId, [
  Entity? record,
]) async {
  final student = s.member(studentId);
  if (student == null || student.classId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Siswa belum memiliki kelas.')),
    );
    return;
  }
  await editDialog(
    context,
    s,
    title: record == null
        ? 'Catat setoran • ${student.name}'
        : 'Ubah catatan setoran',
    initial:
        record?.data ??
        {
          'studentId': student.id,
          'classId': student.classId,
          'startVerse': 1,
          'endVerse': 7,
          'fluency': 80,
          'tajwid': 80,
          'makhraj': 80,
          'status': 'inProgress',
        },
    fields: [
      const FieldSpec(
        'title',
        'Surah / bagian hafalan',
        hint: 'Contoh: Al-Fatihah',
      ),
      const FieldSpec('startVerse', 'Ayat awal', number: true),
      const FieldSpec('endVerse', 'Ayat akhir', number: true),
      const FieldSpec('fluency', 'Kelancaran (0–100)', number: true),
      const FieldSpec('tajwid', 'Tajwid (0–100)', number: true),
      const FieldSpec('makhraj', 'Makhraj (0–100)', number: true),
      const FieldSpec('status', 'Hasil setoran', options: memorizationStatuses),
      const FieldSpec('notes', 'Catatan pembimbing', required: false, lines: 4),
    ],
    onSave: (d) => s.save('memorization', d, previous: record),
  );
}

class MemorizationPage extends ConsumerStatefulWidget {
  const MemorizationPage({super.key, this.studentId});
  final String? studentId;
  @override
  ConsumerState<MemorizationPage> createState() => _MemorizationPageState();
}

class _MemorizationPageState extends ConsumerState<MemorizationPage> {
  String filter = 'all';
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final id = widget.studentId ?? s.user?.id;
    final student = id == null ? null : s.member(id);
    if (student == null) {
      return const PageFrame(
        title: 'Hafalan',
        children: [EmptyState('Siswa tidak ditemukan')],
      );
    }
    final records = s
        .recordsFor(student.id)
        .where((e) => filter == 'all' || e.text('status') == filter)
        .toList();
    return PageFrame(
      title: s.isStaff
          ? 'Hafalan ${student.name.split(' ').first}'
          : 'Hafalan saya',
      subtitle: '${student.name} • ${s.className(student.classId)}',
      actions: [
        if (s.isStaff)
          IconButton(
            tooltip: 'Kartu QR siswa',
            onPressed: () => context.push('/teacher/cards/${student.id}'),
            icon: const Icon(Icons.badge_outlined),
          ),
      ],
      floatingActionButton: s.isStaff
          ? FloatingActionButton.extended(
              onPressed: s.busy
                  ? null
                  : () => editMemorization(context, s, student.id),
              icon: const Icon(Icons.add),
              label: const Text('Catat setoran'),
            )
          : null,
      children: [
        StatGrid([
          (
            label: 'Bagian tuntas',
            value: '${s.completed(student.id)}',
            icon: Icons.task_alt,
          ),
          (
            label: 'Target bagian',
            value: '${s.target(student.id)}',
            icon: Icons.flag_outlined,
          ),
        ]),
        const SizedBox(height: 16),
        LinearProgressIndicator(
          value: s.progress(student.id),
          minHeight: 8,
          borderRadius: BorderRadius.circular(6),
        ),
        const SizedBox(height: 12),
        const Text(
          'Bagian yang sama dihitung satu kali, berdasarkan hasil setoran terakhir.',
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final x in {'all': 'Semua', ...memorizationStatuses}.entries)
              ChoiceChip(
                label: Text(x.value),
                selected: filter == x.key,
                onSelected: (_) => setState(() => filter = x.key),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (records.isEmpty)
          const EmptyState(
            'Belum ada setoran yang sesuai',
            message: 'Setoran yang dicatat pembimbing akan muncul di sini.',
          ),
        for (final e in records)
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${e.text('title')} • ayat ${e.number('startVerse')}–${e.number('endVerse')}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (s.canEdit(e))
                        PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'edit') {
                              await editMemorization(context, s, student.id, e);
                            } else if (await confirmDelete(
                                  context,
                                  e.text('title'),
                                ) &&
                                context.mounted) {
                              await runAction(context, s, () => s.remove(e));
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Ubah')),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Hapus'),
                            ),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  StatusPill(
                    memorizationStatuses[e.text('status')] ?? 'Dalam proses',
                    positive: e.text('status') == 'completed',
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      Text('Kelancaran ${e.number('fluency')}'),
                      Text('Tajwid ${e.number('tajwid')}'),
                      Text('Makhraj ${e.number('makhraj')}'),
                    ],
                  ),
                  if (e.text('notes').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(e.text('notes')),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    '${Formatters.dateTime(e.createdAt)} • ${s.member(e.text('teacherId'))?.name ?? 'Pembimbing'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
