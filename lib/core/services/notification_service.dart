import '../../shared/models/models.dart';
import '../../shared/providers/app_provider.dart';

class InboxItem {
  const InboxItem(this.id, this.title, this.body, this.route, this.date);
  final String id, title, body, route;
  final DateTime date;
}

class NotificationService {
  static List<InboxItem> build(AppStore s) {
    final now = DateTime.now();
    final items = <InboxItem>[
      if (s.isManager)
        for (final e in s.items('spp_payment').where((p) {
          final reportedAt = DateTime.tryParse(p.text('reported_at'));
          return p.text('status') == 'reported' &&
              reportedAt != null &&
              now.difference(reportedAt).inHours >= 24;
        }))
          InboxItem(
            'spp-overdue:${e.id}:${e.text('reported_at')}',
            'Pembayaran belum disetujui lebih dari 24 jam',
            '${s.member(e.text('student_id'))?.name ?? 'Santri'} • buka bukti dan segera setujui',
            '/spp/payment/${e.id}',
            DateTime.tryParse(e.text('reported_at')) ?? e.createdAt,
          ),
      for (final e
          in s
              .items('spp_payment')
              .where(
                (p) => s.isManager
                    ? p.text('reported_at').isNotEmpty ||
                          p.text('reviewed_at').isNotEmpty
                    : p.text('reviewed_at').isNotEmpty,
              ))
        InboxItem(
          'spp:${e.id}:${e.text('status')}:${e.text('reviewed_at')}',
          s.isManager
              ? 'Laporan pembayaran SPP'
              : 'Hasil pengecekan pembayaran',
          '${s.member(e.text('student_id'))?.name ?? 'Santri'} • ${e.text('status') == 'matched'
              ? 'Dana dicocokkan'
              : e.text('status') == 'disputed'
              ? 'Perlu klarifikasi'
              : 'Dilaporkan wali'}',
          '/spp/payment/${e.id}',
          DateTime.tryParse(e.text('reviewed_at')) ??
              DateTime.tryParse(e.text('reported_at')) ??
              e.createdAt,
        ),
      for (final e in s.items('announcement'))
        InboxItem(
          'announcement:${e.id}',
          e.text('title'),
          'Pengumuman baru',
          '/announcements',
          e.createdAt,
        ),
      for (final e in s.items('assignment'))
        InboxItem(
          'assignment:${e.id}',
          e.text('title'),
          'Tugas belajar',
          '/assignments',
          e.createdAt,
        ),
      if (s.role == UserRole.student) ...[
        for (final e in s.items('memorization'))
          InboxItem(
            'memorization:${e.id}',
            e.text('title'),
            'Catatan setoran telah ditambahkan',
            '/student/memorization',
            e.createdAt,
          ),
        for (final e
            in s.items('submission').where((e) => e.data['score'] != null))
          InboxItem(
            'grade:${e.id}:${e.text('gradedAt')}',
            'Tugas sudah dinilai',
            'Nilai ${e.number('score')}/100',
            '/assignments',
            DateTime.tryParse(e.text('gradedAt')) ?? e.createdAt,
          ),
      ] else
        for (final e in s.items('submission'))
          InboxItem(
            'submission:${e.id}',
            s.member(e.text('studentId'))?.name ?? 'Siswa',
            'Jawaban tugas telah dikumpulkan',
            '/assignments',
            e.createdAt,
          ),
    ];
    return items..sort((a, b) => b.date.compareTo(a.date));
  }
}
