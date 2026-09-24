import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

enum ShareSessionMode { share, sync }

enum SyncScope { all, sales, products }

/// A short-lived capability encoded in the pairing QR code.
///
/// The secret never appears in Nearby advertising. It is only used after the
/// encrypted Nearby connection is established, so a nearby device cannot start
/// a transfer simply by discovering the advertiser.
class ShareSession {
  static const _qrPrefix = 'SMXN1.';
  static const lifetime = Duration(minutes: 5);

  final String id;
  final String secret;
  final DateTime expiresAt;
  final ShareSessionMode mode;
  final SyncScope scope;

  const ShareSession({
    required this.id,
    required this.secret,
    required this.expiresAt,
    this.mode = ShareSessionMode.share,
    this.scope = SyncScope.all,
  });

  bool get isSync => mode == ShareSessionMode.sync;

  factory ShareSession.create({
    ShareSessionMode mode = ShareSessionMode.share,
    SyncScope scope = SyncScope.all,
  }) {
    final random = Random.secure();
    final secretBytes = List<int>.generate(32, (_) => random.nextInt(256));
    return ShareSession(
      id: const Uuid().v4(),
      secret: base64UrlEncode(secretBytes).replaceAll('=', ''),
      expiresAt: DateTime.now().toUtc().add(lifetime),
      mode: mode,
      scope: scope,
    );
  }

  /// Small identifier safe to expose in the Nearby endpoint name. The receiver
  /// uses it to select the advertiser associated with its scanned QR code.
  String get discoveryKey =>
      id.replaceAll('-', '').substring(0, 8).toUpperCase();

  String get advertisedEndpointName => 'SMX-$discoveryKey';

  /// A proof derived from the QR-only secret. It authenticates the transfer
  /// payload without putting the secret itself on the Nearby transport.
  String get proof => sha256.convert(utf8.encode('$id.$secret')).toString();

  bool get isExpired => !DateTime.now().toUtc().isBefore(expiresAt);

  String toQrPayload() {
    final value = <String, dynamic>{
      'v': 1,
      'id': id,
      'key': secret,
      'exp': expiresAt.millisecondsSinceEpoch,
      if (mode != ShareSessionMode.share) 'm': mode.name,
      if (scope != SyncScope.all) 's': scope.name,
    };
    return '$_qrPrefix${base64UrlEncode(utf8.encode(jsonEncode(value)))}';
  }

  static ShareSession? tryParseQrPayload(String value) {
    try {
      if (!value.startsWith(_qrPrefix)) return null;
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(value.substring(_qrPrefix.length))),
      );
      if (decoded is! Map ||
          decoded['v'] != 1 ||
          decoded['id'] is! String ||
          decoded['key'] is! String ||
          decoded['exp'] is! int) {
        return null;
      }
      final modeName = decoded['m'] as String?;
      final mode = modeName == ShareSessionMode.sync.name
          ? ShareSessionMode.sync
          : ShareSessionMode.share;
      final scopeName = decoded['s'] as String?;
      final scope = SyncScope.values.firstWhere(
        (s) => s.name == scopeName,
        orElse: () => SyncScope.all,
      );
      final session = ShareSession(
        id: decoded['id'] as String,
        secret: decoded['key'] as String,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(
          decoded['exp'] as int,
          isUtc: true,
        ),
        mode: mode,
        scope: scope,
      );
      return session.id.length >= 8 && session.secret.length >= 32
          ? session
          : null;
    } catch (_) {
      return null;
    }
  }
}
