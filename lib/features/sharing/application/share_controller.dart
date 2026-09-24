import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:stockmix/features/stock/stock_store.dart';
import '../domain/share_session.dart';
import '../domain/sync_service.dart';
import '../domain/transfer_envelope.dart';
import '../domain/transfer_state.dart';
import '../infrastructure/nearby_permissions.dart';
import '../infrastructure/nearby_transport.dart';
import '../infrastructure/pairing_service.dart';

class NearbyShareController extends ChangeNotifier {
  final Map<String, dynamic> bundle;
  final StockStore? store;
  final NearbyTransport _transport;
  final ShareSession session;
  StreamSubscription<NearbyTransportEvent>? _subscription;
  Timer? _expiryTimer;
  Timer? _fileStartTimer;
  DirectTransferState _state = const DirectTransferState.preparing();
  String? _endpointId;
  String? _bundleSha256;
  bool _sending = false;
  bool _disposed = false;
  bool _peerConfirmed = false;
  bool _syncReceived = false;
  bool _syncMergeChosen = false;
  bool mergingSync = false;
  Map<String, dynamic>? _receivedSyncBundle;
  String? _peerMergeSummary;

  NearbyShareController({
    required this.bundle,
    this.store,
    NearbyTransport? transport,
    ShareSession? session,
  }) : _transport = transport ?? createNearbyTransport(),
       session = session ?? ShareSession.create();

  DirectTransferState get state => _state;
  bool get canMergeReceivedSync =>
      session.isSync &&
      store != null &&
      _receivedSyncBundle != null &&
      state.phase == DirectTransferPhase.complete &&
      !_syncMergeChosen;

