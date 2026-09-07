import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:stockmix/design.dart';
import 'package:stockmix/stock_store.dart';

Product item({
  String id = 'p1',
  String name = 'Coffee',
  String code = '1234567890123',
  int opening = 10,
  int price = 450,
}) => Product(
  id: id,
  name: name,
  category: 'Pantry',
  barcode: code,
  price: price,
  cost: 200,
  opening: opening,
  threshold: 3,
);
void main() {
  late StockStore store;
  setUp(() => store = StockStore(persist: (_) async {}));
  test('receive 10, sell 3, restock 1 nets eight units with history', () async {
    final p = item(opening: 0);
    await store.saveProduct(p);
    await store.adjust(p, 10, 'Received', 'Supplier');
    await store.checkout({p.id: 3}, 'Cash');
    await store.adjust(p, 1, 'Return restock', 'Customer return');
    expect(store.stock(p), 8);
    expect(store.movements.map((m) => m.delta), [10, -3, 1]);
    expect(store.revenue(DateTime.now()), 1350);
  });
  test('insufficient stock rejects entire multi-item sale', () async {
    final a = item(), b = item(id: 'p2', code: 'second', opening: 1);
    await store.saveProduct(a);
    await store.saveProduct(b);
    await expectLater(store.checkout({'p1': 2, 'p2': 3}, ''), throwsStateError);
    expect(store.stock(a), 10);
    expect(store.stock(b), 1);
    expect(store.movements.where((m) => m.type == 'Sale'), isEmpty);
  });
  test('failed persistence rolls back stock and history', () async {
    var fail = false;
    store = StockStore(
      persist: (_) async {
        if (fail) throw StateError('Disk full');
      },
    );
    final p = item();
    await store.saveProduct(p);
    fail = true;
    await expectLater(store.checkout({'p1': 2}, ''), throwsStateError);
    expect(store.stock(p), 10);
    expect(store.movements.length, 1);
    expect(store.busy, isFalse);
  });
  test('normalized barcode uniqueness and Digital Link lookup', () async {
    final p = item();
    await store.saveProduct(p);
    expect(store.lookup('https://id.example/01/01234567890123/10/LOT'), p);
    await expectLater(
      store.saveProduct(item(id: 'p2', code: '01234567890123')),
      throwsStateError,
    );
  });
  test('price change leaves historical sale totals intact', () async {
    await store.saveProduct(item());
    await store.checkout({'p1': 2}, '');
    await store.saveProduct(item(price: 900));
    expect(store.revenue(DateTime.now()), 900);
  });
  test('count freezes stock changes and requires all entries', () async {
    await store.saveProduct(item());
    await store.saveProduct(item(id: 'p2', code: 'second'));
    await store.startCount();
    await expectLater(store.checkout({'p1': 1}, ''), throwsStateError);
    await store.setCount('p1', 7);
    await expectLater(store.postCount(), throwsStateError);
    await store.setCount('p2', 0);
    await store.postCount();
    expect(store.stock(store.product('p1')), 7);
    expect(store.stock(store.product('p2')), 0);
    expect(store.received.single['kind'], 'Posted count');
    expect(store.count, isNull);
  });
  test(
    'durable store survives reopen including count draft and photo',
    () async {
      final db = await databaseFactoryMemory.openDatabase('durable-test');
      store = await StockStore.open(db);
      final photo = base64Encode([1, 2, 3]);
      await store.saveProduct(item());
      await store.adjust(item(), 2, 'Received', 'Supplier', photo: photo);
      await store.startCount();
      await store.setCount('p1', 11);
      final reloaded = await StockStore.open(db);
      expect(reloaded.stock(reloaded.product('p1')), 12);
      expect(reloaded.count!['values']['p1'], 11);
      expect(reloaded.movements.last.photo, photo);
      await db.close();
    },
  );
  test(
    'shared file roundtrip, duplicate prevention, no inventory replay',
    () async {
      await store.saveProduct(item());
      await store.checkout({'p1': 2}, '');
      final data = StockStore.decodeBundle(jsonEncode(store.bundle()));
      final target = StockStore(persist: (_) async {});
      await target.importBundle(data);
      expect(target.products, isEmpty);
      expect(target.received.length, 1);
      await expectLater(target.importBundle(data), throwsStateError);
      final another = StockStore(persist: (_) async {});
      await another.importBundle(data, addProducts: true);
      expect(another.stock(another.products.single), 8);
      expect(another.revenue(DateTime.now()), 0);
    },
  );
  test('import never overwrites existing product stock', () async {
    await store.saveProduct(item(opening: 3));
    final target = StockStore(persist: (_) async {});
    await target.saveProduct(item(opening: 20));
    await target.importBundle(store.bundle(), addProducts: true);
    expect(target.stock(target.products.single), 20);
  });
  test(
    'invalid file, negative quantities and duplicate codes are rejected',
    () async {
      expect(() => StockStore.decodeBundle('{}'), throwsFormatException);
      await store.saveProduct(item());
      final data = store.bundle();
      data['products'][0]['onHand'] = -1;
      expect(
        () => StockStore.decodeBundle(jsonEncode(data)),
        throwsFormatException,
      );
    },
  );
  test('CSV escapes formulas, quotes and embedded line breaks', () async {
    await store.saveProduct(item(name: '=HYPERLINK("test")\nCoffee'));
    final csv = store.csv();
    expect(csv, contains('"\'=HYPERLINK(""test"")\nCoffee"'));
  });
  test('money parses in integer cents and rejects nonfinite input', () {
    expect(parseMoney('12.5'), 1250);
    expect(parseMoney('0.01'), 1);
    expect(() => parseMoney('NaN'), throwsFormatException);
    expect(() => parseMoney('-1'), throwsFormatException);
    expect(() => parseMoney('1.999'), throwsFormatException);
  });
  test(
    'product photo exports into bundle, imports into new store, and backfills existing item',
    () async {
      final photo = base64Encode([255, 216, 255, 224, 0, 16, 74, 70, 73, 70]);
      final pWithPhoto = Product(
        id: 'p-photo',
        name: 'Artisan Mug',
        category: 'Home',
        barcode: '9988776655443',
        price: 1500,
        cost: 700,
        opening: 5,
        threshold: 2,
        unit: 'pcs',
        photo: photo,
      );
      await store.saveProduct(pWithPhoto);
      final bundle = store.bundle();

      // Verify photo is present in JSON bundle
      expect(bundle['products'].first['photo'], photo);

      // 1. Importing into a new store adds product with photo
      final targetStore = StockStore(persist: (_) async {});
      await targetStore.importBundle(bundle, addProducts: true);
      expect(targetStore.products.single.photo, photo);

      // 2. Importing into a store that had the item without photo backfills the photo
      final storeWithoutPhoto = StockStore(persist: (_) async {});
      final pNoPhoto = Product(
        id: 'p-photo',
        name: 'Artisan Mug',
        category: 'Home',
        barcode: '9988776655443',
        price: 1500,
        cost: 700,
        opening: 8,
        threshold: 2,
        unit: 'pcs',
        photo: null,
      );
      await storeWithoutPhoto.saveProduct(pNoPhoto);
      expect(storeWithoutPhoto.products.single.photo, isNull);

      await storeWithoutPhoto.importBundle(bundle, addProducts: true);
      // Stock remains 8 (existing stock not overwritten), but photo is backfilled!
      expect(storeWithoutPhoto.stock(storeWithoutPhoto.products.single), 8);
      expect(storeWithoutPhoto.products.single.photo, photo);
    },
  );

  test(
    'ProductImage.decodeBytes handles clean base64, data URIs, and corrupt strings',
    () {
      final clean = base64Encode([1, 2, 3, 4]);
      expect(ProductImage.decodeBytes(clean), [1, 2, 3, 4]);

      // Data URI prefix
      expect(ProductImage.decodeBytes('data:image/jpeg;base64,$clean'), [
        1,
        2,
        3,
        4,
      ]);

      // Whitespace / newlines
      expect(ProductImage.decodeBytes('\n  $clean  \r\n'), [1, 2, 3, 4]);

      // Corrupt / empty
      expect(ProductImage.decodeBytes(''), isNull);
      expect(ProductImage.decodeBytes(null), isNull);
      expect(ProductImage.decodeBytes('not_valid_base64!!!'), isNull);
    },
  );

  test(
    'deleteReceived removes saved record from received list and allows re-import',
    () async {
      await store.saveProduct(item());
      final bundle = store.bundle();
      final target = StockStore(persist: (_) async {});

      // Save as record without adding products
      await target.importBundle(bundle, addProducts: false);
      expect(target.received.length, 1);
      expect(target.products, isEmpty);

      // Cannot re-import while already received
      await expectLater(target.importBundle(bundle), throwsStateError);

      // Delete the received record
      await target.deleteReceived(bundle['id']);
      expect(target.received, isEmpty);

      // Can now cleanly import again if desired
      await target.importBundle(bundle, addProducts: true);
      expect(target.received.length, 1);
      expect(target.products.length, 1);
    },
  );

  test(
    'bundle respects includePhotos flag to reduce stream payload size',
    () async {
      final photo = base64Encode([255, 216, 255, 224, 0, 16, 74, 70, 73, 70]);
      await store.saveProduct(
        Product(
          id: 'p-with-pic',
          name: 'Item With Pic',
          category: 'Test',
          barcode: '99880011',
          price: 1000,
          cost: 500,
          opening: 10,
          threshold: 1,
          unit: 'pcs',
          photo: photo,
        ),
      );

      final withPhoto = store.bundle(includePhotos: true);
      expect(withPhoto['products'].first['photo'], photo);

      final withoutPhoto = store.bundle(includePhotos: false);
      expect(withoutPhoto['products'].first['photo'], isNull);
      expect(withoutPhoto['products'].first['name'], 'Item With Pic');
    },
  );

  test(
    'mergeReceived safely adds new products and backfills photos without overwriting stock',
    () async {
      final target = StockStore(persist: (_) async {});
      // Existing item in target store has 15 in stock, no photo
      final existingItem = Product(
        id: 'prod-1',
        name: 'Coffee',
        category: 'Pantry',
        barcode: '11223344',
        price: 500,
        cost: 200,
        opening: 15,
        threshold: 2,
        unit: 'pcs',
        photo: null,
      );
      await target.saveProduct(existingItem);
      expect(target.stock(existingItem), 15);

      // Incoming bundle has Coffee (with photo, and onHand: 8) plus Tea (new item, onHand: 5)
      final photo = base64Encode([1, 2, 3, 4, 5]);
      final incomingBundle = {
        'format': 'stockmix',
        'version': 1,
        'id': 'bundle-merge-test',
        'kind': 'Stock snapshot',
        'shop': 'Branch Two',
        'currency': target.currency,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'products': [
          {
            'id': 'prod-1',
            'name': 'Coffee',
            'category': 'Pantry',
            'barcode': '11223344',
            'price': 500,
            'cost': 200,
            'opening': 8,
            'threshold': 2,
            'unit': 'pcs',
            'photo': photo,
            'onHand': 8,
          },
          {
            'id': 'prod-2',
            'name': 'Green Tea',
            'category': 'Pantry',
            'barcode': '55667788',
            'price': 300,
            'cost': 150,
            'opening': 5,
            'threshold': 2,
            'unit': 'pcs',
            'photo': null,
            'onHand': 5,
          },
        ],
        'movements': [],
      };

      // Save as received record first
      await target.importBundle(incomingBundle, addProducts: false);
      expect(target.products.length, 1);
      expect(target.received.length, 1);

      // Perform mergeReceived
      final result = await target.mergeReceived('bundle-merge-test');
      expect(result['newProducts'], 1); // Green Tea
      expect(result['backfilledPhotos'], 1); // Coffee photo
      expect(result['skippedProducts'], 0);

      // Check Coffee: stock is still 15 (preserved!), but photo is backfilled!
      final coffee = target.product('prod-1');
      expect(target.stock(coffee), 15);
      expect(coffee.photo, photo);

      // Check Green Tea: added with initial stock 5
      final tea = target.product('prod-2');
      expect(target.stock(tea), 5);
    },
  );

  test(
    'deleteProduct rejects deleting items with on-hand stock and deletes zero-stock items cleanly',
    () async {
      final p = item(opening: 5);
      await store.saveProduct(p);
      expect(store.stock(p), 5);

      // Cannot delete while stock > 0
      await expectLater(store.deleteProduct(p.id), throwsStateError);
      expect(store.products.length, 1);

      // Adjust stock down to 0
      await store.adjust(p, -5, 'Loss/Discontinued', 'Discontinued item');
      expect(store.stock(p), 0);

      // Can now cleanly delete
      await store.deleteProduct(p.id);
      expect(store.products, isEmpty);
      expect(store.movements, isEmpty);
    },
  );

  test(
    'first-time setup completes and currency can be changed even after movements',
    () async {
      expect(store.setupCompleted, isFalse);
      await store.completeSetup('Maya Grocery', 'PHP');
      expect(store.shop, 'Maya Grocery');
      expect(store.currency, 'PHP');
      expect(store.setupCompleted, isTrue);

      // Save product and movement
      final p = item();
      await store.saveProduct(p);
      expect(store.movements, isNotEmpty);

      // Changing currency is allowed anytime without exchange rate conversion
      await store.settings('Maya Grocery', 'USD');
      expect(store.currency, 'USD');
    },
  );

  test(
    'full backup and restore recovers all store data and settings',
    () async {
      await store.completeSetup('Corner Shop', 'EUR');
      final p1 = item(id: 'p1', name: 'Almond Milk', opening: 10);
      await store.saveProduct(p1);
      await store.checkout({p1.id: 2}, 'Customer sale');
      await store.holdSale({p1.id: 3}, note: 'Customer stepped out');

      final backup = store.fullBackup();
      expect(backup['format'], 'stockmix-full-backup');
      expect(backup['shop'], 'Corner Shop');
      expect(backup['currency'], 'EUR');
      expect(backup['products'], hasLength(1));
      expect(backup['movements'], hasLength(2)); // opening + sale
      expect(backup['heldSales'], hasLength(1));

      // Restore on fresh store
      final newStore = StockStore(persist: (_) async {});
      await newStore.restoreFullBackup(backup);

      expect(newStore.shop, 'Corner Shop');
      expect(newStore.currency, 'EUR');
      expect(newStore.setupCompleted, isTrue);
      expect(newStore.products, hasLength(1));
      expect(newStore.stock(newStore.product('p1')), 8);
      expect(newStore.heldSales, hasLength(1));
      expect(newStore.lastBackupAt, isNotNull);
    },
  );

  test('holdSale, resumeSale, and deleteHeldSale workflow', () async {
    final p = item();
    await store.saveProduct(p);

    // Cannot hold empty sale
    await expectLater(store.holdSale({}), throwsStateError);

    // Hold sale
    await store.holdSale({p.id: 4}, note: 'Customer fetching wallet');
    expect(store.heldSales, hasLength(1));
    final heldId = store.heldSales.first['id'] as String;

    // Resume sale returns cart and removes from held
    final resumedCart = await store.resumeSale(heldId);
    expect(resumedCart, {p.id: 4});
    expect(store.heldSales, isEmpty);

    // Hold another and delete
    await store.holdSale({p.id: 2});
    expect(store.heldSales, hasLength(1));
    await store.deleteHeldSale(store.heldSales.first['id'] as String);
    expect(store.heldSales, isEmpty);
  });

  test(
    'processReturn links to sale and creates restock and refund movements',
    () async {
      final p = item(opening: 10, price: 500);
      await store.saveProduct(p);
      final ref = await store.checkout({p.id: 3}, 'Cash');
      expect(ref, isNotEmpty);
      expect(store.stock(p), 7);

      final saleMovement = store.movements.firstWhere((m) => m.type == 'Sale');
      expect(saleMovement.reference, ref);

      // Return 2 units with restock and refund
      await store.processReturn(
        saleMovement: saleMovement,
        returnQty: 2,
        returnToStock: true,
        refundMoney: true,
        note: 'Damaged packaging but accepted',
      );

      // Stock should be 7 + 2 = 9
      expect(store.stock(p), 9);
      expect(
        store.movements.any((m) => m.type == 'Return restock' && m.delta == 2),
        isTrue,
      );
      expect(store.movements.any((m) => m.type == 'Return refund'), isTrue);
    },
  );

  test('business summary reflects refunded and restocked returns', () async {
    final p = item(opening: 10, price: 500);
    await store.saveProduct(p);
    await store.checkout({p.id: 3}, 'Cash');
    final sale = store.movements.lastWhere((m) => m.type == 'Sale');

    await store.processReturn(
      saleMovement: sale,
      returnQty: 1,
      returnToStock: true,
      refundMoney: true,
    );

    final summary = store.businessSummary(days: 7);
    expect(summary['totalRevenue'], 1000);
    expect(summary['estimatedGrossProfit'], 600);
    final top = (summary['topSellers'] as List).single;
    expect(top['quantity'], 2);
    expect(top['revenue'], 1000);
  });

  test('full return completes all available sale lines atomically', () async {
    final first = item(id: 'first', opening: 4, price: 500);
    final second = item(id: 'second', code: 'second', opening: 3, price: 300);
    await store.saveProduct(first);
    await store.saveProduct(second);
    await store.checkout({first.id: 2, second.id: 2}, 'Cash');
    final saleLines = store.movements.where((m) => m.type == 'Sale').toList();

    expect(
      await store.processFullReturn(
        saleMovements: saleLines,
        returnToStock: true,
        refundMoney: true,
      ),
      2,
    );
    expect(store.stock(first), 4);
    expect(store.stock(second), 3);
    expect(store.revenue(DateTime.now()), 0);
    final summary = store.businessSummary(days: 7);
    expect(summary['totalRevenue'], 0);
    expect(summary['estimatedGrossProfit'], 0);
    expect(summary['topSellers'], isEmpty);
    await expectLater(
      store.processFullReturn(
        saleMovements: saleLines,
        returnToStock: true,
        refundMoney: true,
      ),
      throwsStateError,
    );
  });

  test(
    'batchReceive stocks multiple items from supplier in one step',
    () async {
      final p1 = item(id: 'p1', name: 'Item 1', code: 'CODE111', opening: 2);
      final p2 = item(id: 'p2', name: 'Item 2', code: 'CODE222', opening: 5);
      await store.saveProduct(p1);
      await store.saveProduct(p2);

      final total = await store.batchReceive({
        p1.id: 10,
        p2.id: 20,
      }, supplier: 'Ace Wholesale');

      expect(total, 30);
      expect(store.stock(p1), 12);
      expect(store.stock(p2), 25);
      expect(
        store.movements.where((m) => m.note.contains('Ace Wholesale')),
        hasLength(2),
      );
    },
  );

  test(
    'businessSummary calculates revenue, gross profit, missing costs, top sellers, and slow movers',
    () async {
      // p1 has cost 200, price 500
      final p1 = item(
        id: 'p1',
        name: 'Top Seller',
        code: 'CODE100',
        opening: 50,
        price: 500,
      );
      // p2 has cost 0, price 300 (missing cost)
      final p2 = Product(
        id: 'p2',
        name: 'Item With Missing Cost',
        category: 'Pantry',
        barcode: 'P222',
        price: 300,
        cost: 0,
        opening: 20,
        threshold: 5,
      );
      // p3 has stock but will have 0 sales (slow mover)
      final p3 = item(
        id: 'p3',
        name: 'Slow Mover',
        code: 'CODE300',
        opening: 15,
      );

      await store.saveProduct(p1);
      await store.saveProduct(p2);
      await store.saveProduct(p3);

      // Sell 10 of p1 (rev: 5000, cost: 2000, profit: 3000)
      await store.checkout({p1.id: 10}, 'Sale 1');
      // Sell 5 of p2 (rev: 1500, cost: 0, missing cost item)
      await store.checkout({p2.id: 5}, 'Sale 2');

      final summary = store.businessSummary(days: 7);

      expect(summary['totalRevenue'], 6500);
      expect(summary['estimatedGrossProfit'], 4500); // 6500 - 2000
      expect(summary['itemsMissingCost'], 1);
      expect(summary['salesCount'], 2);

      final topSellers = summary['topSellers'] as List;
      expect(topSellers.first['name'], 'Top Seller');
      expect(topSellers.first['quantity'], 10);

      final slowMovers = summary['slowMovers'] as List;
      expect(slowMovers.any((m) => m['name'] == 'Slow Mover'), isTrue);
      expect(slowMovers.any((m) => m['name'] == 'Top Seller'), isFalse);
    },
  );

  test(
    'scoped count allows sales of uncounted products while locking counted items',
    () async {
      final dairy = Product(
        id: 'p_milk',
        name: 'Milk',
        category: 'Dairy',
        barcode: '111',
        price: 200,
        cost: 100,
        opening: 10,
        threshold: 2,
      );
      final bakery = Product(
        id: 'p_bread',
        name: 'Bread',
        category: 'Bakery',
        barcode: '222',
        price: 150,
        cost: 70,
        opening: 5,
        threshold: 1,
      );
      await store.saveProduct(dairy);
      await store.saveProduct(bakery);

      // Start count scoped to Dairy
      await store.startCount(category: 'Dairy');
      expect(store.count?['scope'], 'Dairy');
      expect((store.count?['baseline'] as Map).containsKey('p_milk'), isTrue);
      expect((store.count?['baseline'] as Map).containsKey('p_bread'), isFalse);

      // Selling Dairy is blocked
      await expectLater(
        store.checkout({'p_milk': 1}, 'Sale'),
        throwsStateError,
      );

      // Selling Bakery (uncounted item) is permitted!
      final ref = await store.checkout({'p_bread': 2}, 'Bread sale');
      expect(ref, isNotEmpty);
      expect(store.stock(bakery), 3);

      // Finish count for milk
      await store.setCount('p_milk', 8);
      await store.postCount();
      expect(store.stock(dairy), 8);
      expect(store.count, isNull);
      expect(store.received.last['kind'], 'Posted count (Dairy)');
    },
  );

  test(
    'previewMerge computes before and after stock balance impact before merging',
    () async {
      final coffee = item(id: 'p_coffee', name: 'Coffee', opening: 20);
      await store.saveProduct(coffee);

      // Create a received Day record with sales of Coffee (-3) and a new product
      final dayRecord = {
        'format': 'stockmix',
        'version': 1,
        'id': 'rec_day_1',
        'kind': 'Day record',
        'shop': 'Branch B',
        'currency': store.currency,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'products': [
          {
            'id': 'p_coffee',
            'name': 'Coffee',
            'category': 'Pantry',
            'barcode': '1234567890123',
            'price': 450,
            'cost': 200,
            'opening': 20,
            'onHand': 17,
            'threshold': 3,
            'unit': 'pcs',
          },
          {
            'id': 'p_tea',
            'name': 'Green Tea',
            'category': 'Pantry',
            'barcode': '999999',
            'price': 300,
            'cost': 150,
            'opening': 15,
            'onHand': 15,
            'threshold': 2,
            'unit': 'pcs',
          },
        ],
        'movements': [
          {
            'id': 'm_coffee_sale',
            'productId': 'p_coffee',
            'name': 'Coffee',
            'type': 'Sale',
            'delta': -3,
            'price': 450,
            'cost': 200,
            'note': 'Customer sale',
            'reference': 'ref_1',
            'at': DateTime.now().toUtc().toIso8601String(),
          },
        ],
      };

      await store.importBundle(dayRecord);

      // Preview merge
      final preview = store.previewMerge('rec_day_1');
      final changes = preview['stockChanges'] as List<Map<String, dynamic>>;

      // Coffee should show: 20 -> 17 (-3)
      final coffeePreview = changes.firstWhere(
        (c) => c['productId'] == 'p_coffee',
      );
      expect(coffeePreview['currentStock'], 20);
      expect(coffeePreview['newStock'], 17);
      expect(coffeePreview['delta'], -3);
      expect(coffeePreview['isNew'], isFalse);

      // Tea should show: 0 -> 15 (+15, New)
      final teaPreview = changes.firstWhere((c) => c['productId'] == 'p_tea');
      expect(teaPreview['currentStock'], 0);
      expect(teaPreview['newStock'], 15);
      expect(teaPreview['delta'], 15);
      expect(teaPreview['isNew'], isTrue);

      expect(preview['newProductsCount'], 1);
      expect(preview['newMovementsCount'], 1);

      // Apply merge and verify resulting stock
      await store.mergeReceived('rec_day_1');
      expect(store.stock(coffee), 17);
      final tea = store.product('p_tea');
      expect(store.stock(tea), 15);
    },
  );
}
