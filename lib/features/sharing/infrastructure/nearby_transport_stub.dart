import 'dart:async';
import 'dart:typed_data';

import 'nearby_transport_contract.dart';

NearbyTransport createNearbyTransport() => _UnsupportedNearbyTransport();

class _UnsupportedNearbyTransport implements NearbyTransport {
  final _events = StreamController<NearbyTransportEvent>.broadcast();

  @override
  Stream<NearbyTransportEvent> get events => _events.stream;

  Future<bool> _unsupported() async {
    _events.add(
      NearbyTransportError(
        UnsupportedError(
          'Direct nearby transfer is available on Android only.',
        ),
      ),
    );
    return false;
  }

  @override
  Future<bool> acceptConnection(String endpointId) => _unsupported();

  @override
  Future<void> close() async => _events.close();

  @override
  Future<bool> requestConnection({
    required String endpointId,
    required String endpointName,
  }) => _unsupported();

  @override
  Future<void> sendBytes(String endpointId, Uint8List bytes) async =>
      _unsupported();

  @override
  Future<void> sendFile({
    required String endpointId,
    required Uint8List bytes,
    required String filename,
  }) async => _unsupported();

  @override
  Future<bool> startAdvertising({required String endpointName}) =>
      _unsupported();

  @override
  Future<bool> startDiscovery({required String endpointName}) => _unsupported();

  @override
  Future<void> stop() async {}
}
