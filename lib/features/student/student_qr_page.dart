import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
// Already supplied and registered by this project's supabase_flutter 2.10.0.
// Keep this lib-only update compatible with the existing pubspec.
// ignore: depend_on_referenced_packages
import 'package:url_launcher/url_launcher.dart';
import '../../app/theme.dart';
import '../../core/services/card_print_host.dart';
import '../../core/services/student_card_code.dart';
import '../../core/services/student_card_document.dart';
import '../../shared/models/models.dart';
import '../../shared/providers/app_provider.dart';
import '../../shared/widgets/common.dart';
import '../../shared/widgets/app_dialog.dart';

class StudentQrPage extends ConsumerStatefulWidget {
  const StudentQrPage({super.key, this.studentId});
  final String? studentId;
  @override
  ConsumerState<StudentQrPage> createState() => _StudentQrPageState();
}

class _StudentQrPageState extends ConsumerState<StudentQrPage> {
  final _host = CardPrintHost();
  bool _preparing = false;
  String? _loadedPhotoPath;
  Future<Uint8List?>? _photoFuture;

  Future<Uint8List?> _photo(AppStore s, AppUser u) {
    if (_loadedPhotoPath != u.photoPath || _photoFuture == null) {
      _loadedPhotoPath = u.photoPath;
      _photoFuture = s.repository.downloadPrivateFile(
        'student-photos',
        u.photoPath,
      );
    }
    return _photoFuture!;
  }

  Future<String?> _photoPng(Uint8List? bytes) async {
    if (bytes == null || bytes.isEmpty) return null;
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 360);
    final frame = await codec.getNextFrame();
    codec.dispose();
    final source = frame.image;
    final side = source.width < source.height ? source.width : source.height;
    final left = (source.width - side) / 2;
    final top = (source.height - side) / 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImageRect(
      source,
      Rect.fromLTWH(left, top, side.toDouble(), side.toDouble()),
      const Rect.fromLTWH(0, 0, 320, 320),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final normalized = await picture.toImage(320, 320);
    final data = await normalized.toByteData(format: ui.ImageByteFormat.png);
    normalized.dispose();
    picture.dispose();
    source.dispose();
    return data == null ? null : base64Encode(data.buffer.asUint8List());
  }

