import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:vibration/vibration.dart';

class ScanFeedback {
  AudioPlayer? _player;
  bool _disposed = false;

  /// Called only after an authorized student has been resolved successfully.
  Future<void> success() async {
    if (_disposed) return;
    await Future.wait([_sound(), _vibrate()]);
  }

  Future<void> _sound() async {
    try {
      final player = _player ??= AudioPlayer();
      await player.stop();
      if (_disposed) return;
      await player.play(
        // AssetSource already uses the "assets/" prefix.
        AssetSource('sound/scan_success.mp3'),
        volume: 1,
        mode: PlayerMode.mediaPlayer,
      );
      // Keep the player alive until the short cue has finished.
      await Future<void>.delayed(const Duration(milliseconds: 350));
    } catch (e) {
      if (kDebugMode) debugPrint('Scan sound unavailable: $e');
    }
  }

  Future<void> _vibrate() async {
    try {
      if (!await Vibration.hasVibrator() || _disposed) return;
      final amplitude = await Vibration.hasAmplitudeControl();
      if (_disposed) return;
      await Vibration.vibrate(duration: 250, amplitude: amplitude ? 200 : -1);
    } catch (e) {
      if (kDebugMode) debugPrint('Scan vibration unavailable: $e');
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    try {
      await _player?.dispose();
    } catch (_) {}
  }
}
