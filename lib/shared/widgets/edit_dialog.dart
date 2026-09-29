import 'package:flutter/material.dart';
import '../../app/theme.dart';
import '../models/models.dart';
import '../providers/app_provider.dart';
import 'common.dart';
import 'app_dialog.dart';

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.required = true,
    this.lines = 1,
    this.options,
    this.number = false,
    this.secret = false,
    this.date = false,
    this.time = false,
    this.hint,
  });
  final String key, label;
  final bool required, number, secret, date, time;
  final int lines;
  final Map<String, String>? options;
  final String? hint;
}

Future<void> editDialog(
  BuildContext context,
  AppStore store, {
  required String title,
  required List<FieldSpec> fields,
  Json initial = const {},
  required Future<void> Function(Json) onSave,
}) async {
  await showAppDialog<void>(
    context,
    barrierDismissible: false,
    builder: (_) => EditDialog(
      store: store,
      title: title,
      fields: fields,
      initial: initial,
      onSave: onSave,
    ),
  );
}

class EditDialog extends StatefulWidget {
  const EditDialog({
    super.key,
    required this.store,
    required this.title,
    required this.fields,
    required this.initial,
    required this.onSave,
  });
  final AppStore store;
  final String title;
  final List<FieldSpec> fields;
  final Json initial;
  final Future<void> Function(Json) onSave;
  @override
  State<EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<EditDialog> {
  final _form = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  bool _saving = false;
  final _scroll = ScrollController();
  final _visible = <String>{};
  late final Map<String, GlobalKey<FormFieldState<String>>> _fieldKeys;
  String? _error;
  @override
  void initState() {
    super.initState();
    _fieldKeys = {
      for (final f in widget.fields) f.key: GlobalKey<FormFieldState<String>>(),
    };
    _controllers = {
      for (final f in widget.fields)
        f.key: TextEditingController(
          text: widget.initial[f.key]?.toString() ?? '',
        ),
    };
    for (final f in widget.fields.where((f) => f.date)) {
      final date = DateTime.tryParse(_controllers[f.key]!.text)?.toLocal();
      if (date != null) {
        _controllers[f.key]!.text =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      }
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(FieldSpec f) async {
    if (f.time) {
      final parts = _controllers[f.key]!.text.split(':');
      final value = await showTimePicker(
        context: context,
        initialTime: parts.length == 2
            ? TimeOfDay(
                hour: (int.tryParse(parts[0]) ?? 7).clamp(0, 23),
                minute: (int.tryParse(parts[1]) ?? 0).clamp(0, 59),
              )
            : const TimeOfDay(hour: 7, minute: 0),
      );
      if (mounted && value != null) {
        _controllers[f.key]!.text =
            '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
      }
    } else {
      final now = DateTime.now();
      final first = DateTime(2000), last = DateTime(2100);
      var initial = DateTime.tryParse(_controllers[f.key]!.text) ?? now;
      if (initial.isBefore(first) || initial.isAfter(last)) initial = now;
      final value = await showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: first,
        lastDate: last,
      );
      if (mounted && value != null) {
        _controllers[f.key]!.text =
            '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_form.currentState!.validate()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        for (final key in _fieldKeys.values) {
          if (key.currentState?.hasError == true &&
              key.currentContext != null) {
            Scrollable.ensureVisible(
              key.currentContext!,
              duration: const Duration(milliseconds: 220),
            );
            break;
          }
        }
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final data = <String, dynamic>{...widget.initial};
    for (final f in widget.fields) {
      final s = _controllers[f.key]!.text.trim();
      data[f.key] = f.number ? int.tryParse(s) : s;
    }
    try {
      await widget.store.transaction(() => widget.onSave(data));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = friendlyError(e);
          _saving = false;
        });
        if (_scroll.hasClients)
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
      }
    }
  }

