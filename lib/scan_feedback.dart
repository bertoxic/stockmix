import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Feedback failures must never interrupt an accepted scan or navigation.
class ScanFeedback {
  static const _channel = MethodChannel('com.bertoxic.stockmix/scan_feedback');

  static bool soundEnabled = true;
  static bool hapticsEnabled = true;

  static Future<void> success({bool? sound, bool? haptics}) async {
    final playSound = sound ?? soundEnabled;
    final playHaptics = haptics ?? hapticsEnabled;

    final tasks = <Future<void>>[];
    if (playHaptics) {
      tasks.add(_tryFeedback(HapticFeedback.mediumImpact));
      tasks.add(_tryFeedback(HapticFeedback.vibrate));
    }
    if (playSound) {
      tasks.add(_tryFeedback(() async {
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
          try {
            await _channel.invokeMethod<void>('playSuccess');
          } catch (_) {
            await SystemSound.play(SystemSoundType.click);
          }
        } else {
          await SystemSound.play(SystemSoundType.click);
        }
      }));
    }

    if (tasks.isNotEmpty) {
      await Future.wait(tasks);
    }
  }

  static Future<void> _tryFeedback(Future<void> Function() action) async {
    try {
      await action();
    } on PlatformException {
      // Sound or haptics may be unavailable on this device.
    } on MissingPluginException {
      // Some supported preview platforms have no feedback implementation.
    }
  }
}
