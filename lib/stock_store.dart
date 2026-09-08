import 'dart:convert';
import 'dart:collection';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sembast/sembast.dart';
import 'package:uuid/uuid.dart';

String newId() => const Uuid().v4();
String dayKey(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String normalizeCode(String value) {
  final raw = value.trim();
  final uri = Uri.tryParse(raw);
  if (uri != null && uri.hasScheme) {
    final parts = uri.pathSegments;
    final index = parts.indexOf('01');
    if (index >= 0 &&
        index + 1 < parts.length &&
        RegExp(r'^\d{14}$').hasMatch(parts[index + 1])) {
      return parts[index + 1];
    }
  }
  if (RegExp(r'^\d{8,14}$').hasMatch(raw)) return raw.padLeft(14, '0');
  return raw;
}

String normalizeReceiptReference(String value) {
  var raw = value.trim();
  if (raw.toUpperCase().startsWith('SMX:REC:')) {
    raw = raw.substring('SMX:REC:'.length).trim();
  }
  return raw;
}

int parseMoney(String text) {
  final value = text.trim();
  if (!RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(value)) {
    throw const FormatException('Enter a price with up to two decimal places.');
  }
  final parts = value.split('.');
  return int.parse(parts[0]) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
}

String unitLabel(String unit, int quantity) {
  final trimmed = unit.trim();
  if (quantity == 1 || trimmed.isEmpty || trimmed.toLowerCase().endsWith('s')) {
    return trimmed;
  }
  return '${trimmed}s';
}

List<String> cleanItemLabels(Iterable<String> values) {
  final labels = <String>[];
  for (final value in values) {
    final label = value.trim();
    if (label.isEmpty ||
        labels.any(
          (existing) => existing.toLowerCase() == label.toLowerCase(),
        )) {
      continue;
    }
    labels.add(label);
    if (labels.length == 3) break;
  }
  return labels;
}

class Product {
  final String id, name, category, barcode, unit;
  final int price, cost, opening, threshold;
  final String? photo;
  final DateTime? expiryDate;
  final String? label;

  /// Inventory is always counted in [unit], the product's base unit.
  ///
  /// When [packSize] is greater than one, a pack can be sold as a convenient
  /// multiple of the base unit without creating a second inventory item.
  final int packSize;
  final int? packPrice;
  final String defaultSellingUnit;
  const Product({
    required this.id,
    required this.name,
    required this.category,
    required this.barcode,
    required this.price,
    required this.cost,
    required this.opening,
    required this.threshold,
    this.unit = 'pcs',
    this.photo,
    this.expiryDate,
    this.label,
    this.packSize = 1,
    this.packPrice,
    this.defaultSellingUnit = 'base',
  });

  bool get sellsByPack => packSize > 1 && packPrice != null;

  List<SellingUnit> get sellingUnits => [
    SellingUnit(name: unit, multiplier: 1, price: price),
    if (sellsByPack)
      SellingUnit(name: 'Pack', multiplier: packSize, price: packPrice!),
  ];

  SellingUnit get defaultUnit {
    if (defaultSellingUnit == 'pack' && sellsByPack) {
      return sellingUnits.last;
    }
    return sellingUnits.first;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'barcode': barcode,
    'price': price,
    'cost': cost,
    'opening': opening,
    'threshold': threshold,
    'unit': unit,
    'photo': photo,
    'expiryDate': expiryDate?.toIso8601String(),
    'label': label,
    'packSize': packSize,
    'packPrice': packPrice,
    'defaultSellingUnit': defaultSellingUnit,
  };
  factory Product.fromJson(Map<String, dynamic> j) => Product(
    id: j['id'],
    name: j['name'],
    category: j['category'],
    barcode: j['barcode'],
    price: j['price'],
    cost: j['cost'],
    opening: j['opening'],
    threshold: j['threshold'],
    unit: j['unit'] ?? 'pcs',
    photo: j['photo'],
    expiryDate: j['expiryDate'] is String
        ? DateTime.tryParse(j['expiryDate'] as String)
        : null,
    label: j['label'] is String
        ? j['label'] as String
        : j['toxiLabel'] as String?,
    packSize: j['packSize'] is int ? j['packSize'] as int : 1,
    packPrice: j['packPrice'] is int ? j['packPrice'] as int : null,
    defaultSellingUnit: j['defaultSellingUnit'] == 'pack' ? 'pack' : 'base',
  );
}

/// A customer-facing unit that converts to a quantity of the product's base
/// inventory unit. Prices are stored in cents for one selected selling unit.
class SellingUnit {
  final String name;
  final int multiplier;
  final int price;
  const SellingUnit({
    required this.name,
    required this.multiplier,
    required this.price,
  });
}

/// A distinct line in a sale. Keeping the selected unit on the line means a
/// sale can contain both cards and packs of the same medicine correctly.
class SaleLine {
  final String productId;
  final String unitName;
  final int unitMultiplier;
  final int unitPrice;
  final int quantity;

  const SaleLine({
    required this.productId,
    required this.unitName,
    required this.unitMultiplier,
    required this.unitPrice,
    required this.quantity,
  });

  int get baseQuantity => quantity * unitMultiplier;
  int get total => quantity * unitPrice;
  String get key => '$productId::$unitName::$unitMultiplier::$unitPrice';

  SaleLine copyWith({int? quantity}) => SaleLine(
    productId: productId,
    unitName: unitName,
    unitMultiplier: unitMultiplier,
    unitPrice: unitPrice,
    quantity: quantity ?? this.quantity,
  );

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'unitName': unitName,
    'unitMultiplier': unitMultiplier,
    'unitPrice': unitPrice,
    'quantity': quantity,
  };

  factory SaleLine.fromJson(Map<String, dynamic> json) => SaleLine(
    productId: json['productId'] as String,
    unitName: json['unitName'] as String? ?? 'pcs',
    unitMultiplier: json['unitMultiplier'] is int
        ? json['unitMultiplier'] as int
        : 1,
    unitPrice: json['unitPrice'] is int ? json['unitPrice'] as int : 0,
    quantity: json['quantity'] is int ? json['quantity'] as int : 0,
  );
}

/// Backwards-compatible map view of a sale, keyed by product id and valued in
/// base units. Existing scanner callers can still receive `Map<String, int>`,
/// while the underlying sale retains the exact Card/Pack choices and prices.
class SaleCart extends MapBase<String, int> {
  final List<SaleLine> _lines;

  SaleCart([Iterable<SaleLine> lines = const []]) : _lines = List.of(lines);

  factory SaleCart.fromLegacy(Map<String, int>? cart, StockStore store) {
    if (cart is SaleCart) return cart.copy();
    return SaleCart(
      (cart ?? const <String, int>{}).entries
          .where((entry) => entry.value > 0)
          .map((entry) {
            final product = store.product(entry.key);
            return SaleLine(
              productId: product.id,
              unitName: product.unit,
              unitMultiplier: 1,
              unitPrice: product.price,
              quantity: entry.value,
            );
          }),
    );
  }

  factory SaleCart.fromJson(List<dynamic> json) => SaleCart(
    json
        .map((line) => SaleLine.fromJson(Map<String, dynamic>.from(line)))
        .where((line) => line.quantity > 0 && line.unitMultiplier > 0),
  );

  List<SaleLine> get lines => List.unmodifiable(_lines);
  int get total => _lines.fold(0, (sum, line) => sum + line.total);
  int get totalBaseUnits =>
      _lines.fold(0, (sum, line) => sum + line.baseQuantity);
  int baseQuantityFor(String productId) => _lines
      .where((line) => line.productId == productId)
      .fold(0, (sum, line) => sum + line.baseQuantity);

