import 'package:flutter/material.dart';
import 'database.dart';
import 'design.dart';
import 'stock_store.dart';
import 'pages.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final StockStore store;
    if (const bool.fromEnvironment('DEMO')) {
      store = StockStore(persist: (_) async {});
      await store.loadDemo();
      await store.settings('The Corner Store', 'USD');
    } else {
      store = await StockStore.open(await openStockDatabase());
    }
    runApp(StockmixApp(store: store));
  } catch (_) {
    runApp(
      MaterialApp(
        theme: stockTheme(),
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.storage_outlined, size: 48),
                  const SizedBox(height: 20),
                  const Text(
                    'Your stock book could not be opened.',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Check that storage is available, then reopen Stockmix. Existing data has not been reset.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: main, child: const Text('Try again')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class StockmixApp extends StatelessWidget {
  final StockStore store;
  const StockmixApp({super.key, required this.store});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Stockmix',
    theme: stockTheme(),
    home: StockShell(store: store),
  );
}