  Widget _field(FieldSpec f) {
    final decoration = InputDecoration(
      hintText:
          f.hint ??
          (f.options != null
              ? 'Pilih ${f.label.toLowerCase()}'
              : f.date
              ? 'Pilih tanggal'
              : f.time
              ? 'Pilih waktu'
              : null),
      filled: true,
      fillColor: const Color(0xFFF7F9F8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      errorMaxLines: 2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFDFE7E3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.primary, width: 1.5),
      ),
      suffixIcon: f.secret
          ? IconButton(
              tooltip: _visible.contains(f.key)
                  ? 'Sembunyikan kata sandi'
                  : 'Tampilkan kata sandi',
              onPressed: _saving
                  ? null
                  : () => setState(() {
                      if (!_visible.add(f.key)) _visible.remove(f.key);
                    }),
              icon: Icon(
                _visible.contains(f.key)
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
              ),
            )
          : f.date
          ? const Icon(Icons.calendar_today_outlined, size: 19)
          : f.time
          ? const Icon(Icons.schedule_rounded, size: 20)
          : null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text.rich(
            TextSpan(
              text: f.label,
              children: [
                TextSpan(
                  text: f.required ? ' *' : '  · Opsional',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                    color: f.required ? AppTheme.primary : AppTheme.muted,
                  ),
                ),
              ],
            ),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.ink,
            ),
          ),
        ),
        if (f.options != null)
          DropdownButtonFormField<String>(
            key: _fieldKeys[f.key],
            isExpanded: true,
            initialValue: f.options!.containsKey(_controllers[f.key]!.text)
                ? _controllers[f.key]!.text
                : null,
            decoration: decoration,
            icon: const Icon(
              Icons.expand_more_rounded,
              size: 21,
              color: AppTheme.muted,
            ),
            dropdownColor: Colors.white,
            borderRadius: BorderRadius.circular(12),
            menuMaxHeight: 300,
            items: f.options!.entries
                .map(
                  (e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(
                      e.value,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                )
                .toList(),
            onChanged: _saving
                ? null
                : (value) =>
                      setState(() => _controllers[f.key]!.text = value ?? ''),
            validator: (value) => f.required && (value == null || value.isEmpty)
                ? 'Pilih ${f.label.toLowerCase()}.'
                : null,
          )
        else
          TextFormField(
            key: _fieldKeys[f.key],
            controller: _controllers[f.key],
            enabled: !_saving,
            readOnly: f.date || f.time,
            onTap: f.date || f.time ? () => _pick(f) : null,
            obscureText: f.secret && !_visible.contains(f.key),
            maxLines: f.secret ? 1 : f.lines,
            style: const TextStyle(fontSize: 14, color: AppTheme.ink),
            keyboardType: f.number
                ? const TextInputType.numberWithOptions(signed: true)
                : f.lines > 1
                ? TextInputType.multiline
                : f.key.toLowerCase().contains('email')
                ? TextInputType.emailAddress
                : f.key.toLowerCase().contains('phone')
                ? TextInputType.phone
                : TextInputType.text,
            textInputAction: f.lines > 1
                ? TextInputAction.newline
                : TextInputAction.next,
            decoration: decoration,
            validator: (value) {
              if (f.required && (value == null || value.trim().isEmpty))
                return 'Kolom ini wajib diisi.';
              if (f.number &&
                  (value?.trim().isNotEmpty ?? false) &&
                  int.tryParse(value!.trim()) == null)
                return 'Masukkan angka bulat.';
              return null;
            },
          ),
      ],
    );
  }

  Widget _fields() => Padding(
    padding: const EdgeInsets.fromLTRB(22, 20, 22, 6),
    child: Form(
      key: _form,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1EE),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF0D2C9)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 20,
                    color: Color(0xFFA34E37),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: Color(0xFF853D2B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          for (final f in widget.fields)
            Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: _field(f),
            ),
        ],
      ),
    ),
  );

  Widget _footer() => Container(
    padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
    decoration: const BoxDecoration(
      color: Color(0xFFFAFBFA),
      border: Border(top: BorderSide(color: Color(0xFFE5EBE8))),
    ),
    child: Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 46)),
            child: const Text('Batal'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(minimumSize: const Size(0, 46)),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded, size: 19),
            label: Text(_saving ? 'Menyimpan…' : 'Simpan data'),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: AppDialog(
      title: widget.title,
      subtitle: 'Lengkapi data berikut. Tanda * wajib diisi.',
      onClose: _saving ? null : () => Navigator.pop(context),
      scrollController: _scroll,
      body: _fields(),
      footer: _footer(),
    ),
  );
}
