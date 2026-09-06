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
  test('product photo exports into bundle, imports into new store, and backfills existing item', () async {
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
  });

  test('ProductImage.decodeBytes handles clean base64, data URIs, and corrupt strings', () {
    final clean = base64Encode([1, 2, 3, 4]);
    expect(ProductImage.decodeBytes(clean), [1, 2, 3, 4]);

    // Data URI prefix
    expect(ProductImage.decodeBytes('data:image/jpeg;base64,$clean'), [1, 2, 3, 4]);

    // Whitespace / newlines
    expect(ProductImage.decodeBytes('\n  $clean  \r\n'), [1, 2, 3, 4]);

    // Corrupt / empty
    expect(ProductImage.decodeBytes(''), isNull);
    expect(ProductImage.decodeBytes(null), isNull);
    expect(ProductImage.decodeBytes('not_valid_base64!!!'), isNull);
  });

  test('deleteReceived removes saved record from received list and allows re-import', () async {
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
  });

  test('bundle respects includePhotos flag to reduce stream payload size', () async {
    final photo = base64Encode([255, 216, 255, 224, 0, 16, 74, 70, 73, 70]);
    await store.saveProduct(Product(
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
    ));

    final withPhoto = store.bundle(includePhotos: true);
    expect(withPhoto['products'].first['photo'], photo);

    final withoutPhoto = store.bundle(includePhotos: false);
    expect(withoutPhoto['products'].first['photo'], isNull);
    expect(withoutPhoto['products'].first['name'], 'Item With Pic');
  });

  test('mergeReceived safely adds new products and backfills photos without overwriting stock', () async {
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
  });

  test('deleteProduct rejects deleting items with on-hand stock and deletes zero-stock items cleanly', () async {
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
  });
}
