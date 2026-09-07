import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockmix/design.dart';
import 'package:stockmix/forms.dart';
import 'package:stockmix/main.dart';
import 'package:stockmix/operations.dart';
import 'package:stockmix/pages.dart';
import 'package:stockmix/scanner_page.dart';
import 'package:stockmix/stock_store.dart';

void main() {
  testWidgets(
    'phone navigates inventory, item details, and sales without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final originalHandler = FlutterError.onError;
      FlutterError.onError = (details) {
        debugPrint(details.toString());
        originalHandler?.call(details);
      };
      final store = StockStore(persist: (_) async {});
      await store.loadDemo();
      await tester.pumpWidget(StockmixApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('Today’s sales'.toUpperCase()), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Stock'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Ceramic');
      await tester.pumpAndSettle();
      expect(find.text('Ceramic everyday mug'), findsOneWidget);
      await tester.tap(find.text('Ceramic everyday mug'));
      await tester.pumpAndSettle();
      expect(find.text('Record a sale'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Record a sale'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Record a sale'));
      await tester.pumpAndSettle();
      expect(find.text('New sale'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('wide overview and all main destinations render', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final originalHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      debugPrint(details.toString());
      originalHandler?.call(details);
    };
    final store = StockStore(persist: (_) async {});
    await store.loadDemo();
    await tester.pumpWidget(StockmixApp(store: store));
    await tester.pumpAndSettle();
    for (final label in ['Inventory', 'Day records', 'More', 'Overview']) {
      await tester.tap(find.text(label).first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('empty store has a useful first-item action', (tester) async {
    await tester.pumpWidget(
      StockmixApp(store: StockStore(persist: (_) async {})),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Add your first item'), 250);
    await tester.ensureVisible(find.text('Add your first item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add your first item'));
    await tester.pumpAndSettle();
    expect(find.text('Item name'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'continuous multi-item scan keeps items on screen, updates running total, and supports quantity controls',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = StockStore(persist: (_) async {});
      await store.saveProduct(
        const Product(
          id: 'p1',
          name: 'Oat Milk 1L',
          category: 'Pantry',
          barcode: '1111111111111',
          price: 350,
          cost: 200,
          opening: 10,
          threshold: 2,
        ),
      );
      await store.saveProduct(
        const Product(
          id: 'p2',
          name: 'Espresso Beans',
          category: 'Pantry',
          barcode: '2222222222222',
          price: 1200,
          cost: 700,
          opening: 5,
          threshold: 1,
        ),
      );

      Map<String, int>? returnedCart;

      await tester.pumpWidget(
        MaterialApp(
          theme: stockTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    returnedCart = await Navigator.push<Map<String, int>>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ScannerPage(
                          store: store,
                          mode: ScannerMode.multiItem,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Scanner'),
                ),
              ),
            ),
          ),
        ),
      );

      // Open continuous scanner
      await tester.tap(find.text('Open Scanner'));
      await tester.pumpAndSettle();

      expect(find.text('Scan into sale'), findsOneWidget);
      expect(find.text('Ready to scan'), findsOneWidget);
      expect(find.text('\$0.00'), findsOneWidget);

      // Scan first item via the code field
      final inputField = find.widgetWithText(TextField, 'Or type barcode…');
      await tester.enterText(inputField, '1111111111111');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      // Verify item appears in the list under the scanner
      expect(find.text('Oat Milk 1L'), findsOneWidget);
      expect(find.text('Ready to scan'), findsNothing);
      expect(find.text('\$3.50'), findsWidgets);
      expect(find.text('1 unit'), findsOneWidget);

      // Scan second item
      await tester.enterText(inputField, '2222222222222');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      // Both items are present under the scanner
      expect(find.text('Oat Milk 1L'), findsOneWidget);
      expect(find.text('Espresso Beans'), findsOneWidget);
      // Total is $3.50 + $12.00 = $15.50
      expect(find.text('\$15.50'), findsOneWidget);
      expect(find.text('2 units'), findsWidgets);

      // Increment Oat Milk quantity using the '+' icon
      final addButtons = find.byIcon(Icons.add_circle_outline);
      await tester.tap(addButtons.first);
      await tester.pumpAndSettle();

      // Total is now 2 * $3.50 + $12.00 = $19.00
      expect(find.text('\$19.00'), findsOneWidget);
      expect(find.text('3 units'), findsWidgets);

      // Scan an unknown barcode
      await tester.enterText(inputField, '9999999999999');
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      expect(find.text('Unregistered barcode'), findsOneWidget);
      expect(find.text('9999999999999'), findsOneWidget);

      // Dismiss unknown barcode alert
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Unregistered barcode'), findsNothing);

      // Tap 'Review' to finish and return cart
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();

      expect(returnedCart, isNotNull);
      expect(returnedCart!['p1'], 2);
      expect(returnedCart!['p2'], 1);
    },
  );

  testWidgets('single barcode mode returns code string immediately', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    String? returnedCode;

    await tester.pumpWidget(
      MaterialApp(
        theme: stockTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  returnedCode = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(builder: (_) => const ScannerPage()),
                  );
                },
                child: const Text('Open Single Scanner'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Single Scanner'));
    await tester.pumpAndSettle();

    expect(find.text('Scan an item'), findsOneWidget);

    final codeField = find.widgetWithText(TextField, 'Barcode / item code');
    await tester.scrollUntilVisible(
      codeField,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(codeField);
    await tester.enterText(codeField, '1111111111111');

    final findButton = find.text('Find item');
    await tester.ensureVisible(findButton);
    await tester.tap(findButton);
    await tester.pumpAndSettle();

    expect(returnedCode, '1111111111111');
  });

  testWidgets('product form handles photo text extraction and suggestion chips', (
    tester,
  ) async {
    final store = StockStore(persist: (_) async {});
    await tester.pumpWidget(
      MaterialApp(
        theme: stockTheme(),
        home: ProductForm(store: store),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial empty name
    expect(find.text('Add an item'), findsOneWidget);
    final nameField = find.widgetWithText(TextFormField, 'Item name');
    expect(nameField, findsOneWidget);

    // Find PhotoInput and simulate onTextExtracted callback
    final photoInput = tester.widget<PhotoInput>(find.byType(PhotoInput));
    expect(photoInput.onTextExtracted, isNotNull);

    // Simulate OCR detecting lines: 'Oat Milk Organic', '1 Liter', 'Barista Edition'
    photoInput.onTextExtracted!([
      'Oat Milk Organic',
      '1 Liter',
      'Barista Edition',
    ]);
    await tester.pumpAndSettle();

    // The name field should auto-fill with the first title
    expect(find.text('Oat Milk Organic'), findsOneWidget);
    expect(find.text('Detected from photo (tap to use):'), findsOneWidget);
    expect(find.text('1 Liter'), findsOneWidget);
    expect(find.text('Barista Edition'), findsOneWidget);

    // Tap on the '1 Liter' suggestion chip to append
    await tester.tap(find.widgetWithText(ActionChip, '1 Liter'));
    await tester.pumpAndSettle();
    expect(find.text('Oat Milk Organic 1 Liter'), findsOneWidget);

    // Tap Dismiss to clear chips
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text('Detected from photo (tap to use):'), findsNothing);
  });

  testWidgets(
    'scanning item from New sale and popping keeps item in Your sale',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      final store = StockStore(persist: (_) async {});
      await store.loadDemo();

      await tester.pumpWidget(
        MaterialApp(
          theme: stockTheme(),
          home: SalePage(store: store),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Your sale'), findsOneWidget);
      expect(find.text('0 items'), findsOneWidget);

      // Open scanner via the scan button in the app bar
      await tester.tap(find.byTooltip('Scan item into sale'));
      await tester.pumpAndSettle();

      expect(find.text('Scan into sale'), findsOneWidget);

      final p = store.products.first;

      // Scan an item using the manual input
      final inputField = find.widgetWithText(TextField, 'Or type barcode…');
      await tester.enterText(inputField, p.barcode);
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      // Verify item appears in the live scanned list
      expect(find.text(p.name), findsOneWidget);

      // Click the Back button in the AppBar (or swipe back)
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      // Verify we are back on the New sale page
      expect(find.text('New sale'), findsOneWidget);

      // Crucial: The scanned item must still be present in "Your sale" list!
      expect(find.text(p.name), findsOneWidget);
      expect(find.text('0 items'), findsNothing);
    },
  );

  testWidgets(
    'share receipt navigates to invoice page with matching UI and details',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      final store = StockStore(persist: (_) async {});
      await store.loadDemo();
      final p = store.products.first;

      await tester.pumpWidget(
        MaterialApp(
          theme: stockTheme(),
          home: SalePage(store: store, initialProduct: p),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Checkout
      await tester.scrollUntilVisible(
        find.text('Record cash sale'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Record cash sale'));
      await tester.pumpAndSettle();

      // Confirm dialog appears
      expect(find.text('Record cash received?'), findsOneWidget);
      await tester.tap(find.text('Cash received'));
      await tester.pumpAndSettle();

      // "Sale recorded" dialog appears with "Share receipt"
      expect(find.text('Sale recorded.'), findsOneWidget);
      expect(find.text('Share receipt'), findsOneWidget);

      // Tap "Share receipt" - should navigate to Invoice & Receipt page!
      await tester.tap(find.text('Share receipt'));
      await tester.pumpAndSettle();

      // Verify we are on the Invoice & Receipt page
      expect(find.text('Invoice & Receipt'), findsOneWidget);
      expect(find.text('Sales Receipt & Proof of Purchase'), findsOneWidget);
      expect(find.text(p.name), findsOneWidget);
      expect(find.text('PAID · CASH'), findsOneWidget);
      expect(find.text('Download receipt'), findsOneWidget);
      expect(find.text('Copy text'), findsNothing);
      expect(find.byIcon(Icons.download_rounded), findsAtLeastNWidgets(1));
      expect(find.byType(RepaintBoundary), findsWidgets);
    },
  );

  testWidgets(
    'tapping a sale movement and processing return restocks goods and updates UI',
    (tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);

      final store = StockStore(persist: (_) async {});
      await store.loadDemo();
      final p = store.products.first;
      final openingStock = store.stock(p);

      // Make a sale
      await store.checkout({p.id: 2}, 'Cash');
      expect(store.stock(p), openingStock - 2);

      final saleMovement = store.movements.lastWhere((m) => m.type == 'Sale');

      await tester.pumpWidget(
        MaterialApp(
          theme: stockTheme(),
          home: Scaffold(
            body: MovementTile(store: store, movement: saleMovement),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on the MovementTile to open details bottom sheet
      await tester.tap(find.byType(MovementTile));
      await tester.pumpAndSettle();

      // Bottom sheet should display "Process return"
      expect(find.text('Process return'), findsOneWidget);
      await tester.tap(find.text('Process return'));
      await tester.pumpAndSettle();

      // Return dialog should be visible with "Confirm return"
      expect(find.text('Confirm return'), findsOneWidget);
      await tester.tap(find.text('Confirm return'));
      await tester.pumpAndSettle();

      // Verify stock was restored by 1 unit
      expect(store.stock(p), openingStock - 1);

      // Verify return restock movement was recorded
      expect(
        store.movements.any((m) => m.type == 'Return restock' && m.delta == 1),
        isTrue,
      );

      // Verify return refund movement was recorded
      expect(store.movements.any((m) => m.type == 'Return refund'), isTrue);
    },
  );

  testWidgets(
    'records groups multiple items sold in the same checkout into a single customer sale tile and supports see more',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = StockStore(persist: (_) async {});
      await store.loadDemo();

      // Perform a multi-item checkout (e.g. 3 products)
      final p1 = store.products[0];
      final p2 = store.products[1];
      final p3 = store.products[2];
      final revenueBeforePurchase = store.revenue(DateTime.now());
      await store.checkout({
        p1.id: 1,
        p2.id: 2,
        p3.id: 1,
      }, 'Multi-item purchase');
      final p1StockAfterPurchase = store.stock(p1);

      await tester.pumpWidget(
        MaterialApp(
          theme: stockTheme(),
          home: Scaffold(
            body: DailySaleGroupTile(
              saleGroup: store.movements
                  .where((m) => m.type == 'Sale' && m.reference.isNotEmpty)
                  .toList()
                  .reversed
                  .take(3)
                  .toList(),
              store: store,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(DailySaleGroupTile), findsOneWidget);

      // Tap on DailySaleGroupTile to open transaction bottom sheet
      await tester.tap(find.byType(DailySaleGroupTile).first);
      await tester.pumpAndSettle();

      // Bottom sheet should display customer purchase header and items
      expect(find.text('Customer Purchase'), findsOneWidget);
      expect(find.text('Sale transaction'), findsOneWidget);
      expect(find.text('Share receipt'), findsOneWidget);
      expect(find.text('Process return for all items'), findsOneWidget);
      expect(find.byTooltip('Process return for ${p1.name}'), findsOneWidget);

      // Return one item from the purchase details.
      await tester.tap(find.byTooltip('Process return for ${p1.name}'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm return'), findsOneWidget);
      await tester.tap(find.text('Confirm return'));
      await tester.pumpAndSettle();
      expect(
        store.stock(p1),
        p1StockAfterPurchase + 1,
      );

      // Reopen and return every remaining line in the same purchase.
      await tester.tap(find.byType(DailySaleGroupTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Process return for all items'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm full return'), findsOneWidget);
      await tester.tap(find.text('Confirm full return'));
      await tester.pumpAndSettle();
      expect(store.revenue(DateTime.now()), revenueBeforePurchase);
    },
  );

  testWidgets(
    'More tab has Store settings which navigates to StoreSettingsPage and backup at bottom',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = StockStore(persist: (_) async {});
      await store.loadDemo();

      await tester.pumpWidget(StockmixApp(store: store));
      await tester.pumpAndSettle();

      // Tap More tab
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();

      // Verify Stock count and Shopping & reorder list are present
      expect(find.text('Stock count'), findsOneWidget);
      expect(find.text('Shopping & reorder list'), findsOneWidget);
      expect(find.text('Full backup & restore'), findsOneWidget);
      // Standalone "Import a file" should no longer be present
      expect(find.text('Import a file'), findsNothing);

      // Tap Store settings
      await tester.tap(find.text('Store settings'));
      await tester.pumpAndSettle();

      // Should be in StoreSettingsPage
      expect(find.text('Store & App Settings'), findsOneWidget);
      expect(find.text('Scan audio tone'), findsOneWidget);
      expect(find.text('Haptic vibration'), findsOneWidget);
      expect(find.text('Light Theme (Default)'), findsOneWidget);
    },
  );
}
