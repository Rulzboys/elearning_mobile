import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/formatters.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/edit_dialog.dart';

class AssignmentPage extends ConsumerStatefulWidget {
  const AssignmentPage({super.key});
  @override
  ConsumerState<AssignmentPage> createState() => _AssignmentPageState();
}

class _AssignmentPageState extends ConsumerState<AssignmentPage> {
  String query = '', filter = 'all';
  Future<void> _edit(AppStore s, [Entity? e]) => editDialog(
    context,
    s,
    title: e == null ? 'Buat tugas' : 'Ubah tugas',
    initial:
        e?.data ??
        {
          'dueAt': DateTime.now()
              .add(const Duration(days: 7))
              .toIso8601String(),
        },
    fields: [
      const FieldSpec('title', 'Judul tugas'),
      const FieldSpec('description', 'Instruksi', lines: 5),
      FieldSpec(
        'classId',
        'Kelas',
        options: {for (final c in s.items('classroom')) c.id: c.text('name')},
      ),
      FieldSpec(
        'subjectId',
        'Mata pelajaran',
        options: {for (final c in s.items('subject')) c.id: c.text('name')},
      ),
      const FieldSpec('dueAt', 'Batas pengumpulan (sampai 23:59)', date: true),
    ],
    onSave: (d) {
      final selected = DateTime.parse(d['dueAt'] as String).toLocal();
      d['dueAt'] = DateTime(
        selected.year,
        selected.month,
        selected.day,
        23,
        59,
        59,
      ).toUtc().toIso8601String();
      return s.save('assignment', d, previous: e);
    },
  );
  Future<void> _submit(AppStore s, Entity a, Entity? previous) => editDialog(
    context,
    s,
    title: previous == null ? 'Kumpulkan tugas' : 'Ubah jawaban',
    initial: {
      ...?(previous?.data),
      'assignmentId': a.id,
      'classId': a.text('classId'),
      'studentId': s.user!.id,
    },
    fields: const [FieldSpec('answer', 'Jawaban', lines: 8)],
    onSave: (d) => s.save('submission', d, previous: previous),
  );
  Future<void> _grade(AppStore s, Entity answer) => editDialog(
    context,
    s,
    title:
        'Nilai tugas • ${s.member(answer.text('studentId'))?.name ?? 'Siswa'}',
    initial: answer.data,
    fields: const [
      FieldSpec('score', 'Nilai 0–100', number: true),
      FieldSpec('feedback', 'Catatan guru', required: false, lines: 4),
    ],
    onSave: (d) => s.save('submission', d, previous: answer),
  );
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final student = s.role == UserRole.student;
    final items = s.items('assignment').where((e) {
      final submitted = s
          .items('submission')
          .any(
            (a) =>
                a.text('assignmentId') == e.id &&
                a.text('studentId') == s.user!.id,
          );
      return e.text('title').toLowerCase().contains(query.toLowerCase()) &&
          (filter == 'all' || (filter == 'done' ? submitted : !submitted));
    }).toList()..sort((a, b) => a.text('dueAt').compareTo(b.text('dueAt')));
    return PageFrame(
      title: 'Tugas belajar',
      floatingActionButton: s.isStaff
          ? FloatingActionButton.extended(
              onPressed: s.busy ? null : () => _edit(s),
              icon: const Icon(Icons.add),
              label: const Text('Buat tugas'),
            )
          : null,
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: 'Cari tugas',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 12),
        if (student)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in {
                'all': 'Semua',
                'pending': 'Belum dikumpulkan',
                'done': 'Dikumpulkan',
              }.entries)
                ChoiceChip(
                  label: Text(e.value),
                  selected: filter == e.key,
                  onSelected: (_) => setState(() => filter = e.key),
                ),
            ],
          ),
        const SizedBox(height: 14),
        if (items.isEmpty) const EmptyState('Belum ada tugas yang sesuai'),
        for (final a in items) _card(s, a, student),
      ],
    );
  }

  Widget _card(AppStore s, Entity a, bool student) {
    final submissions = s
        .items('submission')
        .where((e) => e.text('assignmentId') == a.id)
        .toList();
    final mine = submissions
        .where((e) => e.text('studentId') == s.user!.id)
        .firstOrNull;
    final expired = DateTime.parse(a.text('dueAt')).isBefore(DateTime.now());
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              a.text('title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '${s.className(a.text('classId'))} • ${s.entity(a.text('subjectId'))?.text('name') ?? 'Pelajaran'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SelectableText(a.text('description')),
            const SizedBox(height: 12),
            StatusPill(
              'Batas: ${Formatters.dateTime(DateTime.parse(a.text('dueAt')))}',
              positive: !expired,
            ),
            if (student) ...[
              const SizedBox(height: 14),
              if (mine != null) ...[
                const Text(
                  'Jawaban Anda',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                SelectableText(mine.text('answer')),
                const SizedBox(height: 10),
                StatusPill(
                  mine.data['score'] == null
                      ? 'Menunggu penilaian'
                      : 'Nilai ${mine.number('score')}/100',
                ),
                if (mine.text('feedback').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('Catatan guru: ${mine.text('feedback')}'),
                  ),
              ],
              const SizedBox(height: 12),
              if (!expired && mine?.data['score'] == null)
                FilledButton.icon(
                  onPressed: s.busy ? null : () => _submit(s, a, mine),
                  icon: const Icon(Icons.send_outlined),
                  label: Text(mine == null ? 'Kumpulkan' : 'Ubah jawaban'),
                ),
              if (expired && mine == null)
                const Text('Batas pengumpulan telah berakhir.'),
            ] else ...[
              const SizedBox(height: 12),
              Text(
                '${submissions.length} dari ${s.members(UserRole.student).where((u) => u.classId == a.text('classId') && u.active).length} siswa mengumpulkan',
              ),
              for (final answer in submissions)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(
                    s.member(answer.text('studentId'))?.name ?? 'Siswa',
                  ),
                  subtitle: Text(
                    answer.data['score'] == null
                        ? 'Belum dinilai'
                        : 'Nilai ${answer.number('score')}',
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(answer.text('answer')),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: OutlinedButton(
                        onPressed: s.busy ? null : () => _grade(s, answer),
                        child: const Text('Beri / ubah nilai'),
                      ),
                    ),
                  ],
                ),
              if (s.canEdit(a))
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: s.busy ? null : () => _edit(s, a),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Ubah tugas'),
                    ),
                    TextButton.icon(
                      onPressed: s.busy
                          ? null
                          : () async {
                              if (await confirmDelete(
                                    context,
                                    a.text('title'),
                                  ) &&
                                  mounted) {
                                await runAction(context, s, () => s.remove(a));
                              }
                            },
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Hapus'),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
