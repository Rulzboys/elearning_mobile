import 'package:flutter/material.dart';
import '../../app/theme.dart';

Future<T?> showAppDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) => showDialog<T>(
  context: context,
  builder: builder,
  barrierDismissible: barrierDismissible,
  animationStyle: MediaQuery.disableAnimationsOf(context)
      ? AnimationStyle.noAnimation
      : const AnimationStyle(
          duration: Duration(milliseconds: 200),
          reverseDuration: Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        ),
);

/// One dialog surface for forms, confirmations and printing.
/// Layout selection depends on screen size, never animated keyboard height.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.body,
    required this.footer,
    this.subtitle,
    this.icon = Icons.edit_note_rounded,
    this.danger = false,
    this.onClose,
    this.scrollController,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool danger;
  final Widget body, footer;
  final VoidCallback? onClose;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final compact =
        size.height < 500 || MediaQuery.textScalerOf(context).scale(1) > 1.4;
    final color = danger ? const Color(0xFFA34E37) : AppTheme.primary;
    final header = Padding(
      padding: const EdgeInsets.fromLTRB(22, 22, 12, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: danger ? const Color(0xFFFFF0EB) : const Color(0xFFE7F0EB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 25, color: color),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    height: 1.25,
                    letterSpacing: -.4,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: AppTheme.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Tutup formulir',
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.close_rounded,
              size: 20,
              color: AppTheme.muted,
            ),
          ),
        ],
      ),
    );
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      // Follow the platform's inset frames instead of restarting a second tween
      // on every keyboard frame. The focused field stays in the same subtree.
      insetAnimationDuration: Duration.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: compact
            ? SingleChildScrollView(
                controller: scrollController,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [header, body, footer],
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  header,
                  const Divider(height: 1, color: Color(0xFFE5EBE8)),
                  Flexible(
                    child: SingleChildScrollView(
                      controller: scrollController,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: RepaintBoundary(child: body),
                    ),
                  ),
                  footer,
                ],
              ),
      ),
    );
  }
}

class DialogActions extends StatelessWidget {
  const DialogActions({
    super.key,
    required this.label,
    required this.onConfirm,
    required this.onCancel,
    this.cancelLabel = 'Batal',
    this.icon = Icons.check_rounded,
    this.danger = false,
  });
  final String label, cancelLabel;
  final VoidCallback onConfirm, onCancel;
  final IconData icon;
  final bool danger;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
    decoration: const BoxDecoration(
      color: Color(0xFFFAFBFA),
      border: Border(top: BorderSide(color: Color(0xFFE5EBE8))),
    ),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(onPressed: onCancel, child: Text(cancelLabel)),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: onConfirm,
            style: FilledButton.styleFrom(
              backgroundColor: danger
                  ? const Color(0xFFA34E37)
                  : AppTheme.primary,
            ),
            icon: Icon(icon, size: 19),
            label: Text(label),
          ),
        ),
      ],
    ),
  );
}

Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  IconData icon = Icons.info_outline,
  bool danger = false,
}) async =>
    await showAppDialog<bool>(
      context,
      builder: (c) => AppDialog(
        title: title,
        icon: icon,
        danger: danger,
        subtitle: 'Konfirmasi tindakan',
        onClose: () => Navigator.pop(c, false),
        body: Padding(
          padding: const EdgeInsets.all(22),
          child: Text(
            message,
            style: const TextStyle(fontSize: 14, height: 1.6),
          ),
        ),
        footer: DialogActions(
          label: confirmLabel,
          icon: icon,
          danger: danger,
          onConfirm: () => Navigator.pop(c, true),
          onCancel: () => Navigator.pop(c, false),
        ),
      ),
    ) ??
    false;