  void add(Product product, SellingUnit unit, {int quantity = 1}) {
    if (quantity <= 0) return;
    final index = _lines.indexWhere(
      (line) =>
          line.productId == product.id &&
          line.unitName == unit.name &&
          line.unitMultiplier == unit.multiplier &&
          line.unitPrice == unit.price,
    );
    if (index < 0) {
      _lines.add(
        SaleLine(
          productId: product.id,
          unitName: unit.name,
          unitMultiplier: unit.multiplier,
          unitPrice: unit.price,
          quantity: quantity,
        ),
      );
    } else {
      _lines[index] = _lines[index].copyWith(
        quantity: _lines[index].quantity + quantity,
      );
    }
  }

  /// Moves a line to the front without changing its quantity. Scanner pages
  /// use this after an accepted barcode so the latest scan stays visible.
  void moveToFront(String lineKey) {
    final index = _lines.indexWhere((line) => line.key == lineKey);
    if (index <= 0) return;
    _lines.insert(0, _lines.removeAt(index));
  }

  void removeOne(SaleLine line) {
    final index = _lines.indexWhere((candidate) => candidate.key == line.key);
    if (index < 0) return;
    if (_lines[index].quantity <= 1) {
      _lines.removeAt(index);
    } else {
      _lines[index] = _lines[index].copyWith(
        quantity: _lines[index].quantity - 1,
      );
    }
  }

  SaleCart copy() => SaleCart(_lines);
  void replaceWith(SaleCart other) {
    _lines
      ..clear()
      ..addAll(other._lines);
  }

  List<Map<String, dynamic>> toJson() =>
      _lines.map((line) => line.toJson()).toList();

  @override
  int? operator [](Object? key) => key is String ? baseQuantityFor(key) : null;

  @override
  void operator []=(String key, int value) {
    final matching = _lines.where((line) => line.productId == key).toList();
    if (matching.isEmpty) {
      if (value != 0) {
        throw UnsupportedError('Use add() to add a product to a SaleCart.');
      }
      return;
    }
    _lines.removeWhere((line) => line.productId == key);
    if (value > 0) {
      final first = matching.first;
      _lines.add(
        SaleLine(
          productId: key,
          unitName: first.unitName,
          unitMultiplier: 1,
          unitPrice: first.unitMultiplier == 1
              ? first.unitPrice
              : first.unitPrice ~/ first.unitMultiplier,
          quantity: value,
        ),
      );
    }
  }

  @override
  void clear() => _lines.clear();

  @override
  Iterable<String> get keys => _lines.map((line) => line.productId).toSet();

  @override
  int? remove(Object? key) {
    if (key is! String) return null;
    final value = baseQuantityFor(key);
    _lines.removeWhere((line) => line.productId == key);
    return value == 0 ? null : value;
  }
}

class Movement {
  final String id, productId, name, type, note, reference, at;
  final String? returnOf;
  final int delta, price, cost;
  final String? photo;

  /// Sale details are optional so older movement records remain valid.
  final String? saleUnit;
  final int? saleUnitMultiplier, saleQuantity, lineTotal;
  const Movement({
    required this.id,
    required this.productId,
    required this.name,
    required this.type,
    required this.delta,
    required this.price,
    required this.cost,
    required this.note,
    required this.reference,
    required this.at,
    this.photo,
    this.saleUnit,
    this.saleUnitMultiplier,
    this.saleQuantity,
    this.lineTotal,
    this.returnOf,
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'productId': productId,
    'name': name,
    'type': type,
    'delta': delta,
    'price': price,
    'cost': cost,
    'note': note,
    'reference': reference,
    'at': at,
    'photo': photo,
    'saleUnit': saleUnit,
    'saleUnitMultiplier': saleUnitMultiplier,
    'saleQuantity': saleQuantity,
    'lineTotal': lineTotal,
    'returnOf': returnOf,
  };
  factory Movement.fromJson(Map<String, dynamic> j) => Movement(
    id: j['id'],
    productId: j['productId'],
    name: j['name'],
    type: j['type'],
    delta: j['delta'],
    price: j['price'],
    cost: j['cost'],
    note: j['note'],
    reference: j['reference'],
    at: j['at'],
    photo: j['photo'],
    saleUnit: j['saleUnit'] as String?,
    saleUnitMultiplier: j['saleUnitMultiplier'] as int?,
    saleQuantity: j['saleQuantity'] as int?,
    lineTotal: j['lineTotal'] as int?,
    returnOf: j['returnOf'] as String?,
  );
}

class StockStore extends ChangeNotifier {
  final Future<void> Function(Map<String, dynamic>) persist;
  StockStore({required this.persist});
  List<Product> _products = [];
  List<Movement> _movements = [];
  List<Map<String, dynamic>> _received = [];
  List<Map<String, dynamic>> _heldSales = [];
  Map<String, dynamic>? count;
  String shop = 'My store', currency = 'USD';
  String userName = '';
  bool setupCompleted = false;
  String? lastBackupAt;
  bool busy = false;
  bool soundEnabled = true;
  bool hapticsEnabled = true;
  String themeMode = 'light';
  bool showStoreStatistics = false;
  bool showExpiryDateField = false;
  bool showItemLabels = false;
  List<String> itemLabels = [];