  Future<void> _openPrint(String url) async {
    try {
      if (kIsWeb) {
        _host.openBrowser(url);
        return;
      }
      if (await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {
      /* Copy is available when no browser can handle the URL. */
    }
    await Clipboard.setData(ClipboardData(text: url));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Tautan disalin. Tempel pada kolom alamat browser di perangkat ini.',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_host.close());
    super.dispose();
  }

  AppUser? _student(AppStore s) {
    final u = widget.studentId == null ? s.user : s.member(widget.studentId!);
    if (!s.canUse ||
        u == null ||
        !u.active ||
        u.role != UserRole.student ||
        u.tenantId != s.user?.tenantId ||
        u.classId == null ||
        !(u.id == s.user?.id ||
            (s.isStaff && s.classIds.contains(u.classId)))) {
      return null;
    }
    return u;
  }

  Future<void> _printCard() async {
    if (_preparing) return;
    setState(() => _preparing = true);
    try {
      final s = ref.read(appProvider);
      await s.refresh();
      final u = _student(s);
      if (u == null) {
        throw const AppFailure(
          'Kartu tidak dapat diakses. Periksa status akun dan kelas siswa.',
        );
      }
      String? photoPng;
      try {
        photoPng = await _photoPng(await _photo(s, u));
      } catch (_) {
        // A missing/corrupt optional photo must not block printing the QR card.
      }
      final code = StudentCardCode.encode(u.tenantId!, u.id);
      // Include a quiet zone in the exported bitmap, not just the screen UI.
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.white, BlendMode.src);
      canvas.translate(64, 64);
      QrPainter(
        data: code,
        version: QrVersions.auto,
        gapless: true,
        errorCorrectionLevel: QrErrorCorrectLevel.M,
        eyeStyle: const QrEyeStyle(
          eyeShape: QrEyeShape.square,
          color: Colors.black,
        ),
        dataModuleStyle: const QrDataModuleStyle(
          dataModuleShape: QrDataModuleShape.square,
          color: Colors.black,
        ),
      ).paint(canvas, const Size(640, 640));
      final picture = recorder.endRecording();
      final image = await picture.toImage(768, 768);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      if (bytes == null) {
        throw const AppFailure('Kartu belum berhasil disiapkan. Coba lagi.');
      }
      if (!mounted) return;
      final url = await _host.prepare(
        studentCardDocument(
          name: u.name,
          school: s.tenant?.name ?? 'E-Learning',
          number: u.number,
          classroom: s.className(u.classId),
          qrPng: base64Encode(bytes.buffer.asUint8List()),
          photoPng: photoPng,
        ),
      );
      if (!mounted) {
        await _host.close();
        return;
      }
      // Preparation is complete; do not animate a loading spinner behind
      // the dialog while the user reviews print instructions.
      setState(() => _preparing = false);
      await showAppDialog<void>(
        context,
        builder: (c) => AppDialog(
          title: 'Cetak kartu siswa',
          subtitle: 'Simpan kartu untuk digunakan setiap hari.',
          icon: Icons.print_outlined,
          onClose: () => Navigator.pop(c),
          body: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Kartu siap dicetak',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Buka halaman kartu di browser, lalu pilih Cetak / Simpan PDF. Kartu ditempatkan di tengah halaman A4.',
                  style: TextStyle(height: 1.6),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F5F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Biarkan aplikasi terbuka di latar belakang sampai kartu selesai dimuat. Kirim file PDF jika ingin mencetak di perangkat lain.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: AppTheme.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          footer: DialogActions(
            label: 'Buka kartu',
            cancelLabel: 'Tutup',
            icon: Icons.open_in_new,
            onCancel: () => Navigator.pop(c),
            onConfirm: () => _openPrint(url),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    } finally {
      if (mounted) setState(() => _preparing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final u = _student(s);
    return PageFrame(
      title: 'Kartu siswa',
      subtitle:
          'Satu kartu untuk presensi, setoran hafalan, dan layanan siswa lainnya.',
      children: u == null
          ? [
              const EmptyState(
                'Kartu belum tersedia',
                message:
                    'Pastikan siswa aktif dan sudah ditempatkan dalam kelas.',
              ),
            ]
          : [
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 390),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: const Color(0xFFD5E2DC)),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(20),
                          color: AppTheme.primary,
                          child: Row(
                            children: [
                              const Icon(
                                Icons.auto_stories_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'E-LEARNING',
                                      style: TextStyle(
                                        color: Color(0xFFD4E7DF),
                                        fontSize: 10,
                                        letterSpacing: 2,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      s.tenant?.name ?? '',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(22),
                          child: Column(
                            children: [
                              const Text(
                                'KARTU SISWA',
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 2,
                                  color: AppTheme.muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 14),
                              FutureBuilder<Uint8List?>(
                                future: _photo(s, u),
                                builder: (context, snapshot) {
                                  final bytes = snapshot.data;
                                  return CircleAvatar(
                                    radius: 42,
                                    backgroundColor: const Color(0xFFE7F0EB),
                                    foregroundImage:
                                        bytes == null || bytes.isEmpty
                                        ? null
                                        : MemoryImage(bytes),
                                    child: bytes == null || bytes.isEmpty
                                        ? Text(
                                            u.name
                                                .trim()
                                                .split(RegExp(r'\s+'))
                                                .where(
                                                  (part) => part.isNotEmpty,
                                                )
                                                .take(2)
                                                .map((part) => part[0])
                                                .join()
                                                .toUpperCase(),
                                            style: const TextStyle(
                                              color: AppTheme.primary,
                                              fontSize: 22,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          )
                                        : null,
                                  );
                                },
                              ),
                              const SizedBox(height: 12),
                              Text(
                                u.name,
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 7),
                              Text(
                                '${s.className(u.classId)} · NIS ${u.number.isEmpty ? '—' : u.number}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppTheme.muted,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 16),
                              LayoutBuilder(
                                builder: (context, c) => QrImageView(
                                  data: StudentCardCode.encode(
                                    u.tenantId!,
                                    u.id,
                                  ),
                                  version: QrVersions.auto,
                                  errorCorrectionLevel: QrErrorCorrectLevel.M,
                                  backgroundColor: Colors.white,
                                  size: c.maxWidth.clamp(0, 260).toDouble(),
                                  padding: const EdgeInsets.all(20),
                                  semanticsLabel: 'QR kartu siswa ${u.name}',
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Gunakan untuk presensi, hafalan,\ndan layanan siswa lainnya.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  height: 1.6,
                                  color: AppTheme.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          color: const Color(0xFFF0F5F2),
                          child: const Text(
                            'KARTU PENGENAL BELAJAR',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 9,
                              letterSpacing: 1.7,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: _preparing ? null : _printCard,
                icon: _preparing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.print_outlined),
                label: Text(
                  _preparing ? 'Menyiapkan kartu…' : 'Cetak / Simpan PDF',
                ),
              ),
            ],
    );
  }
}
