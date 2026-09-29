import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_provider.dart';
import '../theme.dart';

typedef MainTab = ({String label, String path, IconData icon});

/// Shared tab definitions keep the shell, selection, and page headers in sync.
class MainTabs {
  static List<MainTab> forRole(UserRole role) => [
    (label: 'Beranda', path: role.home, icon: Icons.home_outlined),
    if (role == UserRole.developer) ...[
      (
        label: 'Instansi',
        path: '/developer/tenants',
        icon: Icons.apartment_outlined,
      ),
      (
        label: 'Admin',
        path: '/developer/admins',
        icon: Icons.admin_panel_settings_outlined,
      ),
    ] else if (role == UserRole.leader) ...[
      (label: 'SPP', path: '/spp', icon: Icons.account_balance_wallet_outlined),
      (label: 'Perkembangan', path: '/progress', icon: Icons.bar_chart_rounded),
    ] else if (role == UserRole.admin) ...[
      (label: 'Siswa', path: '/admin/students', icon: Icons.groups_outlined),
      (
        label: 'Pengumuman',
        path: '/announcements',
        icon: Icons.campaign_outlined,
      ),
    ] else ...[
      (
        label: 'Jadwal',
        path: '/schedules',
        icon: Icons.calendar_month_outlined,
      ),
      (label: 'Tugas', path: '/assignments', icon: Icons.assignment_outlined),
    ],
    (label: 'Profil', path: '/profile', icon: Icons.person_outline),
  ];

  static bool isRoot(UserRole? role, String path) =>
      role != null && forRole(role).any((tab) => tab.path == path);
}

/// Entry shell after authentication. Only the four exact tab roots show the bar.
/// Detail/feature routes remain full pages and retain their normal back stack.
class MainNavigation extends ConsumerWidget {
  const MainNavigation({super.key, required this.path, required this.child});
  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(appProvider);
    if (store.role == null) return child;
    final tabs = MainTabs.forRole(store.role!);
    final selected = tabs.indexWhere((tab) => tab.path == path);
    if (selected < 0) return child;
    return PopScope(
      canPop: selected == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && selected != 0) context.go(store.home);
      },
      child: Scaffold(
        body: child,
        bottomNavigationBar: AppBottomNavigationBar(
          tabs: tabs,
          selectedIndex: selected,
          // Switching tabs replaces the location instead of stacking tab pages.
          onSelected: (index) {
            if (index != selected) context.go(tabs[index].path);
          },
        ),
      ),
    );
  }
}

class AppBottomNavigationBar extends StatelessWidget {
  const AppBottomNavigationBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
  });
  final List<MainTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(top: BorderSide(color: Color(0xFFE4E9E9))),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            for (var i = 0; i < tabs.length; i++)
              Expanded(
                child: Semantics(
                  selected: i == selectedIndex,
                  button: true,
                  child: InkWell(
                    key: ValueKey('main-tab-$i'),
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => onSelected(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            tabs[i].icon,
                            size: 23,
                            color: i == selectedIndex
                                ? AppTheme.primary
                                : const Color(0xFF77858C),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            tabs[i].label,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: i == selectedIndex
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: i == selectedIndex
                                  ? AppTheme.primary
                                  : const Color(0xFF77858C),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
