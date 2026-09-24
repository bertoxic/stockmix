import 'package:stockmix/features/stock/stock_store.dart';
import "share_session.dart";

Map<String, dynamic> createSyncBundle(StockStore store, SyncScope scope) {
  switch (scope) {
    case SyncScope.sales:
      return store.bundle(day: DateTime.now());
    case SyncScope.products:
      final b = store.bundle(day: null);
      b['movements'] = <dynamic>[];
      return b;
    case SyncScope.all:
      return store.bundle();
  }
}

Future<String> applySyncMerge({
  required StockStore store,
  required Map<String, dynamic> bundle,
  required SyncScope scope,
}) async {
  final bundleId = bundle["id"] as String;
  final alreadyReceived = store.received.any((r) => r["id"] == bundleId);
  if (!alreadyReceived) {
    try {
      await store.importBundle(bundle, addProducts: false);
    } catch (_) {
      // Ignored if already imported or currency mismatch
    }
  }

  if (store.count != null) {
    return "Saved to Received (Finish active stock count to merge items).";
  }
  final syncProducts = scope == SyncScope.all || scope == SyncScope.products;
  final syncSales = scope == SyncScope.all || scope == SyncScope.sales;

  try {
    final counts = await store.mergeReceived(
      bundle["id"] as String,
      addProducts: syncProducts,
      importMovements: syncSales,
    );
    final parts = <String>[];
    final products = counts["newProducts"] ?? 0;
    final photos = counts["backfilledPhotos"] ?? 0;
    final sales = counts["newMovements"] ?? 0;
    if (products > 0) parts.add("$products new item${products == 1 ? "" : "s"}");
    if (photos > 0) parts.add("$photos photo${photos == 1 ? "" : "s"}");
    if (sales > 0) parts.add("$sales sale${sales == 1 ? "" : "s"}");
    if (parts.isEmpty) return "Everything was already up to date.";
    return "Merged ${parts.join(", ")}.";
  } catch (e) {
    final clean = e
        .toString()
        .replaceAll(RegExp(r"^(StateError|FormatException):\s*"), "");
    return "Saved to Received ($clean).";
  }
}
