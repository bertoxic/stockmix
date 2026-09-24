import 'nearby_transport_contract.dart';
import 'nearby_transport_stub.dart'
    if (dart.library.io) 'nearby_transport_native.dart'
    as implementation;

export 'nearby_transport_contract.dart';

NearbyTransport createNearbyTransport() =>
    implementation.createNearbyTransport();
