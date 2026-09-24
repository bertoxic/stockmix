import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:nearby_connections/nearby_connections.dart' as nearby;
import 'package:path_provider/path_provider.dart';

import 'nearby_transport_contract.dart';

NearbyTransport createNearbyTransport() => GoogleNearbyTransport();

/// The only place that talks to the Flutter Nearby plugin. The controllers use
/// the contract instead, so this can later be replaced with a Kotlin bridge
/// without changing the pairing or UI flow.
class GoogleNearbyTransport implements NearbyTransport {
  final nearby.Nearby _nearby = nearby.Nearby();
  final StreamController<NearbyTransportEvent> _events =
      StreamController<NearbyTransportEvent>.broadcast();
  final Map<int, _IncomingFile> _incomingFiles = {};
  final Map<int, String> _outgoingFiles = {};
  bool _closed = false;

  @override
  Stream<NearbyTransportEvent> get events => _events.stream;

  bool get _supported => Platform.isAndroid;

  void _log(String message) => debugPrint('[StockmixNearby] $message');

  void _emit(NearbyTransportEvent event) {
    if (!_closed) _events.add(event);
  }

  Future<bool> _unsupported() async {
    _emit(
      NearbyTransportError(
        UnsupportedError(
          'Direct nearby transfer is available on Android only.',
        ),
      ),
    );
    return false;
  }

