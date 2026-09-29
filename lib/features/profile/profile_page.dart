import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../core/services/private_image_picker.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/app_dialog.dart';
import '../../shared/widgets/edit_dialog.dart';

class ProfilePage extends ConsumerStatefulWidget {
  const ProfilePage({super.key});

  @override
  ConsumerState<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends ConsumerState<ProfilePage> {
  String? _loadedPath;
  Future<Uint8List?>? _photo;

  Future<void> _changePhoto(AppStore s, AppUser u) async {
    try {
      final selected = await pickPrivateImage();
      if (selected == null || !mounted) return;
      await runAction(context, s, () async {
        await s.repository.saveProfilePhoto(
          tenantId: u.tenantId ?? 'platform',
          userId: u.id,
          bytes: selected.bytes,
          contentType: selected.contentType,
        );
      }, success: 'Foto profil berhasil diperbarui.');
      if (mounted) {
        setState(() {
          _loadedPath = null;
          _photo = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  Widget _avatar(AppStore s, AppUser u) {
    if (_loadedPath != u.photoPath || _photo == null) {
      _loadedPath = u.photoPath;
      _photo = s.repository.downloadPrivateFile('student-photos', u.photoPath);
    }
    return FutureBuilder<Uint8List?>(
      future: _photo,
      builder: (_, snapshot) => CircleAvatar(
        radius: 42,
        backgroundColor: const Color(0xFFE5EFEA),
        backgroundImage: snapshot.data == null
            ? null
            : MemoryImage(snapshot.data!),
        child: snapshot.data == null
            ? Text(
                u.name.trim().isEmpty ? '?' : u.name.trim()[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 30,
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final u = s.user;
    if (u == null) return const SizedBox.shrink();
    return PageFrame(
      title: 'Profil saya',
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          margin: const EdgeInsets.only(bottom: 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8E7)),
          ),
          child: Column(
            children: [
              _avatar(s, u),
              const SizedBox(height: 10),
              TextButton.icon(
                onPressed: s.busy ? null : () => _changePhoto(s, u),
                icon: const Icon(Icons.add_a_photo_outlined),
                label: Text(u.photoPath.isEmpty ? 'Tambah foto' : 'Ganti foto'),
              ),
              const SizedBox(height: 16),
              Text(
                u.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                u.email,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.muted, fontSize: 13),
              ),
              const SizedBox(height: 14),
              StatusPill(u.role.label),
            ],
          ),
        ),
        if (s.tenant != null)
          DataTile(
            title: s.tenant!.name,
            subtitle: s.tenant!.code,
            icon: Icons.school_outlined,
          ),
        if (u.role == UserRole.student)
          DataTile(
            title: s.className(u.classId),
            subtitle: 'Nomor induk ${u.number}',
            icon: Icons.badge_outlined,
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: s.busy
              ? null
              : () => editDialog(
                  context,
                  s,
                  title: 'Ubah profil',
                  initial: {'name': u.name, 'phone': u.phone},
                  fields: const [
                    FieldSpec('name', 'Nama lengkap'),
                    FieldSpec('phone', 'Nomor telepon', required: false),
                  ],
                  onSave: (d) => s.repository.updateSelf(
                    d['name'] as String,
                    d['phone'] as String,
                  ),
                ),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Ubah profil'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: s.busy
              ? null
              : () => editDialog(
                  context,
                  s,
                  title: 'Ubah kata sandi',
                  fields: const [
                    FieldSpec(
                      'password',
                      'Kata sandi baru (minimal 8 karakter)',
                      secret: true,
                    ),
                    FieldSpec('confirm', 'Ulangi kata sandi', secret: true),
                  ],
                  onSave: (d) async {
                    if ((d['password'] as String).length < 8 ||
                        d['password'] != d['confirm']) {
                      throw const AppFailure(
                        'Minimal 8 karakter dan kedua kata sandi harus sama.',
                      );
                    }
                    await s.repository.changePassword(d['password'] as String);
                  },
                ),
          icon: const Icon(Icons.lock_outline),
          label: const Text('Ubah kata sandi'),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: s.busy
              ? null
              : () async {
                  final yes = await confirmAction(
                    context,
                    title: 'Keluar dari akun?',
                    message:
                        'Data yang telah tersimpan dapat dibuka saat Anda masuk kembali.',
                    confirmLabel: 'Keluar',
                    icon: Icons.logout_rounded,
                  );
                  if (yes == true && context.mounted) {
                    await runAction(context, s, s.logout, success: null);
                  }
                },
          icon: const Icon(Icons.logout),
          label: const Text('Keluar'),
        ),
        const SizedBox(height: 24),
        const Center(
          child: Text('E-Learning • 1.0.0', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
