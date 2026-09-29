import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/edit_dialog.dart';
import '../spp/spp_data.dart';

class SubscriptionSettingsPage extends ConsumerWidget {
  const SubscriptionSettingsPage({super.key});

  Future<void> _edit(BuildContext context, AppStore s) async {
    final current = s.items('subscription_setting').firstOrNull;
    await editDialog(
      context,
      s,
      title: 'Atur harga langganan',
      initial: {
        'monthly_price': current?.number('monthly_price', 10000) ?? 10000,
        'annual_price': current?.number('annual_price', 100000) ?? 100000,
      },
      fields: const [
        FieldSpec('monthly_price', 'Harga 1 bulan', number: true),
        FieldSpec('annual_price', 'Harga 1 tahun', number: true),
      ],
      onSave: (data) => s.repository.subscriptionAction('settings', data),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final current = s.items('subscription_setting').firstOrNull;
    final monthly = current?.number('monthly_price', 10000) ?? 10000;
    final annual = current?.number('annual_price', 100000) ?? 100000;
    return PageFrame(
      title: 'Harga langganan',
      subtitle: 'Harga berlaku untuk seluruh instansi.',
      children: [
        StatGrid([
          (
            label: 'Paket 1 bulan',
            value: rupiah(monthly),
            icon: Icons.calendar_month_outlined,
          ),
          (
            label: 'Paket 1 tahun',
            value: rupiah(annual),
            icon: Icons.event_available_outlined,
          ),
        ]),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: s.busy ? null : () => _edit(context, s),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Ubah harga langganan'),
        ),
      ],
    );
  }
}
