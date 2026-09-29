import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/theme.dart';
import '../../app/navigation/main_navigation.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import 'app_dialog.dart';

String friendlyError(Object e) {
  if (e is AppFailure) return e.message;
  if (e is AuthException) {
    if (e.message.toLowerCase().contains('invalid login')) {
      return 'Email atau kata sandi tidak sesuai.';
    }
    if (e.message.toLowerCase().contains('rate limit')) {
      return 'Terlalu banyak percobaan. Tunggu sebentar lalu coba lagi.';
    }
    return 'Akun belum dapat diproses. Periksa email, kata sandi, dan koneksi Anda.';
  }
  if (e is PostgrestException && e.code == 'P0001') return e.message;
  if (e is FunctionException &&
      e.details is Map &&
      (e.details as Map)['error'] != null) {
    return (e.details as Map)['error'].toString();
  }
  return 'Proses belum berhasil. Periksa koneksi dan coba lagi.';
}

Future<bool> runAction(
  BuildContext context,
  AppStore store,
  Future<void> Function() action, {
  String? success = 'Perubahan tersimpan.',
}) async {
  try {
    await store.transaction(action);
    if (context.mounted && success != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    }
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
    return false;
  }
}

Future<bool> confirmDelete(BuildContext context, String label) => confirmAction(
  context,
  title: 'Hapus data?',
  message:
      'Hapus "$label"? Data yang masih digunakan akan tetap dipertahankan.',
  confirmLabel: 'Hapus',
  icon: Icons.delete_outline_rounded,
  danger: true,
);

class PageFrame extends ConsumerWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.children,
    this.actions,
    this.floatingActionButton,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final List<Widget> children;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(appProvider);
    final isHome = GoRouterState.of(context).uri.path == store.home;
    final isTabRoot = MainTabs.isRoot(
      store.role,
      GoRouterState.of(context).uri.path,
    );
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: isTabRoot
            ? null
            : IconButton(
                tooltip: 'Kembali',
                icon: const Icon(Icons.arrow_back_rounded, size: 22),
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go(store.home),
              ),
        title: isHome
            ? const Row(
                children: [
                  Icon(
                    Icons.auto_stories_rounded,
                    color: AppTheme.primary,
                    size: 24,
                  ),
                  SizedBox(width: 10),
                  Text('E-Learning'),
                ],
              )
            : Text(title),
        actions: actions,
      ),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            try {
              await store.refresh();
            } catch (_) {
              /* banner shows retry */
            }
          },
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  floatingActionButton == null ? 32 : 96,
                ),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (store.busy) const LinearProgressIndicator(minHeight: 2),
                  if (store.syncError != null)
                    NoteBox(store.syncError!, icon: Icons.cloud_off_outlined),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 20),
                      child: Text(
                        subtitle!,
                        style: const TextStyle(color: AppTheme.muted),
                      ),
                    ),
                  ...children,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState(
    this.title, {
    super.key,
    this.message = 'Data akan muncul di sini setelah ditambahkan.',
    this.icon = Icons.auto_stories_outlined,
  });
  final String title, message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
    child: Column(
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: const BoxDecoration(
            color: Color(0xFFE8EFED),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 32, color: AppTheme.primary),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.muted),
        ),
      ],
    ),
  );
}

class NoteBox extends StatelessWidget {
  const NoteBox(this.text, {super.key, this.icon = Icons.info_outline});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFEDF2F2),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppTheme.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

class DataTile extends StatelessWidget {
  const DataTile({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.menu_book_outlined,
    this.onTap,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leading: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2EF),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: AppTheme.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: subtitle == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 5),
              child: Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.5,
                  color: AppTheme.muted,
                ),
              ),
            ),
      onTap: onTap,
      trailing:
          trailing ??
          (onTap == null ? null : const Icon(Icons.chevron_right_rounded)),
    ),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.positive = true});
  final String text;
  final bool positive;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: positive ? const Color(0xFFEAF1E6) : const Color(0xFFFFF0DC),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: positive ? AppTheme.primary : const Color(0xFF865B22),
      ),
    ),
  );
}

class StatGrid extends StatelessWidget {
  const StatGrid(this.items, {super.key});
  final List<({String label, String value, IconData icon})> items;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final cols = c.maxWidth > 620 ? 4 : 2;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: items
            .map(
              (item) => SizedBox(
                width: (c.maxWidth - (cols - 1) * 12) / cols,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(item.icon, color: AppTheme.primary),
                        const SizedBox(height: 12),
                        Text(
                          item.value,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          item.label,
                          style: const TextStyle(color: AppTheme.muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
            .toList(),
      );
    },
  );
}

class HomeLink extends StatelessWidget {
  const HomeLink(this.title, this.subtitle, this.icon, this.route, {super.key});
  final String title, subtitle, route;
  final IconData icon;
  @override
  Widget build(BuildContext context) => DataTile(
    title: title,
    subtitle: subtitle,
    icon: icon,
    onTap: () => context.push(route),
  );
}
