import 'dart:convert';
import 'dart:typed_data';

import '../domain/share_session.dart';

enum PairingMessageType { hello, receipt }

/// Small control messages sent over the encrypted Nearby connection. The actual
/// Stockmix bundle travels as a file payload so large photo-inclusive exports do
/// not hit Nearby's byte-payload limit.
class PairingMessage {
  final PairingMessageType type;
  final String sessionId;
  final String proof;
  final String? bundleSha256;

  const PairingMessage._({
    required this.type,
    required this.sessionId,
    required this.proof,
    this.bundleSha256,
  });

  factory PairingMessage.hello(ShareSession session) => PairingMessage._(
    type: PairingMessageType.hello,
    sessionId: session.id,
    proof: session.proof,
  );

  factory PairingMessage.receipt(ShareSession session, String bundleSha256) =>
      PairingMessage._(
        type: PairingMessageType.receipt,
        sessionId: session.id,
        proof: session.proof,
        bundleSha256: bundleSha256,
      );

  bool matches(ShareSession session) =>
      !session.isExpired && sessionId == session.id && proof == session.proof;

  Uint8List encode() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'type': type.name,
        'sessionId': sessionId,
        'proof': proof,
        if (bundleSha256 != null) 'bundleSha256': bundleSha256,
      }),
    ),
  );

  static PairingMessage? tryDecode(Uint8List bytes) {
    try {
      final raw = jsonDecode(utf8.decode(bytes));
      if (raw is! Map ||
          raw['type'] is! String ||
          raw['sessionId'] is! String ||
          raw['proof'] is! String) {
        return null;
      }
      final type = PairingMessageType.values.where(
        (value) => value.name == raw['type'],
      );
      if (type.isEmpty) return null;
      return PairingMessage._(
        type: type.first,
        sessionId: raw['sessionId'] as String,
        proof: raw['proof'] as String,
        bundleSha256: raw['bundleSha256'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
