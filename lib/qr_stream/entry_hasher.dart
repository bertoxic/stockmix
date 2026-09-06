import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../stock_store.dart';

/// Content-based canonical hashing and deduplication engine for Stockmix entries.
class EntryHasher {
  /// Canonical hash for a Product based on its intrinsic attributes.
  /// Ignores ephemeral local IDs and photo byte strings so identical catalog items match.
  static String productHash(Product p) {
    final barcodeKey = normalizeCode(p.barcode);
    final canonical = 'PROD|${p.name.trim().toLowerCase()}|$barcodeKey|${p.price}|${p.cost}|${p.threshold}|${p.unit.trim().toLowerCase()}';
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  /// Canonical hash for a Movement based on transaction facts.
  static String movementHash(Movement m) {
    final canonical = 'MOVE|${m.productId}|${m.type}|${m.delta}|${m.price}|${m.cost}|${m.at}|${m.reference}';
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  /// Canonical hash for a general Map or export bundle.
  static String canonicalJsonHash(Map<String, dynamic> data) {
    final sortedJson = _canonicalString(data);
    return sha256.convert(utf8.encode(sortedJson)).toString();
  }

  static String _canonicalString(dynamic obj) {
    if (obj is Map) {
      final keys = obj.keys.map((k) => k.toString()).toList()..sort();
      final entries = <String>[];
      for (final k in keys) {
        entries.add('${jsonEncode(k)}:${_canonicalString(obj[k])}');
      }
      return '{${entries.join(',')}}';
    } else if (obj is List) {
      final items = obj.map(_canonicalString).toList();
      return '[${items.join(',')}]';
    } else {
      return jsonEncode(obj);
    }
  }

  /// Truncated 8-char visual hash badge (e.g. "#4f92c10a")
  static String shortHash(String fullHash) =>
      '#${fullHash.length >= 8 ? fullHash.substring(0, 8) : fullHash}';
}

/// Status of an incoming product compared to local inventory.
class ProductAnalysisItem {
  final Product product;
  final int onHand;
  final String contentHash;
  final Product? existingMatch;
  final bool isDuplicate;
  final String matchReason;

  const ProductAnalysisItem({
    required this.product,
    required this.onHand,
    required this.contentHash,
    this.existingMatch,
    required this.isDuplicate,
    required this.matchReason,
  });
}

/// Status of an incoming movement compared to local history.
class MovementAnalysisItem {
  final Movement movement;
  final String contentHash;
  final Movement? existingMatch;
  final bool isDuplicate;
  final String matchReason;

  const MovementAnalysisItem({
    required this.movement,
    required this.contentHash,
    this.existingMatch,
    required this.isDuplicate,
    required this.matchReason,
  });
}

/// Analysis result of an incoming stream payload against current store state.
class StreamImportAnalysis {
  final String bundleId;
  final String bundleKind;
  final String shopName;
  final String currency;
  final DateTime exportedAt;
  final String bundleHash;
  final bool isBundleAlreadyReceived;

  final List<ProductAnalysisItem> products;
  final List<MovementAnalysisItem> movements;

  const StreamImportAnalysis({
    required this.bundleId,
    required this.bundleKind,
    required this.shopName,
    required this.currency,
    required this.exportedAt,
    required this.bundleHash,
    required this.isBundleAlreadyReceived,
    required this.products,
    required this.movements,
  });

  int get totalProducts => products.length;
  int get newProductsCount => products.where((p) => !p.isDuplicate).length;
  int get duplicateProductsCount => products.where((p) => p.isDuplicate).length;

  int get totalMovements => movements.length;
  int get newMovementsCount => movements.where((m) => !m.isDuplicate).length;
  int get duplicateMovementsCount => movements.where((m) => m.isDuplicate).length;

  bool get hasAnyDuplicates => duplicateProductsCount > 0 || duplicateMovementsCount > 0 || isBundleAlreadyReceived;

  /// Perform analysis against the local store.
  factory StreamImportAnalysis.analyze(
    Map<String, dynamic> bundle,
    StockStore store,
  ) {
    final bundleId = bundle['id']?.toString() ?? '';
    final bundleKind = bundle['kind']?.toString() ?? 'Stock snapshot';
    final shopName = bundle['shop']?.toString() ?? 'Shared store';
    final currency = bundle['currency']?.toString() ?? store.currency;
    final exportedAt = DateTime.tryParse(bundle['exportedAt']?.toString() ?? '') ?? DateTime.now();
    final bundleHash = EntryHasher.canonicalJsonHash(bundle);

    final isBundleAlreadyReceived = store.received.any(
      (r) => r['id'] == bundleId || r['bundleHash'] == bundleHash,
    );

    // Analyze Products
    final rawProducts = bundle['products'] as List? ?? [];
    final analyzedProducts = <ProductAnalysisItem>[];

    for (final raw in rawProducts) {
      final p = Product.fromJson(Map<String, dynamic>.from(raw));
      final onHand = (raw['onHand'] as int?) ?? p.opening;
      final hash = EntryHasher.productHash(p);

      // Check existing matches in local store
      Product? existingMatch;
      var isDup = false;
      var reason = 'New product';

      // 1. Check ID
      final idMatch = store.products.where((item) => item.id == p.id).firstOrNull;
      if (idMatch != null) {
        existingMatch = idMatch;
        isDup = true;
        reason = 'Matches existing item ID';
      }

      // 2. Check Barcode
      if (!isDup && p.barcode.isNotEmpty) {
        final barcodeMatch = store.products.where(
          (item) => item.barcode.isNotEmpty && normalizeCode(item.barcode) == normalizeCode(p.barcode),
        ).firstOrNull;
        if (barcodeMatch != null) {
          existingMatch = barcodeMatch;
          isDup = true;
          reason = 'Matches barcode "${p.barcode}"';
        }
      }

      // 3. Check Content Hash (exact name, price, cost, unit)
      if (!isDup) {
        final hashMatch = store.products.where((item) => EntryHasher.productHash(item) == hash).firstOrNull;
        if (hashMatch != null) {
          existingMatch = hashMatch;
          isDup = true;
          reason = 'Identical product already in inventory';
        }
      }

      analyzedProducts.add(
        ProductAnalysisItem(
          product: p,
          onHand: onHand,
          contentHash: hash,
          existingMatch: existingMatch,
          isDuplicate: isDup,
          matchReason: reason,
        ),
      );
    }

    // Analyze Movements
    final rawMovements = bundle['movements'] as List? ?? [];
    final analyzedMovements = <MovementAnalysisItem>[];

    // Build lookup of existing movement hashes
    final existingMoveHashes = <String, Movement>{};
    final existingMoveIds = <String, Movement>{};
    for (final m in store.movements) {
      existingMoveIds[m.id] = m;
      existingMoveHashes[EntryHasher.movementHash(m)] = m;
    }

    for (final raw in rawMovements) {
      final m = Movement.fromJson(Map<String, dynamic>.from(raw));
      final hash = EntryHasher.movementHash(m);

      Movement? existingMatch;
      var isDup = false;
      var reason = 'New movement';

      if (existingMoveIds.containsKey(m.id)) {
        existingMatch = existingMoveIds[m.id];
        isDup = true;
        reason = 'Matches existing movement ID';
      } else if (existingMoveHashes.containsKey(hash)) {
        existingMatch = existingMoveHashes[hash];
        isDup = true;
        reason = 'Exact identical movement already in history';
      }

      analyzedMovements.add(
        MovementAnalysisItem(
          movement: m,
          contentHash: hash,
          existingMatch: existingMatch,
          isDuplicate: isDup,
          matchReason: reason,
        ),
      );
    }

    return StreamImportAnalysis(
      bundleId: bundleId,
      bundleKind: bundleKind,
      shopName: shopName,
      currency: currency,
      exportedAt: exportedAt,
      bundleHash: bundleHash,
      isBundleAlreadyReceived: isBundleAlreadyReceived,
      products: analyzedProducts,
      movements: analyzedMovements,
    );
  }
}
