import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/utils/formatters.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/edit_dialog.dart';

/// Shared editor for classroom reading, announcements and weekly schedules.
class ContentPage extends ConsumerStatefulWidget {
  const ContentPage({super.key, required this.kind});
  final String kind;
  @override
  ConsumerState<ContentPage> createState() => _ContentPageState();
}

class _ContentPageState extends ConsumerState<ContentPage> {
  String query = '', classFilter = '';
  int day = 0;
  String get title => {
    'announcement': 'Pengumuman',
    'material': 'Materi pelajaran',
    'schedule': 'Jadwal belajar',
  }[widget.kind]!;
  Future<void> _edit(AppStore s, [Entity? e]) => editDialog(
    context,
    s,
    title: '${e == null ? 'Tambah' : 'Ubah'} ${title.toLowerCase()}',
    initial:
        e?.data ??
        {
          'classId': s.role == UserRole.teacher
              ? s.classIds.firstOrNull ?? ''
              : '',
          'audience': 'all',
          'weekday': DateTime.now().weekday,
          'startTime': '07:30',
          'endTime': '08:30',
        },
    fields: [
      const FieldSpec('title', 'Judul'),
      FieldSpec(
        'classId',
        'Kelas',
        required: widget.kind != 'announcement' || s.role == UserRole.teacher,
        options: {
          if (widget.kind == 'announcement' && s.isManager) '': 'Semua kelas',
          for (final c in s.items('classroom')) c.id: c.text('name'),
        },
      ),
      if (widget.kind == 'announcement')
        FieldSpec(
          'audience',
          'Penerima',
          options: {
            'all': 'Semua peran',
            'student': 'Siswa',
            if (s.isManager) ...{'teacher': 'Guru', 'admin': 'Admin'},
          },
        )
      else
        FieldSpec(
          'subjectId',
          'Mata pelajaran',
          options: {for (final c in s.items('subject')) c.id: c.text('name')},
        ),
      if (widget.kind == 'schedule') ...[
        FieldSpec(
          'weekday',
          'Hari',
          number: true,
          options: {for (var i = 0; i < 7; i++) '${i + 1}': Formatters.days[i]},
        ),
        const FieldSpec('startTime', 'Mulai', time: true),
        const FieldSpec('endTime', 'Selesai', time: true),
        const FieldSpec('room', 'Ruang'),
      ] else
        const FieldSpec('content', 'Isi', lines: 7),
    ],
    onSave: (d) => s.save(widget.kind, d, previous: e),
  );
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final items = s
        .items(widget.kind)
        .where(
          (e) =>
              '${e.text('title')} ${e.text('content')}'.toLowerCase().contains(
                query.toLowerCase(),
              ) &&
              (classFilter.isEmpty || e.text('classId') == classFilter) &&
              (day == 0 ||
                  widget.kind != 'schedule' ||
                  e.number('weekday') == day),
        )
        .toList();
    if (widget.kind == 'schedule') {
      items.sort((a, b) {
        final d = a.number('weekday').compareTo(b.number('weekday'));
        return d == 0 ? a.text('startTime').compareTo(b.text('startTime')) : d;
      });
    }
    return PageFrame(
      title: title,
      floatingActionButton: s.isStaff
          ? FloatingActionButton.extended(
              onPressed: s.busy ? null : () => _edit(s),
              icon: const Icon(Icons.add),
              label: const Text('Tambah'),
            )
          : null,
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: 'Cari ${title.toLowerCase()}',
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 12),
        if (widget.kind == 'schedule')
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: const Text('Semua hari'),
                    selected: day == 0,
                    onSelected: (_) => setState(() => day = 0),
                  ),
                ),
                for (var i = 0; i < 7; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(Formatters.days[i]),
                      selected: day == i + 1,
                      onSelected: (_) => setState(() => day = i + 1),
                    ),
                  ),
              ],
            ),
          ),
        if (s.isStaff)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Semua kelas'),
                selected: classFilter.isEmpty,
                onSelected: (_) => setState(() => classFilter = ''),
              ),
              for (final c in s.items('classroom'))
                ChoiceChip(
                  label: Text(c.text('name')),
                  selected: classFilter == c.id,
                  onSelected: (_) => setState(() => classFilter = c.id),
                ),
            ],
          ),
        const SizedBox(height: 18),
        if (items.isEmpty)
          EmptyState('Belum ada ${title.toLowerCase()} yang sesuai'),
        for (final e in items)
          Card(
            margin: const EdgeInsets.only(bottom: 14),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          e.text('title'),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (s.canEdit(e))
                        PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'edit') {
                              await _edit(s, e);
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
                  const SizedBox(height: 6),
                  Text(
                    '${e.text('classId').isEmpty ? 'Seluruh instansi' : s.className(e.text('classId'))} • ${widget.kind == 'announcement' ? {'all': 'Semua peran', 'student': 'Siswa', 'teacher': 'Guru', 'admin': 'Admin'}[e.text('audience')] : s.entity(e.text('subjectId'))?.text('name') ?? 'Pelajaran'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 14),
                  if (widget.kind == 'schedule') ...[
                    StatusPill(
                      '${Formatters.days[(e.number('weekday', 1) - 1).clamp(0, 6)]} • ${e.text('startTime')}–${e.text('endTime')}',
                    ),
                    const SizedBox(height: 10),
                    Text('Ruang ${e.text('room')}'),
                    Text(
                      s.member(e.text('teacherId'))?.name ?? 'Guru pembimbing',
                    ),
                  ] else ...[
                    SelectableText(e.text('content')),
                    const SizedBox(height: 12),
                    Text(
                      Formatters.date(e.createdAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}
