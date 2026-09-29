import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app/theme.dart';
import '../../app/navigation/main_navigation.dart';
import '../../core/utils/formatters.dart';
import '../../core/services/notification_service.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/widgets/common.dart';

typedef _Menu = ({String title, IconData icon, String route});

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final u = s.user;
    if (u == null) return const SizedBox.shrink();
    final student = u.role == UserRole.student;
    final developer = u.role == UserRole.developer;
    final admin = s.isManager;
    final menus =
        <_Menu>[
              if (student || admin)
                (
                  title: 'Pembayaran SPP',
                  icon: Icons.account_balance_wallet_outlined,
                  route: '/spp',
                ),
              if (admin)
                (
                  title: 'Pengaturan QRIS',
                  icon: Icons.qr_code_rounded,
                  route: '/spp/settings',
                ),
              if (u.role == UserRole.leader) ...[
                (
                  title: 'Admin pondok',
                  icon: Icons.admin_panel_settings_outlined,
                  route: '/leader/admins',
                ),
              ],
              if (developer)
                (
                  title: 'Pimpinan instansi',
                  icon: Icons.supervisor_account_outlined,
                  route: '/developer/leaders',
                ),
              if (student) ...[
                (
                  title: 'Langganan aplikasi',
                  icon: Icons.workspace_premium_outlined,
                  route: '/subscription',
                ),
                (
                  title: 'Hafalan',
                  icon: Icons.menu_book_outlined,
                  route: '/student/memorization',
                ),
                (
                  title: 'Kartu siswa',
                  icon: Icons.badge_outlined,
                  route: '/student/qr',
                ),
              ],
              if (s.isStaff) ...[
                (
                  title: 'Siswa',
                  icon: Icons.people_outline,
                  route: admin ? '/admin/students' : '/teacher/students',
                ),
                (
                  title: 'Presensi',
                  icon: Icons.fact_check_outlined,
                  route: '/attendance',
                ),
              ],
              if (!developer) ...[
                (
                  title: 'Materi',
                  icon: Icons.library_books_outlined,
                  route: '/materials',
                ),
                (
                  title: 'Tugas',
                  icon: Icons.edit_note_rounded,
                  route: '/assignments',
                ),
                (
                  title: 'Jadwal',
                  icon: Icons.calendar_month_outlined,
                  route: '/schedules',
                ),
                (
                  title: 'Perkembangan',
                  icon: Icons.bar_chart_rounded,
                  route: '/progress',
                ),
                (
                  title: 'Pengumuman',
                  icon: Icons.campaign_outlined,
                  route: '/announcements',
                ),
              ],
              if (admin) ...[
                (
                  title: 'Guru',
                  icon: Icons.co_present_outlined,
                  route: '/admin/teachers',
                ),
                (
                  title: 'Kelas',
                  icon: Icons.meeting_room_outlined,
                  route: '/admin/classes',
                ),
                (
                  title: 'Akademik',
                  icon: Icons.tune_rounded,
                  route: '/admin/academic',
                ),
              ],
              if (developer) ...[
                (
                  title: 'Harga langganan',
                  icon: Icons.payments_outlined,
                  route: '/subscription/settings',
                ),
                (
                  title: 'Instansi',
                  icon: Icons.apartment_outlined,
                  route: '/developer/tenants',
                ),
                (
                  title: 'Admin instansi',
                  icon: Icons.admin_panel_settings_outlined,
                  route: '/developer/admins',
                ),
                (
                  title: 'Profil',
                  icon: Icons.person_outline,
                  route: '/profile',
                ),
              ],
            ]
            .where((menu) => !MainTabs.isRoot(u.role, menu.route))
            .toList(growable: false);
    final schedules =
        s
            .items('schedule')
            .where((e) => e.number('weekday') == DateTime.now().weekday)
            .toList()
          ..sort((a, b) => a.text('startTime').compareTo(b.text('startTime')));
    final news = s.items('announcement');
    final unreadNotifications = NotificationService.build(
      s,
    ).where((item) => !s.readIds.contains(item.id)).length;
    return PageFrame(
      title: 'Beranda',
      actions: [
        if (!developer)
          IconButton(
            tooltip: 'Pemberitahuan',
            onPressed: () => context.push('/notifications'),
            icon: unreadNotifications == 0
                ? const Icon(Icons.notifications_none_rounded)
                : Badge.count(
                    count: unreadNotifications,
                    child: const Icon(Icons.notifications_active_outlined),
                  ),
          ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: IconButton(
            tooltip: 'Profil saya',
            onPressed: () => context.push('/profile'),
            icon: CircleAvatar(
              radius: 17,
              backgroundColor: const Color(0xFFE7EEEB),
              child: Text(
                u.name.trim().isEmpty
                    ? '?'
                    : u.name.trim().substring(0, 1).toUpperCase(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.primary,
                ),
              ),
            ),
          ),
        ),
      ],
      children: [
        Row(
          children: [
            const Icon(Icons.school_outlined, size: 16, color: AppTheme.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                developer
                    ? 'PENGELOLA PLATFORM'
                    : s.tenant?.name ?? 'Ruang belajar',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.muted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Text(
          'Assalamu’alaikum,',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.muted),
        ),
        const SizedBox(height: 4),
        Text(u.name, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 8),
        Text(
          '${student ? s.className(u.classId) : u.role.label}  ·  ${Formatters.date(DateTime.now())}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: AppTheme.primary,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student
                              ? 'SEDIKIT DEMI SEDIKIT, ISTIQAMAH'
                              : developer
                              ? 'RINGKASAN PLATFORM'
                              : 'RUANG BIMBINGAN',
                          style: const TextStyle(
                            fontSize: 10,
                            letterSpacing: 1.1,
                            color: Color(0xFFD1E5DE),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          student
                              ? 'Jaga hafalan,\nlanjutkan langkah.'
                              : developer
                              ? 'Pendidikan yang\nterhubung.'
                              : 'Dampingi setiap\nproses belajar.',
                          style: const TextStyle(
                            fontSize: 25,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.5,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF327A6F),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      student
                          ? Icons.auto_stories_outlined
                          : developer
                          ? Icons.apartment_rounded
                          : Icons.qr_code_scanner_rounded,
                      color: const Color(0xFFF0D5A4),
                      size: 30,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              if (student) ...[
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${s.completed(u.id)} dari ${s.target(u.id)} bagian tuntas',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      '${(s.progress(u.id) * 100).round()}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: s.progress(u.id),
                  minHeight: 5,
                  color: const Color(0xFFE3C78F),
                  backgroundColor: const Color(0xFF438679),
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 18),
              ],
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppTheme.primary,
                  minimumSize: const Size(double.infinity, 46),
                ),
                onPressed: () => context.push(
                  student
                      ? '/student/qr'
                      : developer
                      ? '/developer/tenants'
                      : u.role == UserRole.teacher
                      ? '/teacher/scan'
                      : '/progress',
                ),
                icon: Icon(
                  student
                      ? Icons.badge_outlined
                      : developer
                      ? Icons.apartment_outlined
                      : u.role == UserRole.teacher
                      ? Icons.qr_code_scanner
                      : Icons.bar_chart_rounded,
                  size: 19,
                ),
                label: Text(
                  student
                      ? 'Buka kartu siswa'
                      : developer
                      ? 'Kelola instansi'
                      : u.role == UserRole.teacher
                      ? 'Pindai kartu siswa'
                      : 'Lihat laporan perkembangan',
                ),
              ),
            ],
          ),
        ),
        if (!student) ...[
          const SizedBox(height: 18),
          StatGrid(
            developer
                ? [
                    (
                      label: 'Instansi aktif',
                      value: '${s.tenants.where((t) => t.isActive).length}',
                      icon: Icons.apartment_outlined,
                    ),
                    (
                      label: 'Perlu diperbarui',
                      value: '${s.tenants.where((t) => !t.isActive).length}',
                      icon: Icons.event_busy_outlined,
                    ),
                  ]
                : [
                    (
                      label: 'Siswa bimbingan',
                      value: '${s.members(UserRole.student).length}',
                      icon: Icons.people_outline,
                    ),
                    (
                      label: 'Setoran tercatat',
                      value: '${s.items('memorization').length}',
                      icon: Icons.menu_book_outlined,
                    ),
                  ],
          ),
        ],
        if (menus.isNotEmpty) ...[
          const SizedBox(height: 12),
          SectionTitle(developer ? 'Pengelolaan' : 'Layanan akademik'),
          _MenuGrid(menus),
        ],
        if (!developer) ...[
          const SizedBox(height: 18),
          SectionTitle(
            'Agenda hari ini',
            action: 'Semua jadwal',
            onAction: () => context.push('/schedules'),
          ),
          for (final e in schedules.take(3))
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => context.push('/schedules'),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppTheme.amber,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 52,
                        child: Column(
                          children: [
                            Text(
                              e.text('startTime'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              e.text('endTime'),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.text('title'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${s.className(e.text('classId'))} · ${e.text('room')}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          SectionTitle(
            'Kabar sekolah',
            action: 'Lihat semua',
            onAction: () => context.push('/announcements'),
          ),
          for (final e in news.take(2))
            DataTile(
              title: e.text('title'),
              subtitle: Formatters.date(e.createdAt),
              icon: Icons.campaign_outlined,
              onTap: () => context.push('/announcements'),
            ),
        ],
      ],
    );
  }
}

class _MenuGrid extends StatelessWidget {
  const _MenuGrid(this.items);
  final List<_Menu> items;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final columns = c.maxWidth >= 600
          ? 6
          : c.maxWidth < 300
          ? 2
          : 3;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (var i = 0; i < items.length; i++)
            SizedBox(
              width: (c.maxWidth - (columns - 1) * 10) / columns,
              child: Material(
                color: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFE2E8E7)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => context.push(items[i].route),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 18,
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(11),
                          decoration: BoxDecoration(
                            color: i % 3 == 0
                                ? const Color(0xFFE7F0EB)
                                : i % 3 == 1
                                ? const Color(0xFFEDF0F6)
                                : const Color(0xFFF7EFDF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            items[i].icon,
                            size: 24,
                            color: i % 3 == 0
                                ? AppTheme.primary
                                : i % 3 == 1
                                ? const Color(0xFF546681)
                                : AppTheme.amber,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          items[i].title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
