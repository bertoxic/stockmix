import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'share_session.dart';

/// The transfer file is self-validating before the receiver writes anything to
/// its database. It intentionally contains one Stockmix JSON bundle rather than
/// a platform file path, keeping the domain protocol portable.
class TransferEnvelope {
  static const _kind = 'stockmix-nearby-transfer';
  static const _version = 1;

  final String bundleJson;
  final String bundleSha256;

  const TransferEnvelope({
    required this.bundleJson,
    required this.bundleSha256,
  });

  static Uint8List encode({
    required ShareSession session,
    required Map<String, dynamic> bundle,
  }) {
    final bundleJson = jsonEncode(bundle);
    final envelope = <String, dynamic>{
      'kind': _kind,
      'version': _version,
      'sessionId': session.id,
      'sessionProof': session.proof,
      'bundleSha256': sha256.convert(utf8.encode(bundleJson)).toString(),
      'bundle': bundleJson,
    };
    return Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
  }

  static TransferEnvelope decode({
    required Uint8List bytes,
    required ShareSession session,
  }) {
    final raw = jsonDecode(utf8.decode(bytes));
    if (raw is! Map ||
        raw['kind'] != _kind ||
        raw['version'] != _version ||
        raw['sessionId'] != session.id ||
        raw['sessionProof'] != session.proof ||
        raw['bundle'] is! String ||
        raw['bundleSha256'] is! String) {
      throw const FormatException(
        'This transfer does not match the scanned QR code.',
      );
    }
    final bundleJson = raw['bundle'] as String;
    final digest = sha256.convert(utf8.encode(bundleJson)).toString();
    if (digest != raw['bundleSha256']) {
      throw const FormatException(
        'The received data failed its integrity check.',
      );
    }
    return TransferEnvelope(bundleJson: bundleJson, bundleSha256: digest);
  }

  static TransferEnvelope? tryDecode({
    required Uint8List bytes,
    required ShareSession session,
  }) {
    try {
      return decode(bytes: bytes, session: session);
    } catch (_) {
      return null;
    }
  }
}
