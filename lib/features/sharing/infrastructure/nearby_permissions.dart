import 'nearby_permissions_stub.dart'
    if (dart.library.io) 'nearby_permissions_native.dart'
    as implementation;

Future<void> ensureNearbyPermissions() =>
    implementation.ensureNearbyPermissions();