  @override
  Future<bool> startAdvertising({required String endpointName}) async {
    if (!_supported) return _unsupported();
    try {
      _log('startAdvertising endpoint=$endpointName');
      final started = await _nearby.startAdvertising(
        endpointName,
        nearby.Strategy.P2P_POINT_TO_POINT,
        serviceId: stockmixNearbyServiceId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
      _log('startAdvertising result=$started');
      return started;
    } catch (error) {
      _log('startAdvertising error=$error');
      // Startup errors are returned to the controller directly. In particular,
      // a MissingPluginException means this is an old hot-reloaded binary, not
      // a nearby discovery failure.
      rethrow;
    }
  }

  @override
  Future<bool> startDiscovery({required String endpointName}) async {
    if (!_supported) return _unsupported();
    try {
      _log('startDiscovery endpoint=$endpointName');
      final started = await _nearby.startDiscovery(
        endpointName,
        nearby.Strategy.P2P_POINT_TO_POINT,
        serviceId: stockmixNearbyServiceId,
        onEndpointFound: (endpointId, endpointName, _) {
          _log('endpoint found id=$endpointId name=$endpointName');
          _emit(NearbyPeerFound(endpointId, endpointName));
        },
        onEndpointLost: (endpointId) {
          if (endpointId != null) {
            _log('endpoint lost id=$endpointId');
            _emit(NearbyPeerDisconnected(endpointId));
          }
        },
      );
      _log('startDiscovery result=$started');
      return started;
    } catch (error) {
      _log('startDiscovery error=$error');
      rethrow;
    }
  }

  @override
  Future<bool> requestConnection({
    required String endpointId,
    required String endpointName,
  }) async {
    if (!_supported) return _unsupported();
    try {
      _log('requestConnection endpoint=$endpointId name=$endpointName');
      return await _nearby.requestConnection(
        endpointName,
        endpointId,
        onConnectionInitiated: _onConnectionInitiated,
        onConnectionResult: _onConnectionResult,
        onDisconnected: _onDisconnected,
      );
    } catch (error) {
      _log('requestConnection error=$error');
      _emit(NearbyTransportError(error));
      return false;
    }
  }

  @override
  Future<bool> acceptConnection(String endpointId) async {
    if (!_supported) return _unsupported();
    try {
      _log('acceptConnection endpoint=$endpointId');
      return await _nearby.acceptConnection(
        endpointId,
        onPayLoadRecieved: _onPayloadReceived,
        onPayloadTransferUpdate: _onPayloadTransferUpdate,
      );
    } catch (error) {
      _log('acceptConnection error=$error');
      _emit(NearbyTransportError(error));
      return false;
    }
  }

  @override
  Future<void> sendBytes(String endpointId, Uint8List bytes) async {
    if (!_supported) {
      await _unsupported();
      return;
    }
    try {
      _log('sendBytes endpoint=$endpointId bytes=${bytes.length}');
      await _nearby.sendBytesPayload(endpointId, bytes);
    } catch (error) {
      _log('sendBytes error=$error');
      _emit(NearbyTransportError(error));
      rethrow;
    }
  }

  @override
  Future<void> sendFile({
    required String endpointId,
    required Uint8List bytes,
    required String filename,
  }) async {
    if (!_supported) {
      await _unsupported();
      return;
    }
    final safeName = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}${Platform.pathSeparator}${DateTime.now().microsecondsSinceEpoch}-$safeName',
    );
    try {
      _log('sendFile preparing endpoint=$endpointId bytes=${bytes.length}');
      await file.writeAsBytes(bytes, flush: true);
      _log('sendFile wrote path=${file.path} length=${await file.length()}');
      final payloadId = await _nearby.sendFilePayload(endpointId, file.path);
      _outgoingFiles[payloadId] = file.path;
      _log('sendFile payload=$payloadId queued');
    } catch (error) {
      _log('sendFile error=$error');
      await _deleteIfPresent(file.path);
      _emit(NearbyTransportError(error));
      rethrow;
    }
  }

  void _onConnectionInitiated(String endpointId, nearby.ConnectionInfo info) {
    _log('connection initiated endpoint=$endpointId name=${info.endpointName}');
    _emit(
      NearbyConnectionInitiated(
        endpointId: endpointId,
        endpointName: info.endpointName,
        authenticationToken: info.authenticationToken,
      ),
    );
  }

  void _onConnectionResult(String endpointId, nearby.Status status) {
    _log('connection result endpoint=$endpointId status=$status');
    final mapped = switch (status) {
      nearby.Status.CONNECTED => NearbyConnectionStatus.connected,
      nearby.Status.REJECTED => NearbyConnectionStatus.rejected,
      nearby.Status.ERROR => NearbyConnectionStatus.error,
    };
    _emit(NearbyConnectionResult(endpointId, mapped));
  }

  void _onDisconnected(String endpointId) {
    _log('disconnected endpoint=$endpointId');
    _emit(NearbyPeerDisconnected(endpointId));
  }

  void _onPayloadReceived(String endpointId, nearby.Payload payload) {
    if (payload.type == nearby.PayloadType.BYTES) {
      final bytes = payload.bytes ?? Uint8List(0);
      _log(
        'bytes received endpoint=$endpointId payload=${payload.id} bytes=${bytes.length}',
      );
      _emit(NearbyBytesReceived(endpointId, bytes));
      return;
    }
    if (payload.type == nearby.PayloadType.FILE) {
      final uri = payload.uri;
      // `uri` is supplied on current Android versions. The plugin only exposes a
      // file path on Android 10 and below, so retain that compatibility path.
      // ignore: deprecated_member_use
      final legacyFilePath = payload.filePath;
      _log(
        'file announced endpoint=$endpointId payload=${payload.id} '
        'uri=${uri != null} legacyPath=${legacyFilePath != null}',
      );
      _incomingFiles[payload.id] = _IncomingFile(
        endpointId,
        uri: uri,
        legacyFilePath: legacyFilePath,
      );
      return;
    }
    _log('unknown payload endpoint=$endpointId payload=${payload.id} type=${payload.type}');
  }

  void _onPayloadTransferUpdate(
    String endpointId,
    nearby.PayloadTransferUpdate update,
  ) {
    final incoming = _incomingFiles.containsKey(update.id);
    _log(
      'file update endpoint=$endpointId payload=${update.id} incoming=$incoming '
      'status=${update.status} bytes=${update.bytesTransferred}/${update.totalBytes}',
    );
    _emit(
      NearbyFileProgress(
        endpointId: endpointId,
        transferred: update.bytesTransferred,
        total: update.totalBytes,
        status: switch (update.status) {
          nearby.PayloadStatus.SUCCESS => NearbyFileStatus.success,
          nearby.PayloadStatus.FAILURE => NearbyFileStatus.failure,
          nearby.PayloadStatus.IN_PROGRESS => NearbyFileStatus.inProgress,
          nearby.PayloadStatus.CANCELED => NearbyFileStatus.cancelled,
          nearby.PayloadStatus.NONE => NearbyFileStatus.none,
        },
        incoming: incoming,
      ),
    );
    if (update.status != nearby.PayloadStatus.IN_PROGRESS) {
      unawaited(_finishFilePayload(update.id, update.status));
    }
  }

  Future<void> _finishFilePayload(
    int payloadId,
    nearby.PayloadStatus status,
  ) async {
    final outgoingPath = _outgoingFiles.remove(payloadId);
    if (outgoingPath != null) {
      _log('outgoing payload=$payloadId finished status=$status');
      await _deleteIfPresent(outgoingPath);
    }

    final incoming = _incomingFiles.remove(payloadId);
    if (incoming == null) return;
    if (status != nearby.PayloadStatus.SUCCESS) {
      _log('incoming payload=$payloadId finished with status=$status');
      return;
    }
    String? copiedPath;
    try {
      _log('reading completed incoming payload=$payloadId');
      Uint8List bytes;
      if (incoming.legacyFilePath != null) {
        bytes = await File(incoming.legacyFilePath!).readAsBytes();
      } else if (incoming.uri != null) {
        final directory = await getTemporaryDirectory();
        copiedPath =
            '${directory.path}${Platform.pathSeparator}incoming-$payloadId.json';
        final copied = await _nearby.copyFileAndDeleteOriginal(
          incoming.uri!,
          copiedPath,
        );
        if (!copied) {
          throw StateError('Could not read the received transfer file.');
        }
        bytes = await File(copiedPath).readAsBytes();
      } else {
        throw StateError('Received file payload has no path or URI.');
      }
      _log('incoming payload=$payloadId read bytes=${bytes.length}');
      _emit(NearbyFileReceived(incoming.endpointId, bytes));
    } catch (error) {
      _log('reading incoming payload=$payloadId error=$error');
      _emit(NearbyTransportError(error));
    } finally {
      if (copiedPath != null) await _deleteIfPresent(copiedPath);
      if (incoming.legacyFilePath != null) {
        await _deleteIfPresent(incoming.legacyFilePath!);
      }
    }
  }

  Future<void> _deleteIfPresent(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // A temporary transfer file can be cleaned by the OS if it is locked.
    }
  }

  @override
  Future<void> stop() async {
    if (!_supported) return;
    try {
      _log('stopping nearby transport');
      await _nearby.stopAdvertising();
      await _nearby.stopDiscovery();
      await _nearby.stopAllEndpoints();
    } catch (error) {
      _emit(NearbyTransportError(error));
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    await stop();
    _closed = true;
    for (final path in _outgoingFiles.values) {
      await _deleteIfPresent(path);
    }
    _outgoingFiles.clear();
    _incomingFiles.clear();
    await _events.close();
  }
}

class _IncomingFile {
  final String endpointId;
  final String? uri;
  final String? legacyFilePath;
  const _IncomingFile(
    this.endpointId, {
    required this.uri,
    required this.legacyFilePath,
  });
}
