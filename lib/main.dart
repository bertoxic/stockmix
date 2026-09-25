import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:stockmix/core/ads/ad_service.dart';
import 'package:stockmix/core/database/database.dart';
import 'package:stockmix/core/theme/design.dart';
import 'package:stockmix/features/app/pages.dart';
import 'package:stockmix/features/onboarding/onboarding_page.dart';
import 'package:stockmix/features/stock/stock_store.dart';
import 'package:stockmix/l10n/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AdService.initialize();
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
  final bool? initialShowOnboarding;
  const StockmixApp({
    super.key,
    required this.store,
    this.initialShowOnboarding,
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Stockmix',
      theme: stockTheme(),
      darkTheme: stockDarkTheme(),
      themeMode: switch (store.themeMode) {
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => ThemeMode.light,
      },
      locale: store.locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: (initialShowOnboarding ?? !store.hasCompletedOnboarding)
          ? OnboardingPage(store: store)
          : StockShell(store: store),
    ),
  );
}
