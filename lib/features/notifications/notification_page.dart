import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/notification_service.dart';
import '../../core/utils/formatters.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/widgets/common.dart';

class NotificationPage extends ConsumerWidget {
  const NotificationPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final items = NotificationService.build(s);
    return PageFrame(
      title: 'Pemberitahuan',
      actions: [
        IconButton(
          tooltip: 'Tandai semua dibaca',
          icon: const Icon(Icons.done_all),
          onPressed: () => runAction(
            context,
            s,
            () => s.markRead(items.map((e) => e.id)),
            success: null,
          ),
        ),
      ],
      children: [
        if (items.isEmpty) const EmptyState('Belum ada pemberitahuan'),
        for (final e in items)
          DataTile(
            title: e.title,
            subtitle: '${e.body}\n${Formatters.dateTime(e.date)}',
            icon: s.readIds.contains(e.id)
                ? Icons.notifications_none
                : Icons.notifications_active_outlined,
            onTap: () async {
              final ok = await runAction(
                context,
                s,
                () => s.markRead([e.id]),
                success: null,
              );
              if (ok && context.mounted) context.push(e.route);
            },
          ),
      ],
    );
  }
}
