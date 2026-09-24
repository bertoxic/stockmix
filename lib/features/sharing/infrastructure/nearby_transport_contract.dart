import 'dart:typed_data';

const stockmixNearbyServiceId = 'com.bertoxic.stockmix.transfer.v1';

enum NearbyConnectionStatus { connected, rejected, error }

enum NearbyFileStatus { none, success, failure, inProgress, cancelled }

sealed class NearbyTransportEvent {
  const NearbyTransportEvent();
}

class NearbyPeerFound extends NearbyTransportEvent {
  final String endpointId;
  final String endpointName;
  const NearbyPeerFound(this.endpointId, this.endpointName);
}

class NearbyConnectionInitiated extends NearbyTransportEvent {
  final String endpointId;
  final String endpointName;
  final String authenticationToken;
  const NearbyConnectionInitiated({
    required this.endpointId,
    required this.endpointName,
    required this.authenticationToken,
  });
}

class NearbyConnectionResult extends NearbyTransportEvent {
  final String endpointId;
  final NearbyConnectionStatus status;
  const NearbyConnectionResult(this.endpointId, this.status);
}

class NearbyPeerDisconnected extends NearbyTransportEvent {
  final String endpointId;
  const NearbyPeerDisconnected(this.endpointId);
}

class NearbyBytesReceived extends NearbyTransportEvent {
  final String endpointId;
  final Uint8List bytes;
  const NearbyBytesReceived(this.endpointId, this.bytes);
}

class NearbyFileReceived extends NearbyTransportEvent {
  final String endpointId;
  final Uint8List bytes;
  const NearbyFileReceived(this.endpointId, this.bytes);
}

class NearbyFileProgress extends NearbyTransportEvent {
  final String endpointId;
  final int transferred;
  final int total;
  final NearbyFileStatus status;
  final bool incoming;
  const NearbyFileProgress({
    required this.endpointId,
    required this.transferred,
    required this.total,
    required this.status,
    required this.incoming,
  });
}

class NearbyTransportError extends NearbyTransportEvent {
  final Object error;
  const NearbyTransportError(this.error);
}

abstract class NearbyTransport {
  Stream<NearbyTransportEvent> get events;

  Future<bool> startAdvertising({required String endpointName});
  Future<bool> startDiscovery({required String endpointName});
  Future<bool> requestConnection({
    required String endpointId,
    required String endpointName,
  });
  Future<bool> acceptConnection(String endpointId);
  Future<void> sendBytes(String endpointId, Uint8List bytes);
  Future<void> sendFile({
    required String endpointId,
    required Uint8List bytes,
    required String filename,
  });
  Future<void> stop();
  Future<void> close();
}
