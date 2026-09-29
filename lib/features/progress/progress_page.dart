import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/services/card_print_host.dart';
import '../../core/services/progress_report_document.dart';
import '../../core/utils/formatters.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/report_charts.dart';

class ProgressPage extends ConsumerStatefulWidget {
  const ProgressPage({super.key});

  @override
  ConsumerState<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends ConsumerState<ProgressPage> {
  final _host = CardPrintHost();
  bool _preparing = false;

  @override
  void dispose() {
    unawaited(_host.close());
    super.dispose();
  }

  List<ProgressReportRow> _rows(AppStore s, List<AppUser> students) => [
    for (final u in students)
      () {
        final answers = s
            .items('submission')
            .where((e) => e.text('studentId') == u.id)
            .toList();
        final grades = answers.where((e) => e.data['score'] != null).toList();
        final attendance = s
            .items('attendance')
            .where((e) => e.text('studentId') == u.id)
            .toList();
        return ProgressReportRow(
          name: u.name,
          classroom: s.className(u.classId),
          completed: s.completed(u.id),
          target: s.target(u.id),
          submissions: answers.length,
          averageScore: grades.isEmpty
              ? ''
              : (grades.fold<int>(0, (sum, e) => sum + e.number('score')) /
                        grades.length)
                    .toStringAsFixed(1),
          present: attendance.where((e) => e.text('status') == 'Hadir').length,
          attendanceTotal: attendance.length,
        );
      }(),
  ];

  Future<void> _download(AppStore s, List<AppUser> students) async {
    if (_preparing) return;
    setState(() => _preparing = true);
    try {
      final url = await _host.prepare(
        progressReportDocument(
          school: s.tenant?.name ?? 'E-Learning',
          generatedAt: Formatters.dateTime(DateTime.now()),
          rows: _rows(s, students),
        ),
      );
      if (!mounted) return;
      if (kIsWeb) {
        _host.openBrowser(url);
      } else if (!await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        throw const AppFailure('Browser tidak tersedia.');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final students = s.members(UserRole.student);
    final memorization = s.items('memorization')
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final attendance = s.items('attendance');
    final attendanceLabels = ['Hadir', 'Izin', 'Sakit', 'Alpa'];
    return PageFrame(
      title: 'Perkembangan belajar',
      actions: [
        IconButton(
          tooltip: 'Unduh laporan PDF',
          icon: Icon(
            _preparing ? Icons.hourglass_top_rounded : Icons.picture_as_pdf,
          ),
          onPressed: _preparing ? null : () => _download(s, students),
        ),
      ],
      children: [
        Text('Ringkasan seluruh catatan • ${Formatters.date(DateTime.now())}'),
        const SizedBox(height: 16),
        ReportChartCard(
          title: 'Capaian hafalan per siswa',
          subtitle: 'Bar chart persentase capaian terhadap target.',
          child: SimpleBarChart(
            values: students
                .take(8)
                .map((u) => s.progress(u.id) * 100)
                .toList(),
            labels: students
                .take(8)
                .map((u) => u.name.split(' ').first)
                .toList(),
          ),
        ),
        ReportChartCard(
          title: 'Tren catatan perkembangan',
          subtitle: 'Line chart pertumbuhan jumlah setoran yang tercatat.',
          child: SimpleLineChart(
            values: [
              for (var i = 0; i < memorization.length && i < 12; i++)
                (i + 1).toDouble(),
            ],
          ),
        ),
        ReportChartCard(
          title: 'Komposisi presensi',
          subtitle: 'Pie chart seluruh status presensi yang tersimpan.',
          child: SimplePieChart(
            values: [
              for (final label in attendanceLabels)
                attendance
                    .where((e) => e.text('status') == label)
                    .length
                    .toDouble(),
            ],
            labels: attendanceLabels,
          ),
        ),
        if (students.isEmpty)
          const EmptyState('Belum ada perkembangan belajar'),
        for (final u in students) _card(context, s, u),
      ],
    );
  }

  Widget _card(BuildContext context, AppStore s, AppUser u) {
    final answers = s
        .items('submission')
        .where((e) => e.text('studentId') == u.id)
        .toList();
    final graded = answers.where((e) => e.data['score'] != null).toList();
    final attendance = s
        .items('attendance')
        .where((e) => e.text('studentId') == u.id)
        .toList();
    final present = attendance.where((e) => e.text('status') == 'Hadir').length;
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(u.name, style: Theme.of(context).textTheme.titleMedium),
            Text(s.className(u.classId)),
            const SizedBox(height: 16),
            Text(
              'Hafalan • ${s.completed(u.id)} / ${s.target(u.id)} bagian tuntas',
            ),
            const SizedBox(height: 10),
            LinearProgressIndicator(
              value: s.progress(u.id),
              minHeight: 8,
              borderRadius: BorderRadius.circular(5),
            ),
            const SizedBox(height: 16),
            Text('Tugas dikumpulkan: ${answers.length}'),
            Text(
              'Rata-rata tugas: ${graded.isEmpty ? 'Belum dinilai' : (graded.fold<int>(0, (sum, e) => sum + e.number('score')) / graded.length).toStringAsFixed(1)}',
            ),
            Text('Kehadiran: $present dari ${attendance.length} hari tercatat'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.push(
                s.isStaff
                    ? '/teacher/students/${u.id}'
                    : '/student/memorization',
              ),
              child: const Text('Lihat riwayat hafalan'),
            ),
            if (s.role == UserRole.student && attendance.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Riwayat presensi'),
                children: [
                  for (final e in attendance)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(Formatters.dateText(e.text('date'))),
                      trailing: StatusPill(
                        e.text('status'),
                        positive: e.text('status') == 'Hadir',
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
