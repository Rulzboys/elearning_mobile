import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/utils/formatters.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/models/models.dart';
import '../../shared/widgets/common.dart';

class AttendancePage extends ConsumerStatefulWidget {
  const AttendancePage({super.key});
  @override
  ConsumerState<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends ConsumerState<AttendancePage> {
  DateTime date = DateTime.now();
  String classId = '';
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final key = Formatters.dayKey(date);
    final students = s
        .members(UserRole.student)
        .where((u) => u.active && (classId.isEmpty || u.classId == classId))
        .toList();
    final entries = s
        .items('attendance')
        .where((e) => e.text('date') == key)
        .toList();
    return PageFrame(
      title: 'Presensi siswa',
      subtitle: s.role == UserRole.teacher
          ? 'Presensi hadir dicatat dengan memindai QR pada kartu siswa.'
          : 'Lihat hasil presensi yang dicatat oleh guru.',
      children: [
        if (s.role == UserRole.teacher) ...[
          FilledButton.icon(
            onPressed: () => context.push('/teacher/attendance/scan'),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Mulai scan presensi'),
          ),
          const SizedBox(height: 12),
        ],
        OutlinedButton.icon(
          icon: const Icon(Icons.calendar_today_outlined),
          label: Text(Formatters.date(date)),
          onPressed: () async {
            final selected = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (selected != null) setState(() => date = selected);
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Semua kelas'),
              selected: classId.isEmpty,
              onSelected: (_) => setState(() => classId = ''),
            ),
            for (final c in s.items('classroom'))
              ChoiceChip(
                label: Text(c.text('name')),
                selected: classId == c.id,
                onSelected: (_) => setState(() => classId = c.id),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (students.isEmpty) const EmptyState('Belum ada siswa'),
        for (final u in students)
          _row(
            s,
            u,
            entries.where((e) => e.text('studentId') == u.id).firstOrNull,
          ),
      ],
    );
  }

  Widget _row(AppStore s, AppUser u, Entity? e) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(u.name, style: Theme.of(context).textTheme.titleMedium),
          Text(s.className(u.classId)),
          const SizedBox(height: 10),
          const SizedBox(height: 8),
          StatusPill(
            e?.text('status') ?? 'Belum scan',
            positive: e?.text('status') == 'Hadir',
          ),
          if (e != null)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Dicatat melalui QR siswa',
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    ),
  );
}
