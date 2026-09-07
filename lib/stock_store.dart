import 'dart:convert';
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

int parseMoney(String text) {
  final value = text.trim();
  if (!RegExp(r'^\d{1,9}(\.\d{1,2})?$').hasMatch(value)) {
    throw const FormatException('Enter a price with up to two decimal places.');
  }
  final parts = value.split('.');
  return int.parse(parts[0]) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
}

class Product {
  final String id, name, category, barcode, unit;
  final int price, cost, opening, threshold;
  final String? photo;
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
  });
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
  );
}

class Movement {
  final String id, productId, name, type, note, reference, at;
  final int delta, price, cost;
  final String? photo;
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
  bool setupCompleted = false;
  String? lastBackupAt;
  bool busy = false;

  List<Product> get products => List.unmodifiable(_products);
  List<Movement> get movements => List.unmodifiable(_movements);
  List<Map<String, dynamic>> get received => List.unmodifiable(_received);
  List<Map<String, dynamic>> get heldSales => List.unmodifiable(_heldSales);
  List<String> get categories {
    final set = <String>{};
    for (final p in _products) {
      if (p.category.trim().isNotEmpty) set.add(p.category.trim());
    }
    return set.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
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
    'currency': currency,
    'setupCompleted': setupCompleted,
    'lastBackupAt': lastBackupAt,
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
    currency = data['currency'] ?? 'USD';
    setupCompleted = data['setupCompleted'] ?? (_products.isNotEmpty || _movements.isNotEmpty);
    lastBackupAt = data['lastBackupAt'];
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
  Product? lookup(String code) {
    final key = normalizeCode(code);
    if (key.isEmpty) return null;
    for (final p in _products) {
      if (normalizeCode(p.barcode) == key) return p;
    }
    return null;
  }

  List<Movement> onDay(DateTime day) => _movements
      .where((m) => dayKey(DateTime.parse(m.at).toLocal()) == dayKey(day))
      .toList();
  int revenue(DateTime day) => onDay(
    day,
  ).where((m) => m.type == 'Sale').fold(0, (n, m) => n - m.delta * m.price);
  int get units => _products.fold(0, (n, p) => n + stock(p));
  int get valuation => _products.fold(0, (n, p) => n + stock(p) * p.cost);
  List<Product> get low =>
      _products.where((p) => stock(p) <= p.threshold).toList();

  Future<void> completeSetup(String storeName, String currencyCode) => _commit(() {
    if (storeName.trim().isNotEmpty) {
      shop = storeName.trim();
    }
    if (_movements.isEmpty) {
      currency = currencyCode;
    }
    setupCompleted = true;
  });

  // --- Held Sales ---
  Future<void> holdSale(Map<String, int> cart, {String note = ''}) => _commit(() {
    if (cart.isEmpty) throw StateError('Cannot hold an empty sale.');
    _heldSales.add({
      'id': newId(),
      'heldAt': DateTime.now().toUtc().toIso8601String(),
      'cart': Map<String, int>.from(cart),
      'note': note.trim(),
    });
  });

  Future<Map<String, int>?> resumeSale(String id) => _commit(() {
    final index = _heldSales.indexWhere((h) => h['id'] == id);
    if (index < 0) return null;
    final held = _heldSales.removeAt(index);
    return Map<String, int>.from(held['cart'] as Map);
  });

  Future<void> deleteHeldSale(String id) => _commit(() {
    _heldSales.removeWhere((h) => h['id'] == id);
  });

  // --- Linked Returns ---
  Future<void> processReturn({
    required Movement saleMovement,
    required int returnQty,
    required bool returnToStock,
    required bool refundMoney,
    String note = '',
  }) => _commit(() {
    if (saleMovement.type != 'Sale') {
      throw StateError('Returns can only be processed on sales.');
    }
    final maxReturn = -saleMovement.delta;
    if (returnQty <= 0 || returnQty > maxReturn) {
      throw StateError('Invalid return quantity (max $maxReturn).');
    }
    final prod = _products.where((p) => p.id == saleMovement.productId).firstOrNull;
    if (prod == null) {
      throw StateError('Product no longer exists.');
    }

    final reason = note.trim().isEmpty ? 'Customer return' : note.trim();
    final returnRef = 'ret-${saleMovement.reference}';

    if (returnToStock) {
      _movement(
        prod,
        'Return restock',
        returnQty,
        '$reason (${refundMoney ? 'Refunded' : 'Exchanged'})',
        reference: returnRef,
      );
    }

    if (refundMoney) {
      _movement(
        prod,
        'Return refund',
        returnToStock ? 0 : 0, // delta is 0 for cash adjustment only if not restocked or balance adjustment
        '$reason (Refunded ${moneyString(saleMovement.price * returnQty)})',
        reference: returnRef,
      );
    }
  });

  // --- Batch Reorder Receiving ---
  Future<int> batchReceive(Map<String, int> receivedQuantities, {String supplier = ''}) => _commit(() {
    if (count != null) {
      throw StateError('Finish or cancel active stock count before receiving goods.');
    }
    var totalUnits = 0;
    final note = supplier.trim().isEmpty ? 'Supplier restock' : 'Delivery from ${supplier.trim()}';
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
    final startDate = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
    final endDate = now.add(const Duration(days: 1));
    final periodMovements = movementsInPeriod(startDate, endDate);
    final sales = periodMovements.where((m) => m.type == 'Sale').toList();

    var totalRevenue = 0;
    var totalCost = 0;
    var itemsMissingCost = 0;
    final itemSalesCount = <String, int>{};
    final itemSalesRevenue = <String, int>{};

    for (final sale in sales) {
      final qty = -sale.delta;
      final rev = qty * sale.price;
      totalRevenue += rev;
      totalCost += qty * sale.cost;
      if (sale.cost <= 0) {
        itemsMissingCost++;
      }
      itemSalesCount[sale.productId] = (itemSalesCount[sale.productId] ?? 0) + qty;
      itemSalesRevenue[sale.productId] = (itemSalesRevenue[sale.productId] ?? 0) + rev;
    }

    final estimatedGrossProfit = totalRevenue - totalCost;

    // Top selling items
    final sortedItemIds = itemSalesCount.keys.toList()
      ..sort((a, b) => (itemSalesCount[b] ?? 0).compareTo(itemSalesCount[a] ?? 0));
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
        .where((m) => m.type == 'Sale' && DateTime.parse(m.at).toLocal().isAfter(fourteenDaysAgo))
        .map((m) => m.productId)
        .toSet();

    final slowMovers = _products
        .where((p) => stock(p) > 0 && !recentSaleProductIds.contains(p.id))
        .map((p) => {
              'id': p.id,
              'name': p.name,
              'stock': stock(p),
              'unit': p.unit,
              'valuation': stock(p) * p.cost,
            })
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
  }) {
    _movements.add(
      Movement(
        id: newId(),
        productId: p.id,
        name: p.name,
        type: type,
        delta: delta,
        price: p.price,
        cost: p.cost,
        note: note,
        reference: reference ?? newId(),
        at: DateTime.now().toUtc().toIso8601String(),
        photo: photo,
      ),
    );
  }

  void _validateProduct(Product p) {
    if (p.name.trim().isEmpty ||
        p.name.length > 100 ||
        p.price < 0 ||
        p.cost < 0 ||
        p.opening < 0 ||
        p.threshold < 0) {
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
      throw StateError('Finish or cancel the active count before deleting this item.');
    }
    final p = _products.where((item) => item.id == id).firstOrNull;
    if (p == null) {
      throw StateError('Item not found.');
    }
    final onHand = stock(p);
    if (onHand > 0) {
      throw StateError(
        'This item still has $onHand ${p.unit} in stock. Adjust or sell stock to 0 before deleting.',
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
  Future<String> checkout(Map<String, int> cart, String note, {String? photo}) =>
      _commit(() {
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
        for (final line in cart.entries) {
          if (line.value <= 0 || line.value > stock(product(line.key))) {
            throw StateError('Not enough stock for ${product(line.key).name}.');
          }
        }
        final ref = newId();
        for (final line in cart.entries) {
          _movement(
            product(line.key),
            'Sale',
            -line.value,
            note.trim().isEmpty ? 'Cash sale' : note.trim(),
            reference: ref,
            photo: photo,
          );
        }
        return ref;
      });
  Future<void> startCount({String? category, List<String>? productIds}) => _commit(() {
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
          .where((p) => p.category.toLowerCase() == category.trim().toLowerCase())
          .toList();
      if (targetProducts.isEmpty) {
        throw StateError('No products found in category "$category".');
      }
      scopeLabel = category.trim();
    } else if (productIds != null && productIds.isNotEmpty) {
      final idSet = productIds.toSet();
      targetProducts = _products.where((p) => idSet.contains(p.id)).toList();
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
      throw const FormatException('Backup file is missing required inventory data.');
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
    count = data['count'] == null ? null : Map<String, dynamic>.from(data['count']);
    shop = data['shop'] ?? 'My store';
    currency = data['currency'] ?? 'USD';
    setupCompleted = true;
    lastBackupAt = DateTime.now().toUtc().toIso8601String();
  });

  Map<String, dynamic> bundle({
    DateTime? day,
    bool includePhotos = true,
  }) => {
    'format': 'stockmix',
    'version': 1,
    'id': newId(),
    'kind': day == null ? 'Stock snapshot' : 'Day record',
    'shop': shop,
    'currency': currency,
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'day': day == null ? null : dayKey(day),
    'products': _products
        .map((p) {
          final json = p.toJson();
          if (!includePhotos) json['photo'] = null;
          return {...json, 'onHand': stock(p)};
        })
        .toList(),
    'movements': (day == null ? _movements : onDay(day))
        .map((m) {
          final json = m.toJson();
          if (!includePhotos) json['photo'] = null;
          return json;
        })
        .toList(),
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
        final localProduct =
            _products.where((p) => p.id == m.productId).firstOrNull;
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

  Future<Map<String, int>> mergeReceived(
    String id, {
    bool addProducts = true,
    bool importMovements = true,
  }) => _commit(() {
    final recordIndex = _received.indexWhere((r) => r['id'] == id);
    if (recordIndex < 0) {
      throw StateError('Received record not found.');
    }
    final record = _received[recordIndex];
    if (record['currency'] != currency) {
      throw StateError(
        'Cannot merge because currency differs ($currency vs ${record['currency']}).',
      );
    }
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
          _movement(
            p,
            'Opening stock',
            qty,
            'Merged from ${record['shop']}',
          );
        }
      }
    }

    if (importMovements &&
        record['kind'] == 'Day record' &&
        record['movements'] is List) {
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
        final localProduct =
            _products.where((p) => p.id == m.productId).firstOrNull;
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
  }) {
    final recordIndex = _received.indexWhere((r) => r['id'] == id);
    if (recordIndex < 0) {
      throw StateError('Received record not found.');
    }
    final record = _received[recordIndex];
    if (record['currency'] != currency) {
      throw StateError(
        'Cannot merge: File currency (${record['currency']}) differs from your store ($currency).',
      );
    }
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
        final existing = _products.where(
          (e) =>
              e.id == p.id ||
              (p.barcode.isNotEmpty &&
                  normalizeCode(e.barcode) == normalizeCode(p.barcode)),
        ).firstOrNull;

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
            _products.any((p) => p.id == m.productId) || addedProducts.containsKey(m.productId);
        if (productExists) {
          movementDeltas[m.productId] = (movementDeltas[m.productId] ?? 0) + m.delta;
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
                m.type == 'Sale'
                    ? (-m.delta * m.price / 100).toStringAsFixed(2)
                    : '',
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
