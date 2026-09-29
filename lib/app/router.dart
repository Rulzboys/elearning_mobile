import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/services/access_policy.dart';
import '../features/admin/academic_page.dart';
import '../features/admin/classes_page.dart';
import '../features/admin/users_page.dart';
import '../features/assignments/assignment_page.dart';
import '../features/attendance/attendance_page.dart';
import '../features/auth/login_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/developer/tenants_page.dart';
import '../features/learning/content_page.dart';
import '../features/memorization/memorization_page.dart';
import '../features/notifications/notification_page.dart';
import '../features/profile/profile_page.dart';
import '../features/progress/progress_page.dart';
import '../features/student/student_qr_page.dart';
import '../features/teacher/qr_scanner/qr_scanner_page.dart';
import '../shared/models/models.dart';
import '../shared/providers/app_provider.dart';
import 'navigation/main_navigation.dart';
import '../features/spp/spp_page.dart';
import '../features/spp/payment_page.dart';
import '../features/spp/qris_settings_page.dart';
import '../features/subscription/subscription_page.dart';
import '../features/subscription/subscription_settings_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final store = ref.read(appProvider);
  final router = GoRouter(
    initialLocation: '/login',
    refreshListenable: store,
    redirect: (context, state) {
      final path = state.uri.path;
      if (!store.hasSession) return path == '/login' ? null : '/login';
      if (store.recovery) {
        return path == '/auth/new-password' ? null : '/auth/new-password';
      }
      if (!store.canUse) return path == '/blocked' ? null : '/blocked';
      if ([
        '/',
        '/login',
        '/blocked',
        '/auth/new-password',
        '/login-callback',
      ].contains(path)) {
        return store.home;
      }
      if (!AccessPolicy.routeAllowed(store.role!, path)) return store.home;
      if (path == '/attendance' && !store.isStaff) return store.home;
      return null;
    },
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(title: const Text('Halaman tidak ditemukan')),
      body: Center(
        child: FilledButton(
          onPressed: () => context.go(store.home),
          child: const Text('Kembali ke beranda'),
        ),
      ),
    ),
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginPage()),
      GoRoute(path: '/blocked', builder: (_, __) => const BlockedPage()),
      GoRoute(
        path: '/auth/new-password',
        builder: (_, __) => const RecoveryPage(),
      ),
      GoRoute(
        path: '/login-callback',
        builder: (_, __) => const RecoveryPage(),
      ),
      ShellRoute(
        builder: (context, state, child) =>
            MainNavigation(path: state.uri.path, child: child),
        routes: [
          GoRoute(path: '/spp', builder: (_, __) => const SppPage()),
          GoRoute(
            path: '/spp/settings',
            builder: (_, __) => const QrisSettingsPage(),
          ),
          GoRoute(
            path: '/spp/invoice/:id',
            builder: (_, state) => InvoicePage(id: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/spp/payment/:id',
            builder: (_, state) => PaymentPage(id: state.pathParameters['id']!),
          ),
          GoRoute(
            path: '/subscription',
            builder: (_, __) => const SubscriptionPage(),
          ),
          GoRoute(
            path: '/subscription/settings',
            builder: (_, __) => const SubscriptionSettingsPage(),
          ),
          GoRoute(
            path: '/leader/admins',
            builder: (_, __) => const UsersPage(role: UserRole.admin),
          ),
          GoRoute(
            path: '/developer/leaders',
            builder: (_, __) => const UsersPage(role: UserRole.leader),
          ),
          for (final role in UserRole.values)
            GoRoute(path: role.home, builder: (_, __) => const DashboardPage()),
          GoRoute(
            path: '/student/qr',
            builder: (_, __) => const StudentQrPage(),
          ),
          GoRoute(
            path: '/student/memorization',
            builder: (_, __) => const MemorizationPage(),
          ),
          GoRoute(
            path: '/teacher/scan',
            builder: (_, __) => const QrScannerPage(),
          ),
          GoRoute(
            path: '/teacher/attendance/scan',
            builder: (_, __) => const QrScannerPage(attendanceMode: true),
          ),
          GoRoute(
            path: '/teacher/students',
            builder: (_, __) =>
                const UsersPage(role: UserRole.student, readOnly: true),
          ),
          GoRoute(
            path: '/teacher/cards/:id',
            builder: (_, state) =>
                StudentQrPage(studentId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/teacher/students/:id',
            builder: (_, state) =>
                MemorizationPage(studentId: state.pathParameters['id']),
          ),
          GoRoute(
            path: '/admin/students',
            builder: (_, __) => const UsersPage(role: UserRole.student),
          ),
          GoRoute(
            path: '/admin/teachers',
            builder: (_, __) => const UsersPage(role: UserRole.teacher),
          ),
          GoRoute(
            path: '/admin/classes',
            builder: (_, __) => const ClassesPage(),
          ),
          GoRoute(
            path: '/admin/academic',
            builder: (_, __) => const AcademicPage(),
          ),
          GoRoute(
            path: '/developer/tenants',
            builder: (_, __) => const TenantsPage(),
          ),
          GoRoute(
            path: '/developer/admins',
            builder: (_, __) => const UsersPage(role: UserRole.admin),
          ),
          GoRoute(
            path: '/announcements',
            builder: (_, __) => const ContentPage(kind: 'announcement'),
          ),
          GoRoute(
            path: '/materials',
            builder: (_, __) => const ContentPage(kind: 'material'),
          ),
          GoRoute(
            path: '/schedules',
            builder: (_, __) => const ContentPage(kind: 'schedule'),
          ),
          GoRoute(
            path: '/assignments',
            builder: (_, __) => const AssignmentPage(),
          ),
          GoRoute(
            path: '/attendance',
            builder: (_, __) => const AttendancePage(),
          ),
          GoRoute(path: '/progress', builder: (_, __) => const ProgressPage()),
          GoRoute(
            path: '/notifications',
            builder: (_, __) => const NotificationPage(),
          ),
          GoRoute(path: '/profile', builder: (_, __) => const ProfilePage()),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
