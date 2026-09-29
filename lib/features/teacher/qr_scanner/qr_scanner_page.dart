import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/services/scan_feedback.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/providers/app_provider.dart';
import '../../../shared/widgets/common.dart';

class QrScannerPage extends ConsumerStatefulWidget {
  const QrScannerPage({super.key, this.attendanceMode = false});
  final bool attendanceMode;
  @override
  ConsumerState<QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends ConsumerState<QrScannerPage>
    with WidgetsBindingObserver {
  final controller = MobileScannerController(
    autoStart: false,
    formats: [BarcodeFormat.qrCode],
    detectionSpeed: DetectionSpeed.normal,
    detectionTimeoutMs: 1000,
  );
  bool handling = false;
  final _feedback = ScanFeedback();
  Timer? _retryTimer;
  bool _verified = false;
  bool _starting = false;
  bool _foreground = true;
  bool _torch = false;
  String? error;
  String? lastStudentName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    if (!mounted || handling || _starting || !_foreground) return;
    _starting = true;
    setState(() => error = null);
    try {
      await controller.start();
      if (controller.value.error != null) throw controller.value.error!;
      if (!_foreground) await _stop();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Kamera belum dapat dibuka. Izinkan akses kamera pada pengaturan aplikasi, lalu kembali ke halaman ini.',
        );
      }
    } finally {
      _starting = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) {
      if (!handling) unawaited(_start());
    } else {
      unawaited(_stop());
    }
  }

  Future<void> _stop() async {
    try {
      await controller.stop();
    } catch (_) {
      /* Camera may already be detached. */
    }
    if (mounted) setState(() => _torch = false);
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    unawaited(_feedback.dispose());
    WidgetsBinding.instance.removeObserver(this);
    unawaited(controller.dispose());
    super.dispose();
  }

  Future<void> _resolve(String raw) async {
    if (handling || _retryTimer?.isActive == true || !_foreground || !mounted) {
      return;
    }
    setState(() {
      handling = true;
      error = null;
    });
    try {
      await _stop();
      final student = await ref.read(appProvider).resolveQr(raw);
      if (widget.attendanceMode) {
        final s = ref.read(appProvider);
        final day = Formatters.dayKey(DateTime.now());
        final previous = s
            .items('attendance')
            .where(
              (e) => e.text('studentId') == student.id && e.text('date') == day,
            )
            .firstOrNull;
        await s.save('attendance', {
          'studentId': student.id,
          'classId': student.classId,
          'date': day,
          'status': 'Hadir',
          'source': 'qr',
        }, previous: previous);
        lastStudentName = student.name;
      }
      if (!mounted || !_foreground) return;
      setState(() => _verified = true);
      await _feedback.success().timeout(
        const Duration(seconds: 2),
        onTimeout: () {},
      );
      if (mounted && _foreground && !widget.attendanceMode) {
        await context.push('/teacher/students/${student.id}');
      }
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) {
        setState(() => handling = false);
        setState(() => _verified = false);
        if (error == null) {
          await _start();
        } else {
          // Recover automatically after an invalid/unavailable QR; no retry button.
          _retryTimer?.cancel();
          _retryTimer = Timer(const Duration(seconds: 2), () {
            _retryTimer = null;
            if (mounted && _foreground) unawaited(_start());
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF101C1D),
    appBar: AppBar(
      backgroundColor: const Color(0xFF101C1D),
      foregroundColor: Colors.white,
      titleTextStyle: const TextStyle(
        color: Colors.white,
        fontSize: 18,
        fontWeight: FontWeight.w600,
      ),
      title: Text(
        widget.attendanceMode ? 'Scan presensi siswa' : 'Pindai kartu siswa',
      ),
      leading: IconButton(
        tooltip: 'Kembali',
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => context.canPop()
            ? context.pop()
            : context.go(ref.read(appProvider).home),
      ),
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, c) {
          final edge = math.min(
            c.maxWidth * .72,
            math.min(290.0, c.maxHeight * .45),
          );
          final frame = Rect.fromCenter(
            center: Offset(c.maxWidth / 2, c.maxHeight * .43),
            width: edge,
            height: edge,
          );
          return Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(
                controller: controller,
                scanWindow: frame,
                onDetect: (capture) {
                  final values = capture.barcodes
                      .map((b) => b.rawValue)
                      .whereType<String>();
                  if (values.isNotEmpty) unawaited(_resolve(values.first));
                },
                errorBuilder: (context, e) =>
                    const ColoredBox(color: Color(0xFF101C1D)),
              ),
              IgnorePointer(child: CustomPaint(painter: _ScanOverlay(frame))),
              Positioned(
                top: 20,
                left: 28,
                right: 28,
                child: Column(
                  children: [
                    Text(
                      widget.attendanceMode
                          ? 'Scan QR untuk mencatat hadir'
                          : 'Dekatkan kartu ke kamera',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.attendanceMode
                          ? 'Setiap QR yang berhasil dipindai otomatis tercatat Hadir hari ini.'
                          : 'Posisikan QR di dalam bingkai.\nKartu cetak maupun layar siswa dapat dipindai.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFC7D4D0),
                        fontSize: 12,
                        height: 1.6,
                      ),
                    ),
                  ],
                ),
              ),
              if (handling)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xDD101C1D),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: _verified
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.check_circle_rounded,
                                color: Color(0xFF9BDFC0),
                                size: 44,
                              ),
                              const SizedBox(height: 10),
                              Text(
                                widget.attendanceMode
                                    ? 'Presensi berhasil dicatat'
                                    : 'QR berhasil dipindai',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          )
                        : const CircularProgressIndicator(color: Colors.white),
                  ),
                ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 20,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (error != null)
                      Container(
                        padding: const EdgeInsets.all(14),
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFF324140),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    if (widget.attendanceMode && lastStudentName != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF214E47),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '$lastStudentName berhasil dicatat Hadir',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF61736C)),
                          ),
                          onPressed: handling
                              ? null
                              : () async {
                                  try {
                                    await controller.toggleTorch();
                                    if (mounted) {
                                      setState(() => _torch = !_torch);
                                    }
                                  } catch (_) {
                                    if (mounted) {
                                      setState(
                                        () => error =
                                            'Lampu kamera tidak tersedia.',
                                      );
                                    }
                                  }
                                },
                          icon: Icon(
                            _torch
                                ? Icons.flashlight_off_outlined
                                : Icons.flashlight_on_outlined,
                            size: 19,
                          ),
                          label: Text(_torch ? 'Matikan lampu' : 'Lampu'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Data siswa hanya dibuka untuk guru yang berwenang.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFFA9BCB4), fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class _ScanOverlay extends CustomPainter {
  const _ScanOverlay(this.frame);
  final Rect frame;
  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(frame, const Radius.circular(20));
    final mask = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRRect(hole);
    canvas.drawPath(mask, Paint()..color = const Color(0xAA101C1D));
    canvas.drawRRect(
      hole,
      Paint()
        ..color = const Color(0xFFD1E9DC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
    canvas.drawLine(
      Offset(frame.left + 16, frame.center.dy),
      Offset(frame.right - 16, frame.center.dy),
      Paint()
        ..color = const Color(0x557AE5B3)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_ScanOverlay oldDelegate) => oldDelegate.frame != frame;
}
