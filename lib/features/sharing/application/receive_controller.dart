import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../../stock_store.dart';
import '../domain/share_session.dart';
import '../domain/sync_service.dart';
import '../domain/transfer_envelope.dart';
import '../domain/transfer_state.dart';
import '../infrastructure/nearby_permissions.dart';
import '../infrastructure/nearby_transport.dart';
import '../infrastructure/pairing_service.dart';

class NearbyReceiveController extends ChangeNotifier {
  final StockStore store;
  final ShareSession session;
  final String receiverName;
  final NearbyTransport _transport;
  StreamSubscription<NearbyTransportEvent>? _subscription;
  Timer? _fileStartTimer;
  DirectTransferState _state = const DirectTransferState.preparing();
  String? _endpointId;
  bool _accepting = false;
  bool _helloSent = false;
  bool _transferProcessed = false;
  bool _syncSent = false;
  bool _peerConfirmed = false;
  bool _syncMergeChosen = false;
  bool mergingSync = false;
  String? _myBundleSha256;
  Map<String, dynamic>? _receivedSyncBundle;
  String? _syncSummary;
  bool _disposed = false;

  NearbyReceiveController({
    required this.store,
    required this.session,
    required this.receiverName,
    NearbyTransport? transport,
  }) : _transport = transport ?? createNearbyTransport();

  DirectTransferState get state => _state;
  bool get canMergeReceivedSync =>
      session.isSync &&
      _receivedSyncBundle != null &&
      state.phase == DirectTransferPhase.complete &&
      !_syncMergeChosen;

  Future<void> mergeReceivedSyncNow() async {
    if (!canMergeReceivedSync || mergingSync) return;
    mergingSync = true;
    final bundle = _receivedSyncBundle!;
    _set(
      state.copyWith(message: 'Merging received records…', clearProgress: true),
    );
    try {
      _syncSummary = await applySyncMerge(
        store: store,
        bundle: bundle,
        scope: session.scope,
      );
      _syncMergeChosen = true;
      mergingSync = false;
      _complete(_syncSummary!);
    } catch (error) {
      mergingSync = false;
      _syncMergeChosen = true;
      _complete('Saved for later merge. ${_messageFor(error)}');
    }
  }

  Future<void> start() async {
    _subscription ??= _transport.events.listen(_onEvent);
    _set(const DirectTransferState.preparing());
    try {
      if (session.isExpired) {
        throw const FormatException(
          'This pairing code expired. Ask the sender to start again.',
        );
      }
      await ensureNearbyPermissions();
      final started = await _transport.startDiscovery(
        endpointName: receiverName,
      );
      if (!started) {
        throw StateError('Could not look for the sender nearby.');
      }
      _set(
        DirectTransferState(
          phase: DirectTransferPhase.waitingForPeer,
          message: session.isSync
              ? 'Looking for the sync host nearby…'
              : 'Looking for the sender nearby…',
        ),
      );
    } catch (error) {
      _fail(_messageFor(error));
    }
  }

  Future<void> _onEvent(NearbyTransportEvent event) async {
    if (_disposed || state.isFinished) return;
    try {
      switch (event) {
        case NearbyPeerFound():
          if (_endpointId != null ||
              event.endpointName != session.advertisedEndpointName) {
            return;
          }
          _endpointId = event.endpointId;
          _set(
            DirectTransferState(
              phase: DirectTransferPhase.connecting,
              message: session.isSync
                  ? 'Connecting to the sync host…'
                  : 'Connecting to the sender…',
              peerName: event.endpointName,
            ),
          );
          final requested = await _transport.requestConnection(
            endpointId: event.endpointId,
            endpointName: receiverName,
          );
          if (!requested) throw StateError('Could not connect to the sender.');
        case NearbyConnectionInitiated():
          if (event.endpointId != _endpointId || _accepting) return;
          _accepting = true;
          final accepted = await _transport.acceptConnection(event.endpointId);
          if (!accepted) {
            throw StateError('Could not accept the nearby connection.');
          }
        case NearbyConnectionResult():
          if (event.endpointId != _endpointId) return;
          if (event.status != NearbyConnectionStatus.connected) {
            throw StateError('The sender did not accept the connection.');
          }
          _set(
            state.copyWith(
              phase: DirectTransferPhase.authenticating,
              message: 'Authenticating the scanned QR code…',
              clearProgress: true,
            ),
          );
          if (!_helloSent) {
            _helloSent = true;
            await _transport.sendBytes(
              event.endpointId,
              PairingMessage.hello(session).encode(),
            );
            if (session.isSync) {
              await _sendLocalSyncBundle(event.endpointId);
            }
            _fileStartTimer = Timer(const Duration(seconds: 30), () {
              _fail(
                'The transfer did not finish in time. Make sure both apps are on the newest build, then try again.',
              );
            });
          }
        case NearbyFileProgress():
          if (event.incoming && event.total > 0) {
            _fileStartTimer?.cancel();
            _fileStartTimer = Timer(const Duration(seconds: 30), () {
              _fail('The transfer timed out while receiving. Try again.');
            });
            if (event.status == NearbyFileStatus.failure ||
                event.status == NearbyFileStatus.cancelled) {
              throw StateError('The nearby transfer did not finish.');
            }
            _set(
              state.copyWith(
                phase: DirectTransferPhase.receiving,
                message: session.isSync
                    ? 'Syncing securely…'
                    : 'Receiving securely…',
                progress: event.transferred / event.total,
              ),
            );
          }
        case NearbyFileReceived():
          if (event.endpointId == _endpointId) {
            await _saveReceivedTransfer(event.bytes, event.endpointId);
          }
        case NearbyBytesReceived():
          if (event.endpointId == _endpointId && event.bytes.isNotEmpty) {
            final envelope = TransferEnvelope.tryDecode(
              bytes: event.bytes,
              session: session,
            );
            if (envelope != null) {
              await _saveReceivedTransfer(event.bytes, event.endpointId);
              return;
            }
            final message = PairingMessage.tryDecode(event.bytes);
            if (message != null &&
                message.type == PairingMessageType.receipt &&
                message.matches(session) &&
                message.bundleSha256 == _myBundleSha256) {
              _peerConfirmed = true;
              _checkCompletion();
            }
          }
        case NearbyPeerDisconnected():
          if (event.endpointId == _endpointId &&
              state.phase != DirectTransferPhase.complete) {
            throw StateError(
              'The sender disconnected before the transfer finished.',
            );
          }
        case NearbyTransportError():
          throw event.error;
      }
    } catch (error) {
      _fail(_messageFor(error));
    }
  }

