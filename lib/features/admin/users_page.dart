import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/edit_dialog.dart';

class UsersPage extends ConsumerStatefulWidget {
  const UsersPage({super.key, required this.role, this.readOnly = false});
  final UserRole role;
  final bool readOnly;
  @override
  ConsumerState<UsersPage> createState() => _UsersPageState();
}

class _UsersPageState extends ConsumerState<UsersPage> {
  String query = '', filter = '';
  Future<void> _edit(AppStore s, [AppUser? u]) => editDialog(
    context,
    s,
    title:
        '${u == null ? 'Tambah' : 'Ubah'} ${widget.role.label.toLowerCase()}',
    initial: {
      'name': u?.name ?? '',
      'email': u?.email ?? '',
      'number': u?.number ?? '',
      'phone': u?.phone ?? '',
      'classId': u?.classId ?? '',
      'tenantId': u?.tenantId ?? '',
      'active': u?.active == false ? 'false' : 'true',
    },
    fields: [
      const FieldSpec('name', 'Nama lengkap'),
      if (u == null) const FieldSpec('email', 'Email'),
      FieldSpec(
        'password',
        u == null
            ? 'Kata sandi (minimal 8 karakter)'
            : 'Kata sandi baru (opsional)',
        required: u == null,
        secret: true,
      ),
      const FieldSpec('number', 'NIS / NIP', required: false),
      FieldSpec(
        'phone',
        widget.role == UserRole.student
            ? 'Nomor WhatsApp wali'
            : 'Nomor telepon',
        required: false,
      ),
      if (widget.role == UserRole.student)
        FieldSpec(
          'classId',
          'Kelas',
          required: false,
          options: {
            '': 'Belum ditentukan',
            for (final c in s.items('classroom')) c.id: c.text('name'),
          },
        ),
      if (s.role == UserRole.developer && u == null)
        FieldSpec(
          'tenantId',
          'Instansi',
          options: {for (final t in s.tenants) t.id: t.name},
        ),
      const FieldSpec(
        'active',
        'Status akun',
        options: {'true': 'Aktif', 'false': 'Nonaktif'},
      ),
    ],
    onSave: (d) => s.saveUser(
      AppUser(
        id: u?.id ?? newId(),
        name: d['name'] as String,
        email: u?.email ?? (d['email'] as String).toLowerCase(),
        role: widget.role,
        tenantId: s.role == UserRole.developer
            ? (u?.tenantId ?? d['tenantId'] as String)
            : s.user!.tenantId,
        classId: widget.role == UserRole.student && d['classId'] != ''
            ? d['classId'] as String
            : null,
        number: d['number'] as String,
        phone: d['phone'] as String,
        active: d['active'] == 'true',
      ),
      password: d['password'] as String?,
    ),
  );
  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final members = s
        .members(widget.role)
        .where(
          (u) =>
              '${u.name} ${u.email} ${u.number}'.toLowerCase().contains(
                query.toLowerCase(),
              ) &&
              (filter.isEmpty || u.classId == filter),
        )
        .toList();
    return PageFrame(
      title: widget.readOnly
          ? 'Siswa bimbingan'
          : 'Data ${widget.role.label.toLowerCase()}',
      subtitle: widget.readOnly
          ? 'Buka siswa untuk melihat perkembangan dan mencatat setoran.'
          : 'Kelola akun dan penempatan dalam instansi.',
      floatingActionButton: widget.readOnly
          ? null
          : FloatingActionButton.extended(
              onPressed: s.busy ? null : () => _edit(s),
              icon: const Icon(Icons.add),
              label: const Text('Tambah akun'),
            ),
      children: [
        TextField(
          decoration: const InputDecoration(
            hintText: 'Cari nama, email, atau nomor induk',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (v) => setState(() => query = v),
        ),
        const SizedBox(height: 12),
        if (widget.role == UserRole.student)
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Semua kelas'),
                selected: filter.isEmpty,
                onSelected: (_) => setState(() => filter = ''),
              ),
              for (final c in s.items('classroom'))
                ChoiceChip(
                  label: Text(c.text('name')),
                  selected: filter == c.id,
                  onSelected: (_) => setState(() => filter = c.id),
                ),
            ],
          ),
        const SizedBox(height: 16),
        if (members.isEmpty) const EmptyState('Belum ada akun yang sesuai'),
        for (final u in members)
          DataTile(
            title: u.name,
            icon: Icons.person_outline,
            subtitle:
                '${widget.role == UserRole.student ? '${s.className(u.classId)} • ' : ''}${u.email}${u.active ? '' : '\nNonaktif'}',
            onTap: widget.role == UserRole.student
                ? () => context.push('/teacher/students/${u.id}')
                : () => _edit(s, u),
            trailing: PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'card') {
                  context.push('/teacher/cards/${u.id}');
                } else if (v == 'edit') {
                  await _edit(s, u);
                } else if (await confirmDelete(context, u.name) &&
                    context.mounted) {
                  await runAction(context, s, () => s.removeUser(u));
                }
              },
              itemBuilder: (_) => [
                if (widget.role == UserRole.student)
                  const PopupMenuItem(
                    value: 'card',
                    child: Text('Kartu QR siswa'),
                  ),
                if (!widget.readOnly) ...[
                  const PopupMenuItem(value: 'edit', child: Text('Ubah akun')),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Hapus akun'),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}
