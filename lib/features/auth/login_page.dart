import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../app/theme.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/edit_dialog.dart';
import '../../core/data/demo_seed.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    final s = ref.read(appProvider);
    await runAction(
      context,
      s,
      () => s.login(_email.text.trim(), _password.text),
      success: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(28),
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.primary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.auto_stories_rounded,
                            color: Color(0xFFF0D5A4),
                            size: 28,
                          ),
                          SizedBox(width: 12),
                          Text(
                            'E-LEARNING',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 28),
                      Text(
                        'Belajar dengan tekun.\nTumbuh dengan ilmu.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 25,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                          letterSpacing: -0.5,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Sekolah & Pesantren',
                        style: TextStyle(
                          color: Color(0xFFC8E0D5),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Masuk ke akun',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Gunakan akun yang diberikan oleh pengelola instansi.',
                  style: TextStyle(color: AppTheme.muted, fontSize: 14),
                ),
                const SizedBox(height: 32),
                Form(
                  key: _form,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _email,
                        enabled: !s.busy,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.username],
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.alternate_email),
                        ),
                        validator: (v) => v == null || !v.contains('@')
                            ? 'Masukkan email akun Anda.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        enabled: !s.busy,
                        obscureText: _obscure,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => _login(),
                        decoration: InputDecoration(
                          labelText: 'Kata sandi',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            tooltip: _obscure
                                ? 'Tampilkan kata sandi'
                                : 'Sembunyikan kata sandi',
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                            ),
                          ),
                        ),
                        validator: (v) => v == null || v.isEmpty
                            ? 'Masukkan kata sandi.'
                            : null,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: s.busy
                              ? null
                              : () async {
                                  await editDialog(
                                    context,
                                    s,
                                    title: 'Atur ulang kata sandi',
                                    fields: const [
                                      FieldSpec('email', 'Email akun'),
                                    ],
                                    initial: {'email': _email.text},
                                    onSave: (d) async {
                                      await s.repository.resetPassword(
                                        d['email'] as String,
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'Permintaan diterima. Jika email terdaftar, periksa tautan pemulihan pada email Anda.',
                                            ),
                                          ),
                                        );
                                      }
                                    },
                                  );
                                },
                          child: const Text('Lupa kata sandi?'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: s.busy ? null : _login,
                          child: Text(s.busy ? 'Memeriksa akun…' : 'Masuk'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                if (s.isDemo) ...[
                  const Divider(),
                  const SizedBox(height: 14),
                  const Text(
                    'Coba akun contoh',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: UserRole.values.reversed
                        .map(
                          (r) => ActionChip(
                            label: Text(r.label),
                            onPressed: s.busy
                                ? null
                                : () {
                                    _email.text =
                                        '${{UserRole.student: 'siswa', UserRole.teacher: 'guru', UserRole.admin: 'admin', UserRole.leader: 'pimpinan', UserRole.developer: 'developer'}[r]}@elearning.test';
                                    _password.text = DemoSeed.password;
                                  },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Mode demo • perubahan tersimpan di perangkat ini.',
                    style: TextStyle(fontSize: 12, color: AppTheme.muted),
                  ),
                ] else
                  const Text(
                    'Akun diberikan oleh admin sekolah atau pesantren Anda.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.muted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BlockedPage extends ConsumerWidget {
  const BlockedPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.school_outlined,
                    size: 64,
                    color: AppTheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Akses belum tersedia',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(s.blockedReason, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: s.busy
                        ? null
                        : () => runAction(context, s, s.refresh, success: null),
                    child: const Text('Periksa kembali'),
                  ),
                  TextButton(
                    onPressed: s.busy
                        ? null
                        : () => runAction(context, s, s.logout, success: null),
                    child: const Text('Keluar dari akun'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RecoveryPage extends ConsumerWidget {
  const RecoveryPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Kata sandi baru')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Tautan pemulihan sudah diterima. Buat kata sandi baru untuk akun Anda.',
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: s.busy
                  ? null
                  : () => editDialog(
                      context,
                      s,
                      title: 'Kata sandi baru',
                      fields: const [
                        FieldSpec(
                          'password',
                          'Kata sandi (minimal 8 karakter)',
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
                        await s.repository.changePassword(
                          d['password'] as String,
                        );
                        s.recovery = false;
                      },
                    ),
              child: const Text('Buat kata sandi'),
            ),
            TextButton(
              onPressed: () => runAction(context, s, s.logout, success: null),
              child: const Text('Keluar'),
            ),
          ],
        ),
      ),
    );
  }
}