  Future<void> mergeReceivedSyncNow() async {
    if (!canMergeReceivedSync || mergingSync) return;
    mergingSync = true;
    final peerBundle = _receivedSyncBundle!;
    _set(
      state.copyWith(message: 'Merging received records…', clearProgress: true),
    );
    try {
      _peerMergeSummary = await applySyncMerge(
        store: store!,
        bundle: peerBundle,
        scope: session.scope,
      );
      _syncMergeChosen = true;
      mergingSync = false;
      _complete(_peerMergeSummary!);
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
      await ensureNearbyPermissions();
      if (session.isExpired) {
        throw const FormatException(
          'This pairing code has expired. Start again.',
        );
      }
      final started = await _transport.startAdvertising(
        endpointName: session.advertisedEndpointName,
      );
      if (!started) {
        throw StateError('Could not make this device discoverable.');
      }
      _expiryTimer = Timer(ShareSession.lifetime, () {
        _fail('This pairing code expired. Start a new transfer.');
      });
      _set(
        DirectTransferState(
          phase: DirectTransferPhase.waitingForPeer,
          message: session.isSync
              ? 'Waiting for the other phone to scan your sync code…'
              : 'Waiting for the receiver to scan your QR code…',
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
        case NearbyConnectionInitiated():
          _endpointId ??= event.endpointId;
          _set(
            DirectTransferState(
              phase: DirectTransferPhase.connecting,
              message: 'Connecting to ${event.endpointName}…',
              peerName: event.endpointName,
            ),
          );
          final accepted = await _transport.acceptConnection(event.endpointId);
          if (!accepted) {
            throw StateError('Could not accept the nearby connection.');
          }
        case NearbyConnectionResult():
          if (event.endpointId != _endpointId) return;
          if (event.status != NearbyConnectionStatus.connected) {
            throw StateError('The nearby connection was not accepted.');
          }
          _set(
            state.copyWith(
              phase: DirectTransferPhase.authenticating,
              message: 'Authenticating the scanned QR code…',
              clearProgress: true,
            ),
          );
        case NearbyBytesReceived():
          if (session.isSync &&
              event.endpointId == _endpointId &&
              event.bytes.isNotEmpty) {
            final envelope = TransferEnvelope.tryDecode(
              bytes: event.bytes,
              session: session,
            );
            if (envelope != null) {
              await _handleIncomingSyncTransfer(event.bytes, event.endpointId);
              return;
            }
          }
          await _handleControlMessage(event);
        case NearbyFileProgress():
          if (_sending &&
              !event.incoming &&
              event.total > 0 &&
              event.status == NearbyFileStatus.inProgress) {
            _fileStartTimer?.cancel();
            _fileStartTimer = Timer(const Duration(seconds: 30), () {
              _fail('The transfer timed out while sending. Try again.');
            });
            _set(
              state.copyWith(
                phase: DirectTransferPhase.sending,
                message: session.isSync
                    ? 'Syncing securely…'
                    : 'Sending securely…',
                progress: event.transferred / event.total,
              ),
            );
          }
          if (_sending &&
              !event.incoming &&
              event.status == NearbyFileStatus.failure) {
            throw StateError('The nearby transfer did not finish.');
          }
        case NearbyFileReceived():
          if (session.isSync && event.endpointId == _endpointId) {
            await _handleIncomingSyncTransfer(event.bytes, event.endpointId);
          }
        case NearbyPeerDisconnected():
          if (event.endpointId == _endpointId &&
              state.phase != DirectTransferPhase.complete) {
            throw StateError('The other device disconnected.');
          }
        case NearbyTransportError():
          throw event.error;
        case NearbyPeerFound():
          break;
      }
    } catch (error) {
      _fail(_messageFor(error));
    }
  }

  Future<void> _handleControlMessage(NearbyBytesReceived event) async {
    if (event.endpointId != _endpointId) return;
    final message = PairingMessage.tryDecode(event.bytes);
    if (message == null) return;

    if (message.type == PairingMessageType.hello) {
      if (!message.matches(session)) {
        throw const FormatException(
          'The receiver did not authenticate this QR code.',
        );
      }
      if (_sending) return;
      _sending = true;
      final transfer = TransferEnvelope.encode(
        session: session,
        bundle: bundle,
      );
      _bundleSha256 = TransferEnvelope.decode(
        bytes: transfer,
        session: session,
      ).bundleSha256;
      _set(
        state.copyWith(
          phase: DirectTransferPhase.sending,
          message: session.isSync ? 'Syncing securely…' : 'Sending securely…',
          progress: 0,
        ),
      );
      if (transfer.length <= 30 * 1024) {
        await _transport.sendBytes(event.endpointId, transfer);
      } else {
        await _transport.sendFile(
          endpointId: event.endpointId,
          bytes: transfer,
          filename: 'stockmix-nearby-${session.discoveryKey}.json',
        );
      }
      _fileStartTimer = Timer(const Duration(seconds: 30), () {
        _fail(
          'The transfer did not finish in time. Make sure both apps are on the newest build, then try again.',
        );
      });
      return;
    }

    if (message.type == PairingMessageType.receipt &&
        message.matches(session) &&
        message.bundleSha256 == _bundleSha256) {
      _peerConfirmed = true;
      _checkCompletion();
    }
  }

  Future<void> _handleIncomingSyncTransfer(
    Uint8List bytes,
    String endpointId,
  ) async {
    if (_syncReceived) return;
    _syncReceived = true;
    _fileStartTimer?.cancel();
    _set(
      state.copyWith(
        phase: DirectTransferPhase.validating,
        message: 'Validating and saving sync records…',
        clearProgress: true,
      ),
    );
    try {
      final envelope = TransferEnvelope.decode(bytes: bytes, session: session);
      final peerBundle = StockStore.decodeBundle(envelope.bundleJson);
      if (store != null) {
        final alreadySaved = store!.received.any(
          (item) => item['id'] == peerBundle['id'],
        );
        if (!alreadySaved) await store!.importBundle(peerBundle);
        _receivedSyncBundle = peerBundle;
        _peerMergeSummary = alreadySaved
            ? 'Incoming records are already saved.'
            : 'Incoming records are saved for merge.';
      }
      await _transport.sendBytes(
        endpointId,
        PairingMessage.receipt(session, envelope.bundleSha256).encode(),
      );
      _checkCompletion();
    } catch (e) {
      _fail(_messageFor(e));
    }
  }

  void _checkCompletion() {
    if (!session.isSync) {
      if (_peerConfirmed) {
        _complete('Sent ✓ The receiver validated and saved the record.');
      }
      return;
    }
    if (_peerConfirmed && _syncReceived) {
      _complete(
        'Sync complete ✓ ${_peerMergeSummary ?? "Choose when to merge incoming records."}',
      );
    }
  }

  void _complete(String message) {
    _expiryTimer?.cancel();
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
    _expiryTimer?.cancel();
    _fileStartTimer?.cancel();
    _set(
      const DirectTransferState(
        phase: DirectTransferPhase.cancelled,
        message: 'Transfer cancelled.',
      ),
    );
    unawaited(_transport.stop());
  }

  void _fail(String message) {
    if (_disposed || state.isFinished) return;
    _expiryTimer?.cancel();
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
    _expiryTimer?.cancel();
    _fileStartTimer?.cancel();
    _subscription?.cancel();
    unawaited(_transport.close());
    super.dispose();
  }
}