  List<Product> get products => List.unmodifiable(_products);
  List<Movement> get movements => List.unmodifiable(_movements);
  List<Map<String, dynamic>> get received => List.unmodifiable(_received);
  List<Map<String, dynamic>> get heldSales => List.unmodifiable(_heldSales);
  List<String> get categories {
    final set = <String>{};
    for (final p in _products) {
      if (p.category.trim().isNotEmpty) set.add(p.category.trim());
    }
    return set.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  static Future<StockStore> open(Database db) async {
    final record = StoreRef<String, Map<String, dynamic>>(
      'app',
    ).record('state');
    final store = StockStore(
      persist: (data) async {
        await db.transaction((txn) => record.put(txn, data));
      },
    );
    final data = await record.get(db);
    if (data != null) store._restore(data);
    return store;
  }

  Map<String, dynamic> snapshot() => {
    'products': _products.map((p) => p.toJson()).toList(),
    'movements': _movements.map((m) => m.toJson()).toList(),
    'received': _received,
    'heldSales': _heldSales,
    'count': count,
    'shop': shop,
    'userName': userName,
    'currency': currency,
    'setupCompleted': setupCompleted,
    'lastBackupAt': lastBackupAt,
    'soundEnabled': soundEnabled,
    'hapticsEnabled': hapticsEnabled,
    'themeMode': themeMode,
    'showStoreStatistics': showStoreStatistics,
    'showExpiryDateField': showExpiryDateField,
    'showItemLabels': showItemLabels,
    'itemLabels': itemLabels,
  };

  void _restore(Map<String, dynamic> data) {
    _products = (data['products'] as List)
        .map((p) => Product.fromJson(Map<String, dynamic>.from(p)))
        .toList();
    _movements = (data['movements'] as List)
        .map((m) => Movement.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    _received = (data['received'] as List? ?? [])
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    _heldSales = (data['heldSales'] as List? ?? [])
        .map((h) => Map<String, dynamic>.from(h))
        .toList();
    count = data['count'] == null
        ? null
        : Map<String, dynamic>.from(data['count']);
    shop = data['shop'] ?? 'My store';
    userName = data['userName'] ?? '';
    currency = data['currency'] ?? 'USD';
    setupCompleted =
        data['setupCompleted'] ??
        (_products.isNotEmpty || _movements.isNotEmpty);
    lastBackupAt = data['lastBackupAt'];
    soundEnabled = data['soundEnabled'] ?? true;
    hapticsEnabled = data['hapticsEnabled'] ?? true;
    themeMode = data['themeMode'] ?? 'light';
    showStoreStatistics = data['showStoreStatistics'] ?? false;
    showExpiryDateField = data['showExpiryDateField'] ?? false;
    showItemLabels =
        data['showItemLabels'] ?? data['showToxiLabelField'] ?? false;
    itemLabels = cleanItemLabels(
      (data['itemLabels'] as List? ?? const []).whereType<String>(),
    );
  }

  Future<T> _commit<T>(T Function() change) async {
    if (busy) {
      throw StateError('Another save is in progress. Please try again.');
    }
    final before = jsonDecode(jsonEncode(snapshot())) as Map<String, dynamic>;
    busy = true;
    try {
      final result = change();
      await persist(snapshot());
      return result;
    } catch (_) {
      _restore(before);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Product product(String id) => _products.firstWhere((p) => p.id == id);
  int stock(Product p) => _movements
      .where((m) => m.productId == p.id)
      .fold(0, (n, m) => n + m.delta);

  /// Formats base-unit stock in the way staff count it on a shelf, while the
  /// stored quantity remains a single base-unit number.
  String stockLabel(Product p, {bool includeOnHand = false}) {
    final onHand = stock(p);
    if (!p.sellsByPack) return '$onHand ${unitLabel(p.unit, onHand)}';
    final packs = onHand ~/ p.packSize;
    final remainder = onHand % p.packSize;
    final parts = <String>[
      '$packs ${packs == 1 ? 'Pack' : 'Packs'}',
      '$remainder ${unitLabel(p.unit, remainder)}',
    ];
    final display = parts.join(' + ');
    return includeOnHand
        ? '$display ($onHand ${unitLabel(p.unit, onHand)})'
        : display;
  }

  int saleTotal(Movement movement) {
    if (movement.type != 'Sale') return movement.price;
    return movement.lineTotal ?? (-movement.delta * movement.price);
  }

  int refundFor(Movement saleMovement, int baseQuantity) {
    final soldBase = -saleMovement.delta;
    if (soldBase <= 0 || baseQuantity <= 0) return 0;
    return saleTotal(saleMovement) * baseQuantity ~/ soldBase;
  }

  Product? lookup(String code) {
    final key = normalizeCode(code);
    if (key.isEmpty) return null;
    for (final p in _products) {
      if (normalizeCode(p.barcode) == key) return p;
    }
    return null;
  }

  /// Finds all movements belonging to a sale or return transaction by matching
  /// its reference ID, QR code payload (`SMX:REC:...`), or movement ID.
  List<Movement> findSaleByReference(String rawRef) {
    final ref = normalizeReceiptReference(rawRef);
    if (ref.isEmpty) return const [];

    // 1. Exact match on reference
    final exact = _movements.where((m) => m.reference == ref).toList();
    if (exact.isNotEmpty) return exact;

    // 2. Exact match on movement id
    final byId = _movements.where((m) => m.id == ref).toList();
    if (byId.isNotEmpty) return byId;

    // 3. Case-insensitive match on reference or id
    final upper = ref.toUpperCase();
    final caseMatch = _movements
        .where(
          (m) =>
              m.reference.toUpperCase() == upper || m.id.toUpperCase() == upper,
        )
        .toList();
    if (caseMatch.isNotEmpty) return caseMatch;

    // 4. Prefix match (e.g. shortRef, at least 6 characters)
    if (upper.length >= 6) {
      final prefixMatch = _movements
          .where(
            (m) =>
                m.reference.toUpperCase().startsWith(upper) ||
                m.id.toUpperCase().startsWith(upper),
          )
          .toList();
      if (prefixMatch.isNotEmpty) return prefixMatch;
    }

    return const [];
  }

  List<Movement> onDay(DateTime day) => _movements
      .where((m) => dayKey(DateTime.parse(m.at).toLocal()) == dayKey(day))
      .toList();
  int revenue(DateTime day) {
    var total = 0;
    for (final m in onDay(day)) {
      if (m.type == 'Sale') {
        total += saleTotal(m);
      } else if (m.type == 'Return refund') {
        total -= m.price;
      }
    }
    return total;
  }

  int get units => _products.fold(0, (n, p) => n + stock(p));
  int get valuation => _products.fold(0, (n, p) => n + stock(p) * p.cost);
  List<Product> get low =>
      _products.where((p) => stock(p) <= p.threshold).toList();

  Future<void> completeSetup(String storeName, String currencyCode) =>
      _commit(() {
        if (storeName.trim().isNotEmpty) {
          shop = storeName.trim();
        }
        if (_movements.isEmpty) {
          currency = currencyCode;
        }
        setupCompleted = true;
      });

  Future<void> updateSettings({
    String? storeName,
    String? userName,
    String? currencyCode,
    bool? sound,
    bool? haptics,
    String? theme,
    bool? showStatistics,
    bool? showExpiryField,
    bool? showLabels,
    Iterable<String>? labels,
  }) => _commit(() {
    if (storeName != null && storeName.trim().isNotEmpty) {
      shop = storeName.trim();
    }
    if (userName != null) this.userName = userName.trim();
    if (currencyCode != null && currencyCode.trim().isNotEmpty) {
      currency = currencyCode.trim();
    }
    if (sound != null) soundEnabled = sound;
    if (haptics != null) hapticsEnabled = haptics;
    if (theme != null) themeMode = theme;
    if (showStatistics != null) showStoreStatistics = showStatistics;
    if (showExpiryField != null) showExpiryDateField = showExpiryField;
    if (showLabels != null) showItemLabels = showLabels;
    if (labels != null) itemLabels = cleanItemLabels(labels);
  });

  // --- Held Sales ---
  Future<void> holdSale(Map<String, int> cart, {String note = ''}) =>
      _commit(() {
        if (cart.isEmpty) throw StateError('Cannot hold an empty sale.');
        _heldSales.add({
          'id': newId(),
          'heldAt': DateTime.now().toUtc().toIso8601String(),
          'cart': Map<String, int>.from(cart),
          if (cart is SaleCart) 'lines': cart.toJson(),
          'note': note.trim(),
        });
      });

  Future<Map<String, int>?> resumeSale(String id) => _commit(() {
    final index = _heldSales.indexWhere((h) => h['id'] == id);
    if (index < 0) return null;
    final held = _heldSales.removeAt(index);
    return Map<String, int>.from(held['cart'] as Map);
  });

  Future<SaleCart?> resumeSaleCart(String id) => _commit(() {
    final index = _heldSales.indexWhere((h) => h['id'] == id);
    if (index < 0) return null;
    final held = _heldSales.removeAt(index);
    final savedLines = held['lines'];
    if (savedLines is List) return SaleCart.fromJson(savedLines);
    return SaleCart.fromLegacy(
      Map<String, int>.from(held['cart'] as Map),
      this,
    );
  });

  Future<void> deleteHeldSale(String id) => _commit(() {
    _heldSales.removeWhere((h) => h['id'] == id);
  });

  // --- Linked Returns ---
  int returnedQuantity(Movement saleMovement) {
    if (saleMovement.type != 'Sale') return 0;
    final returnRef = 'ret-${saleMovement.reference}';
    final restocked = _movements
        .where(
          (m) =>
              m.reference == returnRef &&
              m.productId == saleMovement.productId &&
              m.type == 'Return restock' &&
              (m.returnOf == saleMovement.id || m.returnOf == null),
        )
        .fold<int>(0, (sum, m) => sum + m.delta);
    final refunded = _movements
        .where(
          (m) =>
              m.reference == returnRef &&
              m.productId == saleMovement.productId &&
              m.type == 'Return refund' &&
              (m.returnOf == saleMovement.id || m.returnOf == null),
        )
        .fold<int>(0, (sum, m) => sum + m.price);
    final refundedUnits = saleMovement.price == 0
        ? 0
        : _movements
              .where(
                (m) =>
                    m.reference == returnRef &&
                    m.productId == saleMovement.productId &&
                    m.type == 'Return refund' &&
                    (m.returnOf == saleMovement.id || m.returnOf == null),
              )
              .fold<int>(0, (sum, m) => sum + (m.saleQuantity ?? 0));
    final legacyRefundedUnits = saleMovement.price == 0
        ? 0
        : refunded ~/ saleMovement.price;
    final normalizedRefundedUnits = refundedUnits == 0
        ? legacyRefundedUnits
        : refundedUnits;
    return restocked > normalizedRefundedUnits
        ? restocked
        : normalizedRefundedUnits;
  }

  int returnableQuantity(Movement saleMovement) => saleMovement.type == 'Sale'
      ? (-saleMovement.delta - returnedQuantity(saleMovement))
      : 0;

  void _applyReturn({
    required Movement saleMovement,
    required int returnQty,
    required bool returnToStock,
    required bool refundMoney,
    required String note,
  }) {
    if (saleMovement.type != 'Sale') {
      throw StateError('Returns can only be processed on sales.');
    }
    final maxReturn = returnableQuantity(saleMovement);
    if (returnQty <= 0 || returnQty > maxReturn) {
      throw StateError('Invalid return quantity (max $maxReturn).');
    }
    final prod = _products
        .where((p) => p.id == saleMovement.productId)
        .firstOrNull;
    if (prod == null) {
      throw StateError('Product no longer exists.');
    }

    final returnRef = 'ret-${saleMovement.reference}';
    final reason = note.trim().isEmpty ? 'Customer return' : note.trim();
    if (returnToStock) {
      _movement(
        prod,
        'Return restock',
        returnQty,
        '$reason (${refundMoney ? 'Refunded' : 'Exchanged'})',
        reference: returnRef,
        returnOf: saleMovement.id,
      );
    }
    if (refundMoney) {
      _movement(
        prod,
        'Return refund',
        0,
        '$reason (Refunded ${moneyString(refundFor(saleMovement, returnQty))})',
        reference: returnRef,
        returnOf: saleMovement.id,
        price: refundFor(saleMovement, returnQty),
        saleQuantity: returnQty,
      );
    }
  }

  Future<void> processReturn({
    required Movement saleMovement,
    required int returnQty,
    required bool returnToStock,
    required bool refundMoney,
    String note = '',
  }) => _commit(
    () => _applyReturn(
      saleMovement: saleMovement,
      returnQty: returnQty,
      returnToStock: returnToStock,
      refundMoney: refundMoney,
      note: note,
    ),
  );

  Future<int> processFullReturn({
    required List<Movement> saleMovements,
    required bool returnToStock,
    required bool refundMoney,
    String note = '',
  }) => _commit(() {
    var returnedLines = 0;
    for (final saleMovement in saleMovements) {
      final quantity = returnableQuantity(saleMovement);
      if (quantity == 0) continue;
      _applyReturn(
        saleMovement: saleMovement,
        returnQty: quantity,
        returnToStock: returnToStock,
        refundMoney: refundMoney,
        note: note,
      );
      returnedLines++;
    }
    if (returnedLines == 0) {
      throw StateError('All items in this sale have already been returned.');
    }
    return returnedLines;
  });

  // --- Batch Reorder Receiving ---
  Future<int> batchReceive(
    Map<String, int> receivedQuantities, {
    String supplier = '',
  }) => _commit(() {
    if (count != null) {
      throw StateError(
        'Finish or cancel active stock count before receiving goods.',
      );
    }
    var totalUnits = 0;
    final note = supplier.trim().isEmpty
        ? 'Supplier restock'
        : 'Delivery from ${supplier.trim()}';
    for (final entry in receivedQuantities.entries) {
      final qty = entry.value;
      if (qty <= 0) continue;
      final prod = _products.where((p) => p.id == entry.key).firstOrNull;
      if (prod != null) {
        _movement(prod, 'Received', qty, note);
        totalUnits += qty;
      }
    }
    return totalUnits;
  });

  // --- Business Analytics & Summaries ---
  List<Movement> movementsInPeriod(DateTime start, DateTime end) {
    return _movements.where((m) {
      final at = DateTime.parse(m.at).toLocal();
      return at.isAfter(start) && at.isBefore(end);
    }).toList();
  }

  Map<String, dynamic> businessSummary({int days = 7}) {
    final now = DateTime.now();
    final startDate = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));
    final endDate = now.add(const Duration(days: 1));
    final periodMovements = movementsInPeriod(startDate, endDate);
    final sales = periodMovements.where((m) => m.type == 'Sale').toList();
    final refunds = periodMovements
        .where((m) => m.type == 'Return refund')
        .toList();
    final restocks = periodMovements
        .where((m) => m.type == 'Return restock')
        .toList();

    var totalRevenue = 0;
    var totalCost = 0;
    var itemsMissingCost = 0;
    final itemSalesCount = <String, int>{};
    final itemSalesRevenue = <String, int>{};

    for (final sale in sales) {
      final qty = -sale.delta;
      final rev = saleTotal(sale);
      totalRevenue += rev;
      totalCost += qty * sale.cost;
      if (sale.cost <= 0) {
        itemsMissingCost++;
      }
      itemSalesCount[sale.productId] =
          (itemSalesCount[sale.productId] ?? 0) + qty;
      itemSalesRevenue[sale.productId] =
          (itemSalesRevenue[sale.productId] ?? 0) + rev;
    }

    for (final refund in refunds) {
      totalRevenue -= refund.price;
      itemSalesRevenue[refund.productId] =
          (itemSalesRevenue[refund.productId] ?? 0) - refund.price;
    }
    for (final restock in restocks) {
      final originalReference = restock.reference.startsWith('ret-')
          ? restock.reference.substring(4)
          : '';
      final sale = _movements
          .where(
            (m) =>
                m.type == 'Sale' &&
                m.reference == originalReference &&
                m.productId == restock.productId,
          )
          .firstOrNull;
      final cost = sale?.cost ?? restock.cost;
      totalCost -= restock.delta * cost;
      itemSalesCount[restock.productId] =
          (itemSalesCount[restock.productId] ?? 0) - restock.delta;
    }

    final estimatedGrossProfit = totalRevenue - totalCost;

    // Top selling items
    final sortedItemIds =
        itemSalesCount.keys
            .where((id) => (itemSalesCount[id] ?? 0) > 0)
            .toList()
          ..sort(
            (a, b) =>
                (itemSalesCount[b] ?? 0).compareTo(itemSalesCount[a] ?? 0),
          );
    final topSellers = sortedItemIds.take(5).map((id) {
      final p = _products.where((prod) => prod.id == id).firstOrNull;
      return {
        'name': p?.name ?? 'Unknown item',
        'unit': p?.unit ?? 'pcs',
        'quantity': itemSalesCount[id] ?? 0,
        'revenue': itemSalesRevenue[id] ?? 0,
      };
    }).toList();

    // Slow moving stock: on-hand items with zero sales in the last 14 days
    final fourteenDaysAgo = now.subtract(const Duration(days: 14));
    final recentSaleProductIds = _movements
        .where(
          (m) =>
              m.type == 'Sale' &&
              DateTime.parse(m.at).toLocal().isAfter(fourteenDaysAgo),
        )
        .map((m) => m.productId)
        .toSet();

    final slowMovers = _products
        .where((p) => stock(p) > 0 && !recentSaleProductIds.contains(p.id))
        .map(
          (p) => {
            'id': p.id,
            'name': p.name,
            'stock': stock(p),
            'unit': p.unit,
            'valuation': stock(p) * p.cost,
          },
        )
        .toList();

    return {
      'periodDays': days,
      'salesCount': sales.length,
      'totalRevenue': totalRevenue,
      'estimatedGrossProfit': estimatedGrossProfit,
      'itemsMissingCost': itemsMissingCost,
      'topSellers': topSellers,
      'slowMovers': slowMovers,
    };
  }

  String moneyString(int cents) =>
      NumberFormat.simpleCurrency(name: currency).format(cents / 100);

  void _movement(
    Product p,
    String type,
    int delta,
    String note, {
    String? reference,
    String? photo,
    int? price,
    String? saleUnit,
    int? saleUnitMultiplier,
    int? saleQuantity,
    int? lineTotal,
    String? returnOf,
  }) {
    _movements.add(
      Movement(
        id: newId(),
        productId: p.id,
        name: p.name,
        type: type,
        delta: delta,
        price: price ?? p.price,
        cost: p.cost,
        note: note,
        reference: reference ?? newId(),
        at: DateTime.now().toUtc().toIso8601String(),
        photo: photo,
        saleUnit: saleUnit,
        saleUnitMultiplier: saleUnitMultiplier,
        saleQuantity: saleQuantity,
        lineTotal: lineTotal,
        returnOf: returnOf,
      ),
    );
  }

  void _validateProduct(Product p) {
    if (p.name.trim().isEmpty ||
        p.name.length > 100 ||
        p.price < 0 ||
        p.cost < 0 ||
        p.opening < 0 ||
        p.threshold < 0 ||
        p.packSize < 1 ||
        (p.packPrice != null && p.packPrice! < 0) ||
        (p.packSize > 1 && p.packPrice == null)) {
      throw StateError('Check the product name, prices and quantities.');
    }
    if (p.barcode.isNotEmpty &&
        _products.any(
          (other) =>
              other.id != p.id &&
              normalizeCode(other.barcode) == normalizeCode(p.barcode),
        )) {
      throw StateError('That barcode already belongs to another item.');
    }
  }

  Future<void> saveProduct(Product p) => _commit(() {
    _validateProduct(p);
    final i = _products.indexWhere((other) => other.id == p.id);
    if (i < 0) {
      if (count != null) {
        throw StateError('Finish the active count before adding new items.');
      }
      _products.add(p);
      if (p.opening > 0) {
        _movement(p, 'Opening stock', p.opening, 'Opening balance');
      }
    } else {
      _products[i] = p;
    }
  });

  Future<void> deleteProduct(String id) => _commit(() {
    if (count != null && (count!['baseline'] as Map).containsKey(id)) {
      throw StateError(
        'Finish or cancel the active count before deleting this item.',
      );
    }
    final p = _products.where((item) => item.id == id).firstOrNull;
    if (p == null) {
      throw StateError('Item not found.');
    }
    final onHand = stock(p);
    if (onHand > 0) {
      throw StateError(
        'This item still has ${stockLabel(p)} in stock. Adjust or sell stock to 0 before deleting.',
      );
    }
    _products.removeWhere((item) => item.id == id);
    _movements.removeWhere((m) => m.productId == id);
  });
  Future<void> adjust(
    Product p,
    int quantity,
    String type,
    String note, {
    String? photo,
  }) => _commit(() {
    if (count != null && (count!['baseline'] as Map).containsKey(p.id)) {
      throw StateError(
        'Finish or cancel the active count for ${p.name} before changing its stock.',
      );
    }
    final current = product(p.id);
    if (quantity == 0 || stock(current) + quantity < 0) {
      throw StateError(
        'Quantity must be nonzero and cannot leave negative stock.',
      );
    }
    if (note.trim().isEmpty) {
      throw StateError('Add a reason for this stock change.');
    }
    _movement(current, type, quantity, note.trim(), photo: photo);
  });
  String _checkoutLines(SaleCart cart, String note, {String? photo}) {
    if (count != null) {
      final counted = count!['baseline'] as Map;
      final blocked = cart.keys.where((k) => counted.containsKey(k)).toList();
      if (blocked.isNotEmpty) {
        final names = blocked.map((k) => product(k).name).join(', ');
        throw StateError(
          'Cannot sell items currently being counted: $names. Finish or cancel the count first.',
        );
      }
    }
    if (cart.isEmpty) throw StateError('Add an item to the sale.');
    for (final productId in cart.keys) {
      final quantity = cart.baseQuantityFor(productId);
      if (quantity <= 0 || quantity > stock(product(productId))) {
        throw StateError('Not enough stock for ${product(productId).name}.');
      }
    }
    final ref = newId();
    for (final line in cart.lines) {
      _movement(
        product(line.productId),
        'Sale',
        -line.baseQuantity,
        note.trim().isEmpty ? 'Cash sale' : note.trim(),
        reference: ref,
        photo: photo,
        price: line.unitPrice,
        saleUnit: line.unitName,
        saleUnitMultiplier: line.unitMultiplier,
        saleQuantity: line.quantity,
        lineTotal: line.total,
      );
    }
    return ref;
  }

  /// Records selected selling units while deducting their converted total in
  /// the product's base unit.
  Future<String> checkoutSale(SaleCart cart, String note, {String? photo}) =>
      _commit(() => _checkoutLines(cart, note, photo: photo));

  /// Kept for existing callers and imports that use one base-unit price per
  /// product. New checkout UI uses [checkoutSale].
  Future<String> checkout(
    Map<String, int> cart,
    String note, {
    String? photo,
  }) => _commit(
    () => _checkoutLines(SaleCart.fromLegacy(cart, this), note, photo: photo),
  );
  Future<void> startCount({String? category, List<String>? productIds}) =>
      _commit(() {
        if (_products.isEmpty) {
          throw StateError('Add products before starting a count.');
        }
        if (count != null) throw StateError('A count is already active.');

        var targetProducts = _products;
        String scopeLabel = 'All items';

        if (category != null &&
            category.trim().isNotEmpty &&
            category != 'All items' &&
            category != 'All') {
          targetProducts = _products
              .where(
                (p) =>
                    p.category.toLowerCase() == category.trim().toLowerCase(),
              )
              .toList();
          if (targetProducts.isEmpty) {
            throw StateError('No products found in category "$category".');
          }
          scopeLabel = category.trim();
        } else if (productIds != null && productIds.isNotEmpty) {
          final idSet = productIds.toSet();
          targetProducts = _products
              .where((p) => idSet.contains(p.id))
              .toList();
          if (targetProducts.isEmpty) {
            throw StateError('No matching products found for the count.');
          }
          scopeLabel = 'Selected products';
        }

        count = {
          'id': newId(),
          'at': DateTime.now().toUtc().toIso8601String(),
          'scope': scopeLabel,
          'baseline': {for (final p in targetProducts) p.id: stock(p)},
          'names': {for (final p in targetProducts) p.id: p.name},
          'values': <String, dynamic>{},
        };
      });
  Future<void> setCount(String id, int quantity) => _commit(() {
    if (count == null ||
        quantity < 0 ||
        !(count!['baseline'] as Map).containsKey(id)) {
      throw StateError('Invalid count entry.');
    }
    (count!['values'] as Map)[id] = quantity;
  });
  Future<void> cancelCount() => _commit(() {
    count = null;
  });
  Future<void> postCount() => _commit(() {
    if (count == null) throw StateError('There is no active count.');
    final values = count!['values'] as Map;
    final baseline = count!['baseline'] as Map;
    if (values.length != baseline.length) {
      throw StateError(
        'Count every item before posting. Enter 0 for empty stock.',
      );
    }
    for (final id in baseline.keys) {
      final p = product(id);
      if (stock(p) != baseline[id]) {
        throw StateError('Stock changed during counting. Restart the count.');
      }
      final delta = (values[id] as int) - (baseline[id] as int);
      if (delta != 0) {
        _movement(
          p,
          'Stock count',
          delta,
          'Expected ${baseline[id]}; counted ${values[id]}',
          reference: count!['id'],
        );
      }
    }
    // Keep the reviewed snapshot even when every variance is zero.
    final scope = (count!['scope'] as String?) ?? 'All items';
    _received.add({
      'kind': scope == 'All items' ? 'Posted count' : 'Posted count ($scope)',
      'shop': shop,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'id': count!['id'],
      'scope': scope,
      'count': jsonDecode(jsonEncode(count)),
    });
    count = null;
  });
  Future<void> settings(String name, String code) => _commit(() {
    shop = name.trim().isEmpty ? 'My store' : name.trim();
    currency = code;
  });

  Map<String, dynamic> fullBackup() {
    final now = DateTime.now().toUtc().toIso8601String();
    return {
      'format': 'stockmix-full-backup',
      'version': 1,
      'createdAt': now,
      'shop': shop,
      'currency': currency,
      'products': _products.map((p) => p.toJson()).toList(),
      'movements': _movements.map((m) => m.toJson()).toList(),
      'received': _received,
      'count': count,
      'heldSales': _heldSales,
    };
  }

  Future<void> markBackupCompleted() => _commit(() {
    lastBackupAt = DateTime.now().toUtc().toIso8601String();
  });

  Future<void> restoreFullBackup(Map<String, dynamic> data) => _commit(() {
    if (data['format'] != 'stockmix-full-backup' || data['version'] != 1) {
      throw const FormatException('Invalid Stockmix backup file.');
    }
    if (data['products'] is! List || data['movements'] is! List) {
      throw const FormatException(
        'Backup file is missing required inventory data.',
      );
    }
    _products = (data['products'] as List)
        .map((p) => Product.fromJson(Map<String, dynamic>.from(p)))
        .toList();
    _movements = (data['movements'] as List)
        .map((m) => Movement.fromJson(Map<String, dynamic>.from(m)))
        .toList();
    _received = (data['received'] as List? ?? [])
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    _heldSales = (data['heldSales'] as List? ?? [])
        .map((h) => Map<String, dynamic>.from(h))
        .toList();
    count = data['count'] == null
        ? null
        : Map<String, dynamic>.from(data['count']);
    shop = data['shop'] ?? 'My store';
    userName = data['userName'] ?? '';
    currency = data['currency'] ?? 'USD';
    setupCompleted = true;
    lastBackupAt = DateTime.now().toUtc().toIso8601String();
  });

  Map<String, dynamic> bundle({DateTime? day, bool includePhotos = true}) => {
    'format': 'stockmix',
    'version': 1,
    'id': newId(),
    'kind': day == null ? 'Stock snapshot' : 'Day record',
    'shop': shop,
    'senderName': userName.trim().isEmpty ? shop : userName.trim(),
    'currency': currency,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'day': day == null ? null : dayKey(day),
    'products': _products.map((p) {
      final json = p.toJson();
      if (!includePhotos) json['photo'] = null;
      return {...json, 'onHand': stock(p)};
    }).toList(),
    'movements': (day == null ? _movements : onDay(day)).map((m) {
      final json = m.toJson();
      if (!includePhotos) json['photo'] = null;
      return json;
    }).toList(),
  };
  static Map<String, dynamic> decodeBundle(String content) {
    if (content.length > 30 * 1024 * 1024) {
      throw const FormatException('File is too large. Maximum size is 30 MB.');
    }
    final value = jsonDecode(content);
    if (value is! Map<String, dynamic> ||
        value['format'] != 'stockmix' ||
        value['version'] != 1 ||
        value['id'] is! String ||
        value['shop'] is! String ||
        (value['senderName'] != null && value['senderName'] is! String) ||
        value['products'] is! List ||
        value['movements'] is! List ||
        !['Stock snapshot', 'Day record'].contains(value['kind'])) {
      throw const FormatException('Choose a Stockmix JSON export.');
    }
    DateTime.parse(value['exportedAt']);
    final ids = <String>{}, codes = <String>{};
    for (final item in value['products']) {
      final p = Product.fromJson(Map<String, dynamic>.from(item));
      if (!ids.add(p.id) ||
          p.name.trim().isEmpty ||
          p.price < 0 ||
          p.cost < 0 ||
          p.threshold < 0 ||
          p.packSize < 1 ||
          (p.packSize > 1 && p.packPrice == null) ||
          (p.packPrice != null && p.packPrice! < 0) ||
          item['onHand'] is! int ||
          item['onHand'] < 0 ||
          (p.barcode.isNotEmpty && !codes.add(normalizeCode(p.barcode)))) {
        throw const FormatException('Invalid or duplicate product in export.');
      }
      if (p.photo != null) {
        if (p.photo!.length > 700000) {
          throw const FormatException('An image is too large.');
        }
        base64Decode(p.photo!);
      }
    }
    final movementIds = <String>{};
    for (final item in value['movements']) {
      final m = Movement.fromJson(Map<String, dynamic>.from(item));
      if (!ids.contains(m.productId) ||
          !movementIds.add(m.id) ||
          m.price < 0 ||
          m.cost < 0) {
        throw const FormatException('Invalid movement in export.');
      }
      DateTime.parse(m.at);
      if (m.photo != null) {
        if (m.photo!.length > 700000) {
          throw const FormatException('An image is too large.');
        }
        base64Decode(m.photo!);
      }
    }
    return value;
  }

  Future<void> importBundle(
    Map<String, dynamic> data, {
    bool addProducts = false,
  }) => _commit(() {
    final checked = decodeBundle(jsonEncode(data));
    if (_received.any((r) => r['id'] == checked['id'])) {
      throw StateError('This file has already been imported.');
    }
    if (addProducts) {
      if (checked['currency'] != currency ||
          checked['kind'] != 'Stock snapshot') {
        throw StateError(
          'Only stock snapshots in your store currency can add products.',
        );
      }
      if (count != null) {
        throw StateError('Finish the stock count before importing products.');
      }
      for (final item in checked['products']) {
        final p = Product.fromJson(Map<String, dynamic>.from(item));
        final existingIndex = _products.indexWhere(
          (existing) =>
              existing.id == p.id ||
              (p.barcode.isNotEmpty &&
                  normalizeCode(existing.barcode) == normalizeCode(p.barcode)),
        );
        if (existingIndex >= 0) {
          final existing = _products[existingIndex];
          if (existing.photo == null && p.photo != null) {
            _products[existingIndex] = Product(
              id: existing.id,
              name: existing.name,
              category: existing.category,
              barcode: existing.barcode,
              price: existing.price,
              cost: existing.cost,
              opening: existing.opening,
              threshold: existing.threshold,
              unit: existing.unit,
              photo: p.photo,
              expiryDate: existing.expiryDate,
              label: existing.label,
              packSize: existing.packSize,
              packPrice: existing.packPrice,
              defaultSellingUnit: existing.defaultSellingUnit,
            );
          }
          continue;
        }
        _validateProduct(p);
        _products.add(p);
        final qty = item['onHand'] as int;
        if (qty > 0) {
          _movement(
            p,
            'Opening stock',
            qty,
            'Imported from ${checked['shop']}',
          );
        }
      }
    }
    _received.add(checked);
  });

  Future<void> importStreamBundle(
    Map<String, dynamic> data, {
    bool addProducts = false,
    bool importMovements = false,
  }) => _commit(() {
    final checked = decodeBundle(jsonEncode(data));
    final bundleHash = sha256.convert(utf8.encode(jsonEncode(data))).toString();
    final alreadyReceived = _received.any(
      (r) => r['id'] == checked['id'] || r['bundleHash'] == bundleHash,
    );

    if (addProducts) {
      if (checked['currency'] != currency) {
        throw StateError(
          'Cannot import products because currency differs ($currency vs ${checked['currency']}).',
        );
      }
      if (count != null) {
        throw StateError('Finish the stock count before importing products.');
      }
      for (final item in checked['products']) {
        final p = Product.fromJson(Map<String, dynamic>.from(item));
        final existingIndex = _products.indexWhere(
          (existing) =>
              existing.id == p.id ||
              (p.barcode.isNotEmpty &&
                  normalizeCode(existing.barcode) == normalizeCode(p.barcode)),
        );
        if (existingIndex >= 0) {
          final existing = _products[existingIndex];
          if (existing.photo == null && p.photo != null) {
            _products[existingIndex] = Product(
              id: existing.id,
              name: existing.name,
              category: existing.category,
              barcode: existing.barcode,
              price: existing.price,
              cost: existing.cost,
              opening: existing.opening,
              threshold: existing.threshold,
              unit: existing.unit,
              photo: p.photo,
              expiryDate: existing.expiryDate,
              label: existing.label,
              packSize: existing.packSize,
              packPrice: existing.packPrice,
              defaultSellingUnit: existing.defaultSellingUnit,
            );
          }
          continue;
        }
        _validateProduct(p);
        _products.add(p);
        final qty = (item['onHand'] as int?) ?? p.opening;
        if (qty > 0) {
          _movement(
            p,
            'Opening stock',
            qty,
            'Streamed from ${checked['shop']}',
          );
        }
      }
    }

    if (importMovements && checked['kind'] == 'Day record') {
      for (final item in checked['movements']) {
        final m = Movement.fromJson(Map<String, dynamic>.from(item));
        final isDup = _movements.any(
          (existing) =>
              existing.id == m.id ||
              (existing.reference == m.reference &&
                  existing.productId == m.productId &&
                  existing.delta == m.delta),
        );
        if (isDup) continue;
        final localProduct = _products
            .where((p) => p.id == m.productId)
            .firstOrNull;
        if (localProduct != null) {
          _movements.add(m);
        }
      }
    }

    if (!alreadyReceived) {
      final savedRecord = Map<String, dynamic>.from(checked);
      savedRecord['bundleHash'] = bundleHash;
      _received.add(savedRecord);
    }

    return;
  });

  Future<void> deleteReceived(String id) => _commit(() {
    _received.removeWhere((r) => r['id'] == id);
  });

  double _exchangeRateFor(Map<String, dynamic> record, double? exchangeRate) {
    if (record['currency'] == currency) return 1;
    if (exchangeRate == null || !exchangeRate.isFinite || exchangeRate <= 0) {
      throw StateError(
        'Enter a valid exchange rate to merge ${record['currency']} into $currency.',
      );
    }
    return exchangeRate;
  }

  int _convertMoney(int value, double exchangeRate) =>
      (value * exchangeRate).round();

  Product _convertProduct(Product product, double exchangeRate) {
    if (exchangeRate == 1) return product;
    return Product(
      id: product.id,
      name: product.name,
      category: product.category,
      barcode: product.barcode,
      price: _convertMoney(product.price, exchangeRate),
      cost: _convertMoney(product.cost, exchangeRate),
      opening: product.opening,
      threshold: product.threshold,
      unit: product.unit,
      photo: product.photo,
      expiryDate: product.expiryDate,
      label: product.label,
      packSize: product.packSize,
      packPrice: product.packPrice == null
          ? null
          : _convertMoney(product.packPrice!, exchangeRate),
      defaultSellingUnit: product.defaultSellingUnit,
    );
  }

  Movement _convertMovement(Movement movement, double exchangeRate) {
    if (exchangeRate == 1) return movement;
    return Movement(
      id: movement.id,
      productId: movement.productId,
      name: movement.name,
      type: movement.type,
      delta: movement.delta,
      price: _convertMoney(movement.price, exchangeRate),
      cost: _convertMoney(movement.cost, exchangeRate),
      note: movement.note,
      reference: movement.reference,
      at: movement.at,
      photo: movement.photo,
      saleUnit: movement.saleUnit,
      saleUnitMultiplier: movement.saleUnitMultiplier,
      saleQuantity: movement.saleQuantity,
      lineTotal: movement.lineTotal == null
          ? null
          : _convertMoney(movement.lineTotal!, exchangeRate),
      returnOf: movement.returnOf,
    );
  }

  Future<Map<String, int>> mergeReceived(
    String id, {
    bool addProducts = true,
    bool importMovements = true,
    double? exchangeRate,
  }) => _commit(() {
    final recordIndex = _received.indexWhere((r) => r['id'] == id);
    if (recordIndex < 0) {
      throw StateError('Received record not found.');
    }
    final record = _received[recordIndex];
    final rate = _exchangeRateFor(record, exchangeRate);
    if (count != null) {
      throw StateError('Finish the stock count before merging records.');
    }

    var newProductsCount = 0;
    var backfilledPhotosCount = 0;
    var skippedProductsCount = 0;
    var newMovementsCount = 0;
    var skippedMovementsCount = 0;

    if (addProducts && record['products'] is List) {
      for (final item in record['products']) {
        final p = _convertProduct(
          Product.fromJson(Map<String, dynamic>.from(item)),
          rate,
        );
        final existingIndex = _products.indexWhere(
          (existing) =>
              existing.id == p.id ||
              (p.barcode.isNotEmpty &&
                  normalizeCode(existing.barcode) == normalizeCode(p.barcode)),
        );
        if (existingIndex >= 0) {
          final existing = _products[existingIndex];
          if (existing.photo == null && p.photo != null) {
            _products[existingIndex] = Product(
              id: existing.id,
              name: existing.name,
              category: existing.category,
              barcode: existing.barcode,
              price: existing.price,
              cost: existing.cost,
              opening: existing.opening,
              threshold: existing.threshold,
              unit: existing.unit,
              photo: p.photo,
              expiryDate: existing.expiryDate,
              label: existing.label,
              packSize: existing.packSize,
              packPrice: existing.packPrice,
              defaultSellingUnit: existing.defaultSellingUnit,
            );
            backfilledPhotosCount++;
          } else {
            skippedProductsCount++;
          }
          continue;
        }
        _validateProduct(p);
        _products.add(p);
        newProductsCount++;
        final qty = (item['onHand'] as int?) ?? p.opening;
        if (qty > 0) {
          _movement(p, 'Opening stock', qty, 'Merged from ${record['shop']}');
        }
      }
    }

    if (importMovements &&
        record['kind'] == 'Day record' &&
        record['movements'] is List) {
      for (final item in record['movements']) {
        final m = _convertMovement(
          Movement.fromJson(Map<String, dynamic>.from(item)),
          rate,
        );
        final isDup = _movements.any(
          (existing) =>
              existing.id == m.id ||
              (existing.reference == m.reference &&
                  existing.productId == m.productId &&
                  existing.delta == m.delta),
        );
        if (isDup) {
          skippedMovementsCount++;
          continue;
        }
        final localProduct = _products
            .where((p) => p.id == m.productId)
            .firstOrNull;
        if (localProduct != null) {
          _movements.add(m);
          newMovementsCount++;
        }
      }
    }

    return {
      'newProducts': newProductsCount,
      'backfilledPhotos': backfilledPhotosCount,
      'skippedProducts': skippedProductsCount,
      'newMovements': newMovementsCount,
      'skippedMovements': skippedMovementsCount,
    };
  });

  Map<String, dynamic> previewMerge(
    String id, {
    bool addProducts = true,
    bool importMovements = true,
    double? exchangeRate,
  }) {
    final recordIndex = _received.indexWhere((r) => r['id'] == id);
    if (recordIndex < 0) {
      throw StateError('Received record not found.');
    }
    final record = _received[recordIndex];
    _exchangeRateFor(record, exchangeRate);
    if (count != null) {
      throw StateError('Finish the stock count before merging records.');
    }

    final stockChanges = <Map<String, dynamic>>[];
    final addedProducts = <String, Map<String, dynamic>>{};
    int newProductsCount = 0;
    int backfilledPhotosCount = 0;
    int skippedProductsCount = 0;
    int newMovementsCount = 0;
    int skippedMovementsCount = 0;

    if (addProducts && record['products'] is List) {
      for (final item in record['products']) {
        final p = Product.fromJson(Map<String, dynamic>.from(item));
        final existing = _products
            .where(
              (e) =>
                  e.id == p.id ||
                  (p.barcode.isNotEmpty &&
                      normalizeCode(e.barcode) == normalizeCode(p.barcode)),
            )
            .firstOrNull;

        if (existing != null) {
          if (existing.photo == null && p.photo != null) {
            backfilledPhotosCount++;
          } else {
            skippedProductsCount++;
          }
        } else {
          newProductsCount++;
          final initialQty = (item['onHand'] as int?) ?? p.opening;
          final change = {
            'productId': p.id,
            'name': p.name,
            'unit': p.unit,
            'currentStock': 0,
            'delta': initialQty,
            'newStock': initialQty,
            'isNew': true,
          };
          stockChanges.add(change);
          addedProducts[p.id] = change;
        }
      }
    }

    if (importMovements &&
        record['kind'] == 'Day record' &&
        record['movements'] is List) {
      final movementDeltas = <String, int>{};
      for (final item in record['movements']) {
        final m = Movement.fromJson(Map<String, dynamic>.from(item));
        final isDup = _movements.any(
          (existing) =>
              existing.id == m.id ||
              (existing.reference == m.reference &&
                  existing.productId == m.productId &&
                  existing.delta == m.delta),
        );
        if (isDup) {
          skippedMovementsCount++;
          continue;
        }
        final productExists =
            _products.any((p) => p.id == m.productId) ||
            addedProducts.containsKey(m.productId);
        if (productExists) {
          movementDeltas[m.productId] =
              (movementDeltas[m.productId] ?? 0) + m.delta;
          newMovementsCount++;
        }
      }

      for (final entry in movementDeltas.entries) {
        final pId = entry.key;
        final delta = entry.value;
        if (delta == 0) continue;

        if (addedProducts.containsKey(pId)) {
          final sc = addedProducts[pId]!;
          final initialDelta = sc['delta'] as int;
          final totalDelta = initialDelta + delta;
          sc['delta'] = totalDelta;
          sc['newStock'] = totalDelta;
        } else {
          final p = product(pId);
          final current = stock(p);
          stockChanges.add({
            'productId': p.id,
            'name': p.name,
            'unit': p.unit,
            'currentStock': current,
            'delta': delta,
            'newStock': current + delta,
            'isNew': false,
          });
        }
      }
    }

    return {
      'record': record,
      'stockChanges': stockChanges,
      'newProductsCount': newProductsCount,
      'backfilledPhotosCount': backfilledPhotosCount,
      'skippedProductsCount': skippedProductsCount,
      'newMovementsCount': newMovementsCount,
      'skippedMovementsCount': skippedMovementsCount,
    };
  }

  String csv({DateTime? day}) {
    String cell(Object? v) {
      var text = '${v ?? ''}';
      if (RegExp(r'^\s*[=+@-]').hasMatch(text)) text = "'$text";
      return '"${text.replaceAll('"', '""')}"';
    }

    final rows = day == null
        ? <List<Object?>>[
            [
              'Item',
              'Category',
              'Barcode',
              'On hand',
              'Unit',
              'Price ($currency)',
              'Cost ($currency)',
              'Low stock threshold',
            ],
            ..._products.map(
              (p) => [
                p.name,
                p.category,
                p.barcode,
                stock(p),
                p.unit,
                (p.price / 100).toStringAsFixed(2),
                (p.cost / 100).toStringAsFixed(2),
                p.threshold,
              ],
            ),
          ]
        : <List<Object?>>[
            [
              'Date (UTC)',
              'Item',
              'Type',
              'Quantity change',
              'Unit price ($currency)',
              'Sale total ($currency)',
              'Note',
              'Reference',
            ],
            ...onDay(day).map(
              (m) => [
                m.at,
                m.name,
                m.type,
                m.delta,
                (m.price / 100).toStringAsFixed(2),
                m.type == 'Sale' ? (saleTotal(m) / 100).toStringAsFixed(2) : '',
                m.note,
                m.reference,
              ],
            ),
          ];
    return '${rows.map((r) => r.map(cell).join(',')).join('\r\n')}\r\n';
  }

  Future<void> loadDemo() => _commit(() {
    if (_products.isNotEmpty) {
      throw StateError('Demo items can only be added to an empty store.');
    }
    const names = [
      'Ceramic everyday mug',
      'Oat milk · 1 litre',
      'House blend coffee',
      'Linen market tote',
      'Botanical hand soap',
      'Wildflower honey',
    ];
    const categories = [
      'Home',
      'Pantry',
      'Pantry',
      'Lifestyle',
      'Care',
      'Pantry',
    ];
    const prices = [1800, 450, 1600, 2400, 950, 1250];
    const quantities = [24, 8, 32, 16, 5, 20];
    for (var i = 0; i < names.length; i++) {
      final p = Product(
        id: newId(),
        name: names[i],
        category: categories[i],
        barcode: 'SM00${i + 1}',
        price: prices[i],
        cost: prices[i] ~/ 2,
        opening: quantities[i],
        threshold: 8,
      );
      _products.add(p);
      _movement(p, 'Opening stock', quantities[i], 'Sample data');
    }
    _movement(
      _products[0],
      'Sale',
      -3,
      'Sample cash sale',
      reference: 'demo-sale',
    );
    _movement(
      _products[2],
      'Sale',
      -2,
      'Sample cash sale',
      reference: 'demo-sale',
    );
    setupCompleted = true;
  });
}
