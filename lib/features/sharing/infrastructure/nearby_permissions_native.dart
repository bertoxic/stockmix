import 'dart:io';

import 'package:flutter/services.dart';

const _platform = MethodChannel('com.bertoxic.stockmix/platform');

Future<void> ensureNearbyPermissions() async {
  if (!Platform.isAndroid) {
    throw UnsupportedError(
      'Direct nearby transfer is available on Android only.',
    );
  }

  // Nearby's Android 10 implementation verifies ACCESS_COARSE_LOCATION
  // directly. Requesting and checking it in the Activity avoids an ambiguous
  // grouped status from a Dart permission plugin.
  final granted =
      await _platform.invokeMethod<bool>('ensureNearbyPermissions') ?? false;
  if (!granted) {
    throw StateError(
      'Allow Location and nearby-device access to find the other Stockmix device.',
    );
  }
}