  Future<void> _sendLocalSyncBundle(String endpointId) async {
    if (_syncSent) return;
    _syncSent = true;
    final myBundle = createSyncBundle(store, session.scope);
    final transfer = TransferEnvelope.encode(
      session: session,
      bundle: myBundle,
    );
    _myBundleSha256 = TransferEnvelope.decode(
      bytes: transfer,
      session: session,
    ).bundleSha256;
    if (transfer.length <= 30 * 1024) {
      await _transport.sendBytes(endpointId, transfer);
    } else {
      await _transport.sendFile(
        endpointId: endpointId,
        bytes: transfer,
        filename: 'stockmix-sync-${session.discoveryKey}.json',
      );
    }
  }

  Future<void> _saveReceivedTransfer(Uint8List bytes, String endpointId) async {
    if (_transferProcessed) return;
    _transferProcessed = true;
    _fileStartTimer?.cancel();
    _set(
      state.copyWith(
        phase: DirectTransferPhase.validating,
        message: session.isSync
            ? 'Validating and saving sync records…'
            : 'Validating and saving the record…',
        clearProgress: true,
      ),
    );
    final envelope = TransferEnvelope.decode(bytes: bytes, session: session);
    final bundle = StockStore.decodeBundle(envelope.bundleJson);
    final alreadySaved = store.received.any(
      (item) => item['id'] == bundle['id'],
    );
    if (!alreadySaved) await store.importBundle(bundle);

    if (session.isSync) {
      _receivedSyncBundle = bundle;
      _syncSummary = alreadySaved
          ? 'Incoming records are already saved.'
          : 'Incoming records are saved for merge.';
    }

    await _transport.sendBytes(
      endpointId,
      PairingMessage.receipt(session, envelope.bundleSha256).encode(),
    );

    if (!session.isSync) {
      _complete(
        alreadySaved
            ? 'Already received ✓ This record is already saved on this device.'
            : 'Received ✓ The validated record is saved.',
      );
    } else {
      _checkCompletion();
    }
  }

  void _checkCompletion() {
    if (!session.isSync) return;
    if (_transferProcessed && _peerConfirmed) {
      _complete(
        'Sync complete ✓ ${_syncSummary ?? "Choose when to merge incoming records."}',
      );
    }
  }

  void _complete(String message) {
    _fileStartTimer?.cancel();
    _set(
      DirectTransferState(
        phase: DirectTransferPhase.complete,
        message: message,
        progress: 1,
      ),
    );
  }

  void cancel() {
    if (state.isFinished) return;
    _fileStartTimer?.cancel();
    _set(
      const DirectTransferState(
        phase: DirectTransferPhase.cancelled,
        message: 'Receive cancelled.',
      ),
    );
    unawaited(_transport.stop());
  }

  void _fail(String message) {
    if (_disposed || state.isFinished) return;
    _fileStartTimer?.cancel();
    _set(
      DirectTransferState(phase: DirectTransferPhase.error, message: message),
    );
    unawaited(_transport.stop());
  }

  void _set(DirectTransferState value) {
    if (_disposed) return;
    _state = value;
    notifyListeners();
  }

  String _messageFor(Object error) {
    if (error is PlatformException &&
        error.code == 'nearby_location_disabled') {
      return error.message ??
          'Turn on Location in your phone’s Quick Settings, then try again.';
    }
    if (error is MissingPluginException) {
      return 'Direct sharing was added after this app started. Stop the app completely and install or run the newest build, then try again.';
    }
    final value = error.toString().replaceFirst(
      RegExp(r'^(StateError|FormatException):\s*'),
      '',
    );
    return value.isEmpty ? 'Something interrupted the nearby transfer.' : value;
  }

  @override
  void dispose() {
    _disposed = true;
    _fileStartTimer?.cancel();
    _subscription?.cancel();
    unawaited(_transport.close());
    super.dispose();
  }
}
