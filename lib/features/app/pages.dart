import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:stockmix/core/theme/design.dart';
import 'package:stockmix/core/widgets/calculator.dart';
import 'package:stockmix/core/widgets/native_ad_card.dart';
import 'package:stockmix/features/inventory/forms.dart';
import 'package:stockmix/features/inventory/reorder_page.dart';
import 'package:stockmix/features/onboarding/onboarding_page.dart';
import 'package:stockmix/features/sales/invoice_page.dart';
import 'package:stockmix/features/sales/operations.dart';
import 'package:stockmix/features/scanner/scanner_page.dart';
import 'package:stockmix/features/settings/backup_page.dart';
import 'package:stockmix/features/settings/privacy_policy_page.dart';
import 'package:stockmix/features/settings/settings_page.dart';
import 'package:stockmix/features/sharing/presentation/share_page.dart';
import 'package:stockmix/features/sharing/qr_stream/qr_stream_receiver_page.dart';
import 'package:stockmix/features/sharing/qr_stream/qr_stream_sender_page.dart';
import 'package:stockmix/features/stock/slow_moving_page.dart';
import 'package:stockmix/features/stock/stock_store.dart';
import 'package:stockmix/l10n/app_localizations.dart';

String money(StockStore store, int cents) =>
    NumberFormat.simpleCurrency(name: store.currency).format(cents / 100);

class StockShell extends StatefulWidget {
  final StockStore store;
  const StockShell({super.key, required this.store});
  @override
  State<StockShell> createState() => _StockShellState();
}

class _ReceiptSearchDialog extends StatefulWidget {
  const _ReceiptSearchDialog();

  @override
  State<_ReceiptSearchDialog> createState() => _ReceiptSearchDialogState();
}

class _ReceiptSearchDialogState extends State<_ReceiptSearchDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(context.l10n.findReceiptRecord),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: InputDecoration(
        labelText: context.l10n.receiptReference,
        hintText: 'e.g. REF-1234 or paste QR payload',
        prefixIcon: const Icon(Icons.receipt_long_outlined),
      ),
      onSubmitted: (v) => Navigator.pop(context, v.trim()),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.cancel),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _controller.text.trim()),
        child: Text(context.l10n.findRecord),
      ),
    ],
  );
}

class _StockShellState extends State<StockShell> {
  int tab = 0;
  String search = '', category = 'All items';
  DateTime day = DateTime.now();
  int recordsMode = 0;
  // Sales and customer refunds are the primary day-to-day view.
  int dailyActivityFilter = 1;
  int insightsDays = 7;
  bool showAllRecords = false;
  bool showAllInventory = false;
  int inventoryDisplayLimit = 20;
  int slowMoversDisplayLimit = 15;
  int topSellersDisplayLimit = 10;
  bool hideTodaySales = false;
  StockStore get store => widget.store;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _showCategoryPicker(List<String> categories) => showDialog<void>(
    context: context,
    builder: (dialogContext) => Dialog(
      child: SizedBox(
        height: MediaQuery.sizeOf(dialogContext).height * .5,
        width: 360,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.categories,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: context.l10n.close,
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Divider(color: context.stockLine, height: 1),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  final selectedCategory = categories[index];
                  final selected = category == selectedCategory;
                  return ListTile(
                    title: Text(selectedCategory == 'All items' ? context.l10n.allItems : selectedCategory),
                    selected: selected,
                    trailing: selected ? const Icon(Icons.check) : null,
                    onTap: () {
                      setState(() => category = selectedCategory);
                      Navigator.pop(dialogContext);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _showFirstTimeSetup() async {
    final name = TextEditingController(
      text: store.shop == 'My store' ? '' : store.shop,
    );
    var currency = store.currency;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: avocado.withAlpha(60),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.storefront_outlined,
                  color: context.stockInk,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                context.l10n.welcomeTitle,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.welcomeSubtitle,
                  style: TextStyle(
                    color: context.stockMuted,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: name,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: context.l10n.storeNameLabel,
                    hintText: context.l10n.storeNameHint,
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: currency,
                  decoration: InputDecoration(
                    labelText: context.l10n.storeCurrencyLabel,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'USD',
                      child: Text(
                        'USD (\$) - US Dollar',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'EUR',
                      child: Text(
                        'EUR (€) - Euro',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'GBP',
                      child: Text(
                        'GBP (£) - British Pound',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'PHP',
                      child: Text(
                        'PHP (₱) - Philippine Peso',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'INR',
                      child: Text(
                        'INR (₹) - Indian Rupee',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'NGN',
                      child: Text(
                        'NGN (₦) - Nigerian Naira',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'KES',
                      child: Text(
                        'KES (KSh) - Kenyan Shilling',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'GHS',
                      child: Text(
                        'GHS (GH₵) - Ghanaian Cedi',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'ZAR',
                      child: Text(
                        'ZAR (R) - South African Rand',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'CAD',
                      child: Text(
                        'CAD (\$) - Canadian Dollar',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'AUD',
                      child: Text(
                        'AUD (\$) - Australian Dollar',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: (v) => update(() => currency = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.later),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.save),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      await store.completeSetup(name.text, currency);
    }
  }

  void open(Widget page) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));

  Future<void> _showShareSaleOptions() async {
    var selectedSaleDay = DateTime.now();
    final direction = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => Row(
                    children: [
                      Expanded(
                        child: Text(
                          dayKey(selectedSaleDay) == dayKey(DateTime.now())
                              ? 'Share today’s sales'
                              : 'Share ${DateFormat('d MMM').format(selectedSaleDay)} sales',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: constraints.maxWidth * .4,
                        child: OutlinedButton(
                          onPressed: () async {
                            final day = await showDatePicker(
                              context: sheetContext,
                              initialDate: selectedSaleDay,
                              firstDate: DateTime(2020),
                              lastDate: DateTime.now(),
                            );
                            if (day != null) {
                              setSheetState(() => selectedSaleDay = day);
                            }
                          },
                          child: Text(
                            dayKey(selectedSaleDay) == dayKey(DateTime.now())
                                ? 'Today'
                                : DateFormat('d MMM').format(selectedSaleDay),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Send that day’s sale record or receive one from another Stockmix user.',
                  style: TextStyle(color: sheetContext.stockMuted),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, 'send'),
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: Text(sheetContext.l10n.sendSaleQr),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(sheetContext, 'receive'),
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: Text(sheetContext.l10n.receiveSaleQr),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || direction == null) return;
    if (direction == 'send') {
      open(
        QrStreamSenderPage(
          store: store,
          bundle: store.bundle(day: selectedSaleDay),
        ),
      );
    } else if (direction == 'receive') {
      open(QrStreamReceiverPage(store: store));
    }
  }

  Future<void> scan() async {
    final resultCart = await Navigator.push<Map<String, int>>(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerPage(store: store, mode: ScannerMode.multiItem),
      ),
    );
    if (resultCart != null && resultCart.isNotEmpty && mounted) {
      open(SalePage(store: store, initialCart: resultCart));
    }
  }

  Future<void> scanToFind() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (code == null || !mounted) return;
    if (code.toUpperCase().startsWith('SMX:REC:')) {
      await scanReceipt(initialQuery: code);
      return;
    }
    setState(() => search = code);
  }

  Future<void> scanReceipt({String? initialQuery}) async {
    String? code = initialQuery;
    code ??= await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerPage(title: context.l10n.scanReceiptQr),
      ),
    );
    if (code == null || !mounted) return;

    final movements = store.findSaleByReference(code);
    if (movements.isEmpty) {
      final cleanRef = normalizeReceiptReference(code);
      showMessage(
        context,
        context.l10n.noSaleFoundForRef(cleanRef),
      );
      return;
    }

    final first = movements.first;
    final saleDate = DateTime.tryParse(first.at)?.toLocal();
    if (saleDate != null) {
      setState(() {
        tab = 2; // Switch to Records tab
        recordsMode = 0; // Daily activity
        day = DateTime(saleDate.year, saleDate.month, saleDate.day);
      });
    }

    await showSaleTransactionDetails(context, store, movements);
  }

  Future<void> _promptReceiptSearch() async {
    final ref = await showDialog<String>(
      context: context,
      builder: (ctx) => const _ReceiptSearchDialog(),
    );
    if (ref != null && ref.isNotEmpty && mounted) {
      await scanReceipt(initialQuery: ref);
    }
  }

  void _selectTab(int value) {
    if (value == tab) return;
    setState(() {
      tab = value;
      // The inventory field is rebuilt when its tab is left. Clear the
      // matching and category-filter state too so they cannot affect stock
      // when the user returns.
      if (value != 1) {
        search = '';
        category = 'All items';
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final wide = MediaQuery.sizeOf(context).width >= 1000;
      final shell = Scaffold(
        body: Row(
          children: [
            if (wide) sidebar(),
            Expanded(
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: ListView(
                      key: ValueKey(tab),
                      padding: EdgeInsets.fromLTRB(
                        wide ? 40 : 22,
                        wide ? 32 : 20,
                        wide ? 40 : 22,
                        wide ? 30 : 100,
                      ),
                      children: [
                        header(),
                        const SizedBox(height: 30),
                        ...switch (tab) {
                          0 => home(wide),
                          1 => inventory(wide),
                          2 => records(),
                          _ => more(),
                        },
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar: wide ? null : bottomNav(),
      );
      return PopScope(
        canPop: tab == 0,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && tab != 0) {
            _selectTab(0);
          }
        },
        child: shell,
      );
    },
  );
  Widget logo() => Row(
    children: [
      Container(
        width: 37,
        height: 37,
        decoration: BoxDecoration(
          color: avocado,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.layers_outlined, color: plum, size: 23),
      ),
      const SizedBox(width: 10),
      const Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            'stockmix',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.1,
            ),
          ),
        ),
      ),
    ],
  );
  Widget sidebar() => Container(
    width: 228,
    color: context.stockPaper,
    padding: const EdgeInsets.all(24),
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          logo(),
          const SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.only(left: 47),
            child: Text(
              'A little more in order.',
              style: TextStyle(fontSize: 10, color: context.stockMuted),
            ),
          ),
          const SizedBox(height: 50),
          const Eyebrow('Your workspace'),
          const SizedBox(height: 18),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: tab == i ? context.stockLinen : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  leading: Icon(
                    [
                      Icons.grid_view_rounded,
                      Icons.inventory_2_outlined,
                      Icons.receipt_long_outlined,
                      Icons.tune_rounded,
                    ][i],
                    color: tab == i ? context.stockInk : context.stockMuted,
                    size: 21,
                  ),
                  title: Text(
                    [
                      context.l10n.sidebarOverview,
                      context.l10n.sidebarInventory,
                      context.l10n.sidebarRecords,
                      context.l10n.sidebarMore,
                    ][i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: tab == i ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                  onTap: () => _selectTab(i),
                ),
              ),
            ),
          const SizedBox(height: 22),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: avocado,
                foregroundColor: plum,
              ),
              onPressed: scan,
              icon: const Icon(Icons.qr_code_scanner, size: 20),
              label: const Text('Scan an item'),
            ),
          ),
          const Spacer(),
          Surface(
            color: linen,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.offline_pin_outlined,
                  color: context.stockMuted,
                  size: 23,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Your shop. In your pocket.',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 7),
                Text(
                  'Work offline. Share when you’re ready.',
                  style: TextStyle(
                    color: context.stockMuted,
                    fontSize: 11,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'STOCKMIX  /  01',
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 2,
              color: context.stockMuted,
            ),
          ),
        ],
      ),
    ),
  );
  Widget header() => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('Your everyday stock companion'),
            const SizedBox(height: 9),
            Row(
              children: [
                Icon(
                  Icons.storefront_outlined,
                  size: 17,
                  color: context.stockMuted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    store.shop,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      IconButton(
        tooltip: 'Calculator',
        onPressed: () => showCalculator(context),
        icon: const Icon(Icons.calculate_outlined),
      ),
      const SizedBox(width: 6),
      Tooltip(
        message: 'More tools & settings',
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () => _selectTab(3),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: plum,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Icon(Icons.person_outline, color: linen, size: 22),
          ),
        ),
      ),
    ],
  );
  Widget bottomNav() => Container(
    decoration: BoxDecoration(
      color: context.stockPaper,
      border: Border(top: BorderSide(color: context.stockLine)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        child: Row(
          children: [
            navItem(0, Icons.grid_view_rounded, context.l10n.tabHome),
            navItem(1, Icons.inventory_2_outlined, context.l10n.tabStock),
            Expanded(
              child: Semantics(
                button: true,
                label: 'Scan an item',
                child: InkWell(
                  onTap: scan,
                  borderRadius: BorderRadius.circular(19),
                  child: Container(
                    height: 55,
                    margin: const EdgeInsets.symmetric(horizontal: 5),
                    decoration: BoxDecoration(
                      color: avocado,
                      borderRadius: BorderRadius.circular(19),
                    ),
                    child: Icon(
                      Icons.qr_code_scanner,
                      size: 27,
                      color: context.isStockDark ? plum : null,
                    ),
                  ),
                ),
              ),
            ),
            navItem(2, Icons.receipt_long_outlined, context.l10n.tabRecords),
            navItem(3, Icons.tune_rounded, context.l10n.tabMore),
          ],
        ),
      ),
    ),
  );
  Widget navItem(int value, IconData icon, String label) => Expanded(
    child: InkWell(
      onTap: () => _selectTab(value),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 23,
              color: tab == value ? context.stockInk : cement,
            ),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: tab == value ? FontWeight.w800 : FontWeight.w500,
                color: tab == value ? context.stockInk : context.stockMuted,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget section(String title, {String? action, VoidCallback? onTap}) =>
      Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 15),
        child: Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            if (action != null)
              TextButton(
                onPressed: onTap,
                child: Text(action, style: const TextStyle(fontSize: 12)),
              ),
          ],
        ),
      );
  List<Widget> home(bool wide) {
    final today = DateTime.now();
    final sales = store.onDay(today).where((m) => m.type == 'Sale').toList();
    final transactions = sales.map((m) => m.reference).toSet().length;
    final hero = Surface(
      color: plum,
      padding: const EdgeInsets.all(26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Eyebrow(context.l10n.todaysSales, color: const Color(0xFFCCC5CB)),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => setState(() => hideTodaySales = !hideTodaySales),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: Icon(
                    hideTodaySales
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 16,
                    color: const Color(0xFFCCC5CB),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.circle, size: 6, color: avocado),
                    const SizedBox(width: 6),
                    Text(
                      context.l10n.todayCaps,
                      style: const TextStyle(
                        color: avocado,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => hideTodaySales = !hideTodaySales),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                hideTodaySales
                    ? '••••••••'
                    : money(store, store.revenue(today)),
                style: const TextStyle(
                  color: paper,
                  fontSize: 43,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hideTodaySales
                ? context.l10n.amountHiddenReveal
                : '${transactions == 1 ? context.l10n.oneSaleRecorded : context.l10n.salesRecorded(transactions)}  ·  ${context.l10n.itemsSoldCount(sales.fold(0, (n, m) => n - m.delta))}',
            style: const TextStyle(color: Color(0xFFCFC6CD), fontSize: 12),
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: SizedBox(
                  height: 43,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(7, (i) {
                      final amount = store.revenue(
                        today.subtract(Duration(days: 6 - i)),
                      );
                      final amounts = List.generate(
                        7,
                        (j) => store.revenue(today.subtract(Duration(days: j))),
                      );
                      final max = amounts.fold(1, (a, b) => a > b ? a : b);
                      return Expanded(
                        child: Container(
                          height: 5 + 38 * amount / max,
                          margin: const EdgeInsets.only(right: 7),
                          decoration: BoxDecoration(
                            color: i == 6 ? avocado : const Color(0xFF635860),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 22),
              Text(
                context.l10n.last7Days,
                style: const TextStyle(
                  color: Color(0xFFBFB4BC),
                  fontSize: 8,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final stats = Column(
      children: [
        stat(
          Icons.inventory_2_outlined,
          context.l10n.stockOnHand,
          '${store.units}',
          context.l10n.uniqueProducts(store.products.length),
          avocado,
        ),
        const SizedBox(height: 12),
        stat(
          Icons.trending_down_rounded,
          context.l10n.needAttention,
          '${store.low.length}',
          store.low.isEmpty
              ? context.l10n.allStockedUp
              : context.l10n.runningLowReorder,
          maple,
          onTap: () => open(ReorderPage(store: store)),
        ),
      ],
    );
    return [
      if (!store.setupCompleted && store.movements.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Surface(
            color: avocado.withAlpha(55),
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: avocado,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.storefront_outlined, color: plum, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.setStoreCurrency,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.l10n.storeCurrencyCurrently(store.currency),
                        style: TextStyle(
                          color: context.stockMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _showFirstTimeSetup,
                  child: Text(context.l10n.configure),
                ),
              ],
            ),
          ),
        ),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (wide)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.wb_sunny_outlined, color: maple, size: 44),
            ),
          Text(
            DateFormat('EEEE, d MMMM').format(today),
            style: TextStyle(color: context.stockMuted, fontSize: 13),
          ),
        ],
      ),
      const SizedBox(height: 25),
      const NativeAdCard(),
      if (wide)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 6, child: hero),
            const SizedBox(width: 18),
            Expanded(flex: 4, child: stats),
          ],
        )
      else ...[
        hero,
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: compactStat(
                context.l10n.onHand,
                '${store.units}',
                Icons.inventory_2_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: compactStat(
                context.l10n.lowStock,
                '${store.low.length}',
                Icons.trending_down_rounded,
                onTap: () => open(ReorderPage(store: store)),
              ),
            ),
          ],
        ),
      ],
      section(context.l10n.quickActions),
      Row(
        children: [
          quickAction(
            context.l10n.newSale,
            Icons.add_shopping_cart_outlined,
            avocado,
            () => open(SalePage(store: store)),
          ),
          const SizedBox(width: 12),
          quickAction(
            context.l10n.addItem,
            Icons.add_box_outlined,
            paper,
            () => open(ProductForm(store: store)),
          ),
          const SizedBox(width: 12),
          quickAction(
            context.l10n.shareSale,
            Icons.qr_code_2_rounded,
            paper,
            _showShareSaleOptions,
          ),
        ],
      ),
      if (store.count != null) ...[
        const SizedBox(height: 18),
        Surface(
          color: avocado.withValues(alpha: .3),
          child: Row(
            children: [
              const Icon(Icons.pause_circle_outline),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.l10n.stockCountInProgress(store.count?['scope'] ?? context.l10n.allItems),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: () => open(CountPage(store: store)),
                child: Text(context.l10n.resume),
              ),
            ],
          ),
        ),
      ],
      section(
        context.l10n.needsRestocking,
        action: store.low.isNotEmpty
            ? context.l10n.shoppingListAction(store.low.length)
            : context.l10n.viewInventoryAction,
        onTap: () => store.low.isNotEmpty
            ? open(ReorderPage(store: store))
            : _selectTab(1),
      ),
      if (store.products.isEmpty)
        Surface(
          child: EmptyState(
            icon: Icons.inventory_2_outlined,
            title: context.l10n.stockBookStartsHere,
            subtitle: context.l10n.addFirstItemSubtitle,
            action: FilledButton.icon(
              onPressed: () => open(ProductForm(store: store)),
              icon: const Icon(Icons.add),
              label: Text(context.l10n.addFirstItem),
            ),
          ),
        )
      else
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
          child: Column(
            children: [
              for (final p
                  in (store.low.isEmpty ? store.products : store.low).take(3))
                productRow(p),
            ],
          ),
        ),
      section(
        context.l10n.theLatestInShop,
        action: context.l10n.viewAllAction,
        onTap: () => _selectTab(2),
      ),
      if (store.movements.isEmpty)
        Text(
          context.l10n.stockChangesAppearHere,
          style: TextStyle(color: context.stockMuted),
        )
      else
        ...store.movements.reversed
            .take(3)
            .map((m) => MovementTile(movement: m, store: store)),
      const SizedBox(height: 25),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 12, color: cement),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              context.l10n.savedOnDeviceReady,
              style: TextStyle(color: context.stockMuted, fontSize: 10),
            ),
          ),
        ],
      ),
    ];
  }

  Widget stat(
    IconData icon,
    String label,
    String value,
    String detail,
    Color color, {
    VoidCallback? onTap,
  }) {
    final content = Surface(
      padding: const EdgeInsets.all(19),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .25),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(icon, size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, color: context.stockMuted),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 29,
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        detail,
                        style: TextStyle(
                          fontSize: 10,
                          color: context.stockMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, color: context.stockMuted, size: 20),
        ],
      ),
    );
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: content,
      );
    }
    return content;
  }

  Widget compactStat(
    String label,
    String value,
    IconData icon, {
    VoidCallback? onTap,
  }) {
    final content = Surface(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: context.stockMuted, size: 16),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(color: context.stockMuted, fontSize: 11),
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, color: context.stockMuted, size: 14),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
        ],
      ),
    );
    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: content,
      );
    }
    return content;
  }

  Widget quickAction(
    String label,
    IconData icon,
    Color color,
    VoidCallback action,
  ) => Expanded(
    child: Material(
      color: color == paper ? context.stockPaper : color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 21, horizontal: 4),
          child: Column(
            children: [
              Icon(
                icon,
                size: 25,
                color: context.isStockDark && color == avocado ? plum : null,
              ),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  color: context.isStockDark && color == avocado ? plum : null,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget productRow(Product p) => InkWell(
    onTap: () => open(ProductPage(store: store, id: p.id)),
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 13),
      child: Row(
        children: [
          ProductImage(p, size: 53),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${p.category}  ·  ${p.barcode.isEmpty ? context.l10n.noBarcode : p.barcode}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: context.stockMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money(store, p.price),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                context.l10n.unitsLeft(store.stockLabel(p)),
                style: TextStyle(
                  color: store.stock(p) <= p.threshold
                      ? context.stockRust
                      : context.stockMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
  List<Widget> inventory(bool wide) {
    final categories = [
      'All items',
      ...store.products
          .map((p) => p.category.trim())
          .where((category) => category.isNotEmpty)
          .toSet()
          .toList()
        ..sort(),
    ];
    final filtered = store.products
        .where(
          (p) =>
              (category == 'All items' || p.category.trim() == category) &&
              '${p.name} ${p.barcode} ${p.category}'.toLowerCase().contains(
                search.toLowerCase(),
              ),
        )
        .toList();
    final displayItems =
        (showAllInventory || search.isNotEmpty || filtered.length <= 5)
        ? (filtered.length > inventoryDisplayLimit
            ? filtered.take(inventoryDisplayLimit).toList()
            : filtered)
        : filtered.take(5).toList();
    return [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.yourStockAtAGlance,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  context.l10n.itemsUnitsInShop(store.products.length, store.units),
                  style: TextStyle(fontSize: 12, color: context.stockMuted),
                ),
              ],
            ),
          ),
          IconButton.filled(
            onPressed: () => open(ProductForm(store: store)),
            tooltip: context.l10n.addItem,
            style: IconButton.styleFrom(
              backgroundColor: avocado,
              foregroundColor: plum,
              padding: const EdgeInsets.all(17),
            ),
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      const SizedBox(height: 25),
      TextField(
        onChanged: (v) => setState(() => search = v),
        decoration: InputDecoration(
          hintText: context.l10n.findItemPlaceholder,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            onPressed: scanToFind,
            tooltip: context.l10n.scanToFind,
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ),
      ),
      const SizedBox(height: 17),
      Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: Text(
              context.l10n.allItems,
              style: TextStyle(
                color: category == 'All items' ? paper : context.stockMuted,
                fontSize: 12,
              ),
            ),
            selected: category == 'All items',
            showCheckmark: false,
            onSelected: (_) => setState(() => category = 'All items'),
          ),
          ActionChip(
            avatar: const Icon(Icons.category_outlined, size: 16),
            label: Text(
              category == 'All items' ? context.l10n.categories : category,
              style: const TextStyle(fontSize: 12),
            ),
            onPressed: () => _showCategoryPicker(categories),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          Text(
            context.l10n.itemsCaps(filtered.length),
            style: TextStyle(
              fontSize: 10,
              color: context.stockMuted,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (store.low.isNotEmpty)
                ActionChip(
                  avatar: const Icon(
                    Icons.playlist_add_check_outlined,
                    size: 16,
                  ),
                  label: Text(
                    context.l10n.lowStock,
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: () => open(ReorderPage(store: store)),
                ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (filtered.isEmpty)
        Surface(
          child: EmptyState(
            icon: Icons.search_off,
            title: store.products.isEmpty
                ? context.l10n.aFreshStart
                : context.l10n.noMatchingItems,
            subtitle: store.products.isEmpty
                ? context.l10n.addFirstItemToStart
                : context.l10n.tryAnotherNameOrFilter,
            action: store.products.isEmpty
                ? FilledButton(
                    onPressed: () => open(ProductForm(store: store)),
                    child: Text(context.l10n.addItem),
                  )
                : null,
          ),
        )
      else if (wide) ...[
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: displayItems
              .map(
                (p) => SizedBox(
                  width:
                      (MediaQuery.sizeOf(context).width - 228 - 80 - 32).clamp(
                        0,
                        988,
                      ) /
                      3,
                  child: Material(
                    color: context.stockPaper,
                    borderRadius: BorderRadius.circular(22),
                    child: InkWell(
                      onTap: () => open(ProductPage(store: store, id: p.id)),
                      borderRadius: BorderRadius.circular(22),
                      child: Padding(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                ProductImage(p, size: 65),
                                const Spacer(),
                                if (store.stock(p) <= p.threshold)
                                  Tag('Low stock', color: context.stockRust),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              p.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              p.category,
                              style: TextStyle(
                                fontSize: 11,
                                color: context.stockMuted,
                              ),
                            ),
                            const SizedBox(height: 19),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    money(store, p.price),
                                    style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Text(
                                  store.stockLabel(p),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.stockMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        if (filtered.length > 5) ...[
          const SizedBox(height: 14),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!showAllInventory && search.isEmpty)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () =>
                        setState(() => showAllInventory = true),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text(
                      'See more (${filtered.length - 5} more items)',
                    ),
                  )
                else ...[
                  if (displayItems.length < filtered.length)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () => setState(
                          () => inventoryDisplayLimit += 25),
                      icon: const Icon(Icons.expand_more_rounded),
                      label: Text(
                        'See more (${filtered.length - displayItems.length} more items)',
                      ),
                    ),
                  if (showAllInventory) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () => setState(() {
                        showAllInventory = false;
                        inventoryDisplayLimit = 20;
                      }),
                      icon: const Icon(Icons.expand_less_rounded),
                      label: const Text('Show less'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ] else ...[
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 3),
          child: Column(
            children: [
              for (var i = 0; i < displayItems.length; i++) ...[
                productRow(displayItems[i]),
                if (i < displayItems.length - 1) const Divider(),
              ],
            ],
          ),
        ),
        if (filtered.length > 5) ...[
          const SizedBox(height: 14),
          Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!showAllInventory && search.isEmpty)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () =>
                        setState(() => showAllInventory = true),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text(
                      'See more (${filtered.length - 5} more items)',
                    ),
                  )
                else ...[
                  if (displayItems.length < filtered.length)
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () => setState(
                          () => inventoryDisplayLimit += 25),
                      icon: const Icon(Icons.expand_more_rounded),
                      label: Text(
                        'See more (${filtered.length - displayItems.length} more items)',
                      ),
                    ),
                  if (showAllInventory) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () => setState(() {
                        showAllInventory = false;
                        inventoryDisplayLimit = 20;
                      }),
                      icon: const Icon(Icons.expand_less_rounded),
                      label: const Text('Show less'),
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ],
      const SizedBox(height: 22),
      OutlinedButton.icon(
        onPressed: () => open(SharePage(store: store)),
        icon: const Icon(Icons.ios_share_outlined, size: 18),
        label: const Text('Export or share stock'),
      ),
    ];
  }

  List<Widget> records() {
    final movementsOnDay = store.onDay(day).reversed.toList();
    final filteredMovements = switch (dailyActivityFilter) {
      1 =>
        movementsOnDay
            .where((m) => m.type == 'Sale' || m.type.startsWith('Return'))
            .toList(),
      2 =>
        movementsOnDay
            .where((m) => m.type != 'Sale' && !m.type.startsWith('Return'))
            .toList(),
      _ => movementsOnDay,
    };
    // Keep each customer purchase and each related return together. A return
    // produces restock and refund movements per item, but staff should see one
    // customer-return entry instead of a separate row for every movement.
    final activityItems = <dynamic>[];
    final processedRefs = <String>{};

    for (final m in filteredMovements) {
      if (m.type == 'Sale' && m.reference.isNotEmpty) {
        final groupKey = 'sale:${m.reference}';
        if (!processedRefs.contains(groupKey)) {
          processedRefs.add(groupKey);
          final saleGroup = filteredMovements
              .where(
                (other) =>
                    other.type == 'Sale' && other.reference == m.reference,
              )
              .toList();
          if (saleGroup.length > 1) {
            activityItems.add(saleGroup);
          } else {
            activityItems.add(m);
          }
        }
      } else if (m.type.startsWith('Return') &&
          m.reference.isNotEmpty &&
          m.reference.startsWith('ret-')) {
        final groupKey = 'return:${m.reference}';
        if (!processedRefs.contains(groupKey)) {
          processedRefs.add(groupKey);
          activityItems.add(
            filteredMovements
                .where(
                  (other) =>
                      other.type.startsWith('Return') &&
                      other.reference == m.reference,
                )
                .toList(),
          );
        }
      } else {
        activityItems.add(m);
      }
    }

    final displayActivity = showAllRecords || activityItems.length <= 5
        ? activityItems
        : activityItems.take(5).toList();

    return [
      Text(
        context.l10n.everyDayAccountedFor,
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 10),
      Text(
        context.l10n.salesAndChangesInOnePlace,
        style: TextStyle(color: context.stockMuted, fontSize: 12),
      ),
      const SizedBox(height: 20),
      SegmentedButton<int>(
        segments: [
          ButtonSegment(
            value: 0,
            label: Text(context.l10n.dailyActivity),
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
          ),
          ButtonSegment(
            value: 1,
            label: Text(context.l10n.businessSummary),
            icon: const Icon(Icons.insights_outlined, size: 18),
          ),
        ],
        selected: {recordsMode},
        onSelectionChanged: (s) => setState(() => recordsMode = s.first),
      ),
      const SizedBox(height: 20),
      if (recordsMode == 0) ...[
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => scanReceipt(),
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
                label: Text(context.l10n.scanReceiptQr),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.outlined(
              tooltip: context.l10n.findReceiptByReference,
              onPressed: _promptReceiptSearch,
              icon: const Icon(Icons.search_rounded, size: 20),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<int>(
              tooltip: context.l10n.filterDayActivity,
              initialValue: dailyActivityFilter,
              onSelected: (value) => setState(() {
                dailyActivityFilter = value;
                showAllRecords = false;
              }),
              itemBuilder: (menuCtx) => [
                for (final option in [
                  (0, context.l10n.allActivity),
                  (1, context.l10n.salesAndRefunds),
                  (2, context.l10n.stockActivity),
                ])
                  PopupMenuItem(
                    value: option.$1,
                    child: Row(
                      children: [
                        Icon(
                          dailyActivityFilter == option.$1
                              ? Icons.check_circle_rounded
                              : Icons.circle_outlined,
                          size: 18,
                          color: dailyActivityFilter == option.$1
                              ? avocado
                              : context.stockMuted,
                        ),
                        const SizedBox(width: 10),
                        Text(option.$2),
                      ],
                    ),
                  ),
              ],
              icon: Icon(
                Icons.filter_list_rounded,
                color: dailyActivityFilter == 1
                    ? context.stockInk
                    : context.stockMuted,
              ),
              style: IconButton.styleFrom(
                backgroundColor: dailyActivityFilter == 1
                    ? avocado
                    : context.stockPaper,
                side: BorderSide(color: context.stockLine),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              IconButton(
                tooltip: context.l10n.previousDay,
                onPressed: () =>
                    setState(() => day = day.subtract(const Duration(days: 1))),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () async {
                    final value = await showDatePicker(
                      context: context,
                      initialDate: day,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (value != null) setState(() => day = value);
                  },
                  icon: const Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text(
                    DateFormat('EEE, d MMM yyyy').format(day),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ),
              IconButton(
                tooltip: context.l10n.nextDay,
                onPressed: dayKey(day) == dayKey(DateTime.now())
                    ? null
                    : () => setState(
                        () => day = day.add(const Duration(days: 1)),
                      ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Surface(
          color: avocado,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow(context.l10n.salesRecordedTitle, color: plum),
                    const SizedBox(height: 10),
                    Text(
                      money(store, store.revenue(day)),
                      style: Theme.of(
                        context,
                      ).textTheme.headlineLarge?.copyWith(color: plum),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${movementsOnDay.length}',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(context.l10n.stockMovements, style: const TextStyle(fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
        section(context.l10n.theDaysActivity),
        if (activityItems.isEmpty)
          Surface(
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: context.l10n.aQuietPageSoFar,
              subtitle: context.l10n.noActivityMatchesFilter,
            ),
          )
        else ...[
          for (final item in displayActivity)
            if (item is List<Movement>)
              if (item.first.type == 'Sale')
                DailySaleGroupTile(saleGroup: item, store: store)
              else
                DailyReturnGroupTile(returnGroup: item, store: store)
            else if (item is Movement)
              MovementTile(movement: item, store: store),
          if (activityItems.length > 5) ...[
            const SizedBox(height: 12),
            Center(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
                onPressed: () =>
                    setState(() => showAllRecords = !showAllRecords),
                icon: Icon(
                  showAllRecords
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                ),
                label: Text(
                  showAllRecords
                      ? context.l10n.showLess
                      : context.l10n.seeMoreEntries(activityItems.length - 5),
                ),
              ),
            ),
          ],
        ],
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => open(SharePage(store: store, initialDay: day)),
          icon: const Icon(Icons.ios_share_outlined, size: 19),
          label: Text(context.l10n.shareOrExportThisDay),
        ),
      ] else ...[
        Row(
          children: [
            Expanded(
              child: Text(
                context.l10n.performanceOverview,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            SegmentedButton<int>(
              segments: [
                ButtonSegment(value: 7, label: Text(context.l10n.daysCount(7))),
                ButtonSegment(value: 30, label: Text(context.l10n.daysCount(30))),
              ],
              selected: {insightsDays},
              onSelectionChanged: (s) => setState(() => insightsDays = s.first),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Builder(
          builder: (context) {
            final summary = store.businessSummary(days: insightsDays);
            final int revenue = summary['totalRevenue'] ?? 0;
            final int grossProfit = summary['estimatedGrossProfit'] ?? 0;
            final int missingCost = summary['itemsMissingCost'] ?? 0;
            final List topSellers = summary['topSellers'] as List? ?? [];
            final List slowMovers = summary['slowMovers'] as List? ?? [];

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Surface(
                        color: plum,
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Eyebrow(context.l10n.totalSales, color: avocado),
                            const SizedBox(height: 8),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                money(store, revenue),
                                style: const TextStyle(
                                  color: paper,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              context.l10n.salesInDays(summary['salesCount'] ?? 0, insightsDays),
                              style: const TextStyle(
                                color: Color(0xFFCCC5CB),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Surface(
                        color: avocado,
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Eyebrow(context.l10n.estGrossProfit, color: plum),
                            const SizedBox(height: 8),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                money(store, grossProfit),
                                style: TextStyle(
                                  color: plum,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              context.l10n.revenueMinusProductCosts,
                              style: const TextStyle(color: plum, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                if (missingCost > 0) ...[
                  const SizedBox(height: 12),
                  Surface(
                    color: linen,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: context.stockMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            context.l10n.salesLackedCost(missingCost),
                            style: TextStyle(
                              fontSize: 11,
                              color: context.stockMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                section(context.l10n.topSellingItems),
                if (topSellers.isEmpty)
                  Surface(
                    child: EmptyState(
                      icon: Icons.trending_up,
                      title: context.l10n.noSalesRecordedYet,
                      subtitle: context.l10n.salesRankSubtitle,
                    ),
                  )
                else ...[
                  Builder(
                    builder: (context) {
                      final displayedTopSellers =
                          topSellers.take(topSellersDisplayLimit).toList();
                      return Surface(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < displayedTopSellers.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: i == 0
                                            ? avocado
                                            : context.stockLinen,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Text(
                                        '${i + 1}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: i == 0 ? plum : context.stockMuted,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            displayedTopSellers[i]['name'],
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            context.l10n.quantitySold(
                                                displayedTopSellers[i]['quantity'],
                                                displayedTopSellers[i]['unit']
                                                    as String),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: context.stockMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      money(store,
                                          displayedTopSellers[i]['revenue']),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  if (topSellers.length > 10) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (topSellersDisplayLimit < topSellers.length)
                            OutlinedButton.icon(
                              onPressed: () => setState(
                                  () => topSellersDisplayLimit += 15),
                              icon: const Icon(Icons.expand_more_rounded,
                                  size: 18),
                              label: Text(
                                'Show more (${topSellers.length - topSellersDisplayLimit} remaining)',
                              ),
                            ),
                          if (topSellersDisplayLimit > 10) ...[
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => setState(
                                  () => topSellersDisplayLimit = 10),
                              icon: const Icon(Icons.expand_less_rounded,
                                  size: 18),
                              label: const Text('Show less'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 24),
                section(
                  context.l10n.slowMovingItems,
                  action: slowMovers.length > 5
                      ? 'View all (${slowMovers.length})'
                      : null,
                  onTap: slowMovers.length > 5
                      ? () => open(
                            SlowMovingItemsPage(
                              store: store,
                              slowMovers: slowMovers,
                            ),
                          )
                      : null,
                ),
                Text(
                  context.l10n.slowMovingSubtitle,
                  style: TextStyle(color: context.stockMuted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (slowMovers.isEmpty)
                  Surface(
                    child: EmptyState(
                      icon: Icons.check_circle_outline,
                      title: context.l10n.healthyMovement,
                      subtitle: context.l10n.healthyMovementSubtitle,
                    ),
                  )
                else ...[
                  Builder(
                    builder: (context) {
                      final displayedSlowMovers =
                          slowMovers.take(slowMoversDisplayLimit).toList();
                      return Surface(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        child: Column(
                          children: [
                            for (var i = 0; i < displayedSlowMovers.length; i++) ...[
                              if (i > 0) const Divider(height: 1),
                              InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => open(
                                  ProductPage(
                                    store: store,
                                    id: displayedSlowMovers[i]['id'] as String,
                                  ),
                                ),
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.hourglass_empty_rounded,
                                        size: 20,
                                        color: context.stockMuted,
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              displayedSlowMovers[i]['name'],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            Text(
                                              context.l10n.quantityInStockLabel(
                                                displayedSlowMovers[i]['stock'],
                                                displayedSlowMovers[i]['unit']
                                                    as String,
                                              ),
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: context.stockMuted,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.end,
                                        children: [
                                          Text(
                                            money(store,
                                                displayedSlowMovers[i]['valuation']),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                          ),
                                          Text(
                                            context.l10n.tiedInStock,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: context.stockMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    },
                  ),
                  if (slowMovers.length > 15) ...[
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (slowMoversDisplayLimit < slowMovers.length)
                          OutlinedButton.icon(
                            onPressed: () => setState(
                                () => slowMoversDisplayLimit += 20),
                            icon: const Icon(Icons.expand_more_rounded,
                                size: 18),
                            label: Text(
                              'Show more (${slowMovers.length - slowMoversDisplayLimit} remaining)',
                            ),
                          ),
                        if (slowMoversDisplayLimit > 15) ...[
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => setState(
                                () => slowMoversDisplayLimit = 15),
                            icon: const Icon(Icons.expand_less_rounded,
                                size: 18),
                            label: const Text('Show less'),
                          ),
                        ],
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: () => open(
                            SlowMovingItemsPage(
                              store: store,
                              slowMovers: slowMovers,
                            ),
                          ),
                          icon: const Icon(Icons.list_alt_rounded, size: 18),
                          label: Text('View all (${slowMovers.length})'),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ],
    ];
  }

  List<Widget> more() => [
    Text(
      context.l10n.makeItYourOwn,
      style: Theme.of(context).textTheme.headlineLarge,
    ),
    const SizedBox(height: 12),
    Text(
      context.l10n.goodToolsWellRunShop,
      style: TextStyle(color: context.stockMuted),
    ),
    const SizedBox(height: 24),
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(context.l10n.storeAndPreferences),
        const SizedBox(height: 10),
        Surface(
          child: Column(
            children: [
              menu(
                Icons.storefront_outlined,
                context.l10n.storeSettings,
                context.l10n.storeSettingsSub(store.shop, store.currency),
                settings,
              ),
              menu(
                Icons.auto_stories_outlined,
                context.l10n.welcomeTour,
                context.l10n.welcomeTourSubtitle,
                () => open(OnboardingPage(store: store, isRevisit: true)),
              ),
              menu(
                Icons.privacy_tip_outlined,
                context.l10n.privacyDataPolicy,
                context.l10n.privacySub,
                () => open(const PrivacyPolicyPage()),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Eyebrow(context.l10n.operationsAndTools),
        const SizedBox(height: 10),
        Surface(
          child: Column(
            children: [
              menu(
                Icons.fact_check_outlined,
                context.l10n.stockCount,
                store.count == null
                    ? context.l10n.stockCountSubEmpty
                    : context.l10n.stockCountSubActive,
                () => open(CountPage(store: store)),
              ),
              menu(
                Icons.playlist_add_check_outlined,
                context.l10n.shoppingReorderList,
                store.low.isEmpty
                    ? context.l10n.reorderSubEmpty
                    : context.l10n.reorderSubItems(store.low.length),
                () => open(ReorderPage(store: store)),
              ),
              menu(
                Icons.qr_code_scanner_rounded,
                context.l10n.streamScanner,
                context.l10n.streamScannerSub,
                () => open(QrStreamReceiverPage(store: store)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Eyebrow(context.l10n.dataAndSharing),
        const SizedBox(height: 10),
        Surface(
          child: Column(
            children: [
              menu(
                Icons.swap_horiz_rounded,
                context.l10n.shareAndExport,
                context.l10n.shareExportSub,
                () => open(SharePage(store: store)),
              ),
              menu(
                Icons.folder_open_outlined,
                context.l10n.receivedSavedRecords,
                context.l10n.receivedRecordsSub(store.received.length),
                () => open(ReceivedPage(store: store)),
              ),
              menu(
                Icons.settings_backup_restore_outlined,
                context.l10n.fullBackupRestore,
                context.l10n.backupRestoreSub,
                () => open(BackupRestorePage(store: store)),
              ),
            ],
          ),
        ),
      ],
    ),
    const SizedBox(height: 20),
    Surface(
      color: plum,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(context.l10n.stockBookGoesWithYou, color: avocado),
          const SizedBox(height: 15),
          Text(
            context.l10n.noSignalNoInterruption,
            style: TextStyle(
              color: paper,
              fontSize: 25,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.l10n.offlineDeviceStorageDescription,
            style: const TextStyle(
              color: Color(0xFFD1C6CD),
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ],
      ),
    ),
    if (store.products.isEmpty) ...[
      const SizedBox(height: 22),
      OutlinedButton(
        onPressed: () async {
          if (await confirm(
            context,
            context.l10n.exploreSampleTitle,
            context.l10n.exploreSampleMessage,
            action: context.l10n.addSampleData,
          )) {
            try {
              await store.loadDemo();
            } catch (e) {
              if (mounted) showMessage(context, friendlyError(e));
            }
          }
        },
        child: Text(context.l10n.exploreWithSampleItems),
      ),
    ],
    const SizedBox(height: 30),
    Center(child: Eyebrow(context.l10n.stockmixTagline)),
  ];
  Widget menu(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback action,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 6),
    leading: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: context.stockLinen,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, size: 21),
    ),
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(
        subtitle,
        style: TextStyle(color: context.stockMuted, fontSize: 11),
      ),
    ),
    trailing: const Icon(Icons.chevron_right, color: cement, size: 19),
    onTap: action,
  );
  void settings() {
    open(StoreSettingsPage(store: store));
  }
}

class _ReturnLineSummary {
  final String productId;
  final String name;
  int restockedBaseUnits = 0;
  int refundedBaseUnits = 0;
  int refundedAmount = 0;

  _ReturnLineSummary({required this.productId, required this.name});

  int get returnedBaseUnits => restockedBaseUnits > refundedBaseUnits
      ? restockedBaseUnits
      : refundedBaseUnits;
}

class DailyReturnGroupTile extends StatelessWidget {
  final List<Movement> returnGroup;
  final StockStore store;

  const DailyReturnGroupTile({
    super.key,
    required this.returnGroup,
    required this.store,
  });

  int _refundedBaseUnits(Movement refund) {
    if (refund.saleQuantity != null) return refund.saleQuantity!;
    final originalReference = refund.reference.startsWith('ret-')
        ? refund.reference.substring(4)
        : '';
    final originalSale = store.movements
        .where(
          (movement) =>
              movement.type == 'Sale' &&
              movement.productId == refund.productId &&
              (movement.id == refund.returnOf ||
                  (refund.returnOf == null &&
                      movement.reference == originalReference)),
        )
        .firstOrNull;
    if (originalSale == null || originalSale.price == 0) return 0;
    return refund.price ~/ originalSale.price;
  }

  List<_ReturnLineSummary> get _lines {
    final grouped = <String, _ReturnLineSummary>{};
    for (final movement in returnGroup) {
      final line = grouped.putIfAbsent(
        movement.productId,
        () => _ReturnLineSummary(
          productId: movement.productId,
          name: movement.name,
        ),
      );
      if (movement.type == 'Return restock') {
        line.restockedBaseUnits += movement.delta;
      } else if (movement.type == 'Return refund') {
        line.refundedBaseUnits += _refundedBaseUnits(movement);
        line.refundedAmount += movement.price;
      }
    }
    return grouped.values.toList();
  }

  @override
  Widget build(BuildContext context) {
    final first = returnGroup.first;
    final lines = _lines;
    final itemNames = lines.map((line) => line.name).join(', ');
    final refundedTotal = lines.fold<int>(
      0,
      (sum, line) => sum + line.refundedAmount,
    );
    final returnedTotal = lines.fold<int>(
      0,
      (sum, line) => sum + line.returnedBaseUnits,
    );
    final returnTime = DateFormat(
      'h:mm a',
    ).format(DateTime.parse(first.at).toLocal());

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: context.stockPaper,
        borderRadius: BorderRadius.circular(18),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 8,
          ),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: rust.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.replay_outlined,
              size: 21,
              color: context.stockRust,
            ),
          ),
          title: Text(
            itemNames,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Customer return (${lines.length} ${lines.length == 1 ? 'item' : 'items'})  ·  $returnTime',
              style: TextStyle(fontSize: 10, color: context.stockMuted),
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                refundedTotal > 0
                    ? '-${money(store, refundedTotal)}'
                    : 'Restocked',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: context.stockRust,
                ),
              ),
              Text(
                '$returnedTotal returned',
                style: TextStyle(fontSize: 10, color: context.stockMuted),
              ),
            ],
          ),
          onTap: () => showModalBottomSheet<void>(
            context: context,
            showDragHandle: true,
            builder: (sheetContext) => SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Tag('Customer return', color: context.stockRust),
                    const SizedBox(height: 12),
                    Text(
                      'Returned items',
                      style: Theme.of(sheetContext).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      DateFormat(
                        'd MMM yyyy · h:mm a',
                      ).format(DateTime.parse(first.at).toLocal()),
                      style: TextStyle(color: context.stockMuted, fontSize: 12),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    for (final line in lines) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    line.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${line.returnedBaseUnits} ${unitLabel(store.products.where((p) => p.id == line.productId).firstOrNull?.unit ?? 'units', line.returnedBaseUnits)} returned${line.restockedBaseUnits > 0 ? ' · Restocked' : ''}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: context.stockMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (line.refundedAmount > 0)
                              Text(
                                '-${money(store, line.refundedAmount)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: context.stockRust,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Cash refunded',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Text(
                          money(store, refundedTotal),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    OutlinedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DailySaleGroupTile extends StatelessWidget {
  final List<Movement> saleGroup;
  final StockStore store;

  const DailySaleGroupTile({
    super.key,
    required this.saleGroup,
    required this.store,
  });

  @override
  Widget build(BuildContext context) {
    final first = saleGroup.first;
    final totalUnits = saleGroup.fold<int>(0, (sum, m) => sum + (-m.delta));
    final totalMoney = saleGroup.fold<int>(
      0,
      (sum, m) => sum + store.saleTotal(m),
    );
    final itemNames = saleGroup.map((m) => m.name).join(', ');
    final saleTime = DateFormat(
      'h:mm a',
    ).format(DateTime.parse(first.at).toLocal());

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: context.stockPaper,
        borderRadius: BorderRadius.circular(18),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 8,
          ),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: avocado.withAlpha(45),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              Icons.shopping_bag_outlined,
              size: 21,
              color: context.stockInk,
            ),
          ),
          title: Text(
            itemNames,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Sale (${saleGroup.length} items)  ·  $saleTime',
              style: TextStyle(fontSize: 10, color: context.stockMuted),
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money(store, totalMoney),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              Text(
                '$totalUnits sold',
                style: TextStyle(fontSize: 10, color: context.stockMuted),
              ),
            ],
          ),
          onTap: () => showSaleTransactionDetails(context, store, saleGroup),
        ),
      ),
    );
  }
}

Future<void> showSaleTransactionDetails(
  BuildContext context,
  StockStore store,
  List<Movement> saleGroup,
) async {
  if (saleGroup.isEmpty) return;
  final first = saleGroup.first;
  final totalMoney = saleGroup.fold<int>(
    0,
    (sum, m) => sum + store.saleTotal(m),
  );

  final action = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetCtx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Tag('Customer Purchase'),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(sheetCtx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Sale transaction',
              style: Theme.of(sheetCtx).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              '${DateFormat('d MMM yyyy · h:mm a').format(DateTime.parse(first.at).toLocal())}  ·  ${saleGroup.length} items',
              style: TextStyle(color: sheetCtx.stockMuted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            // List each item purchased
            for (final m in saleGroup) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${m.saleQuantity ?? -m.delta} ${m.saleUnit ?? store.product(m.productId).unit} × ${money(store, m.price)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: sheetCtx.stockMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      money(store, store.saleTotal(m)),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Process return for ${m.name}',
                      onPressed: store.returnableQuantity(m) > 0
                          ? () => Navigator.pop(sheetCtx, 'return:${m.id}')
                          : null,
                      icon: const Icon(Icons.replay_outlined, size: 19),
                    ),
                  ],
                ),
              ),
            ],
            const Divider(),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total paid',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  money(store, totalMoney),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
            if (first.reference.isNotEmpty) ...[
              const SizedBox(height: 16),
              SelectableText(
                'Transaction Ref: ${first.reference}',
                style: TextStyle(fontSize: 10, color: sheetCtx.stockMuted),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: rust,
                foregroundColor: paper,
              ),
              onPressed: saleGroup.any((m) => store.returnableQuantity(m) > 0)
                  ? () => Navigator.pop(sheetCtx, 'returnAll')
                  : null,
              icon: const Icon(Icons.replay_circle_filled_outlined),
              label: const Text('Process return for all items'),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.pop(sheetCtx, 'receipt'),
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('Share receipt'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(sheetCtx),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  if (!context.mounted) return;
  if (action == 'receipt') {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ReceiptInvoicePage.fromMovement(store: store, movement: first),
      ),
    );
  } else if (action == 'returnAll') {
    await _showFullReturnDialog(context, store, saleGroup);
  } else if (action != null && action.startsWith('return:')) {
    final id = action.substring('return:'.length);
    final line = saleGroup.where((m) => m.id == id).firstOrNull;
    if (line != null) {
      await MovementTile(
        store: store,
        movement: line,
      )._showReturnDialog(context);
    }
  }
}

Future<void> _showFullReturnDialog(
  BuildContext context,
  StockStore store,
  List<Movement> saleGroup,
) async {
  final available = saleGroup
      .where((m) => store.returnableQuantity(m) > 0)
      .toList();
  if (available.isEmpty) {
    showMessage(context, 'All items in this sale have already been returned.');
    return;
  }
  var returnToStock = true;
  var refundMoney = true;
  final note = TextEditingController(text: 'Customer return');
  final total = available.fold<int>(
    0,
    (sum, m) => sum + store.refundFor(m, store.returnableQuantity(m)),
  );
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) => AlertDialog(
        title: const Text('Return all available items'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${available.length} item ${available.length == 1 ? 'line' : 'lines'} will be returned. Refund total: ${money(store, total)}.',
              style: TextStyle(fontSize: 12, color: context.stockMuted),
            ),
            const SizedBox(height: 12),
            for (final m in available)
              Text(
                '• ${m.name}: ${store.returnableQuantity(m)}',
                style: const TextStyle(fontSize: 12),
              ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Return items to store shelf'),
              subtitle: Text(
                'Turn this off for damaged or discarded goods.',
                style: TextStyle(fontSize: 11, color: context.stockMuted),
              ),
              value: returnToStock,
              onChanged: (value) => setDialogState(() => returnToStock = value),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Refund customer cash'),
              subtitle: Text(
                refundMoney
                    ? 'Refund ${money(store, total)}'
                    : 'Customer exchange or store credit',
                style: TextStyle(fontSize: 11, color: context.stockMuted),
              ),
              value: refundMoney,
              onChanged: (value) => setDialogState(() => refundMoney = value),
            ),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'Reason for return'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm full return'),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    final lines = await store.processFullReturn(
      saleMovements: available,
      returnToStock: returnToStock,
      refundMoney: refundMoney,
      note: note.text,
    );
    if (context.mounted) {
      showMessage(context, 'Return processed for $lines item lines.');
    }
  } catch (error) {
    if (context.mounted) showMessage(context, friendlyError(error));
  }
}

class MovementTile extends StatelessWidget {
  final Movement movement;
  final StockStore store;
  const MovementTile({super.key, required this.movement, required this.store});
  @override
  Widget build(BuildContext context) {
    final m = movement;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: context.stockPaper,
        borderRadius: BorderRadius.circular(18),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 7,
          ),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color:
                  (m.type == 'Sale'
                          ? avocado
                          : m.type.startsWith('Return')
                          ? rust
                          : cement)
                      .withValues(alpha: .18),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              m.type == 'Sale'
                  ? Icons.shopping_bag_outlined
                  : m.type.startsWith('Return')
                  ? Icons.replay_outlined
                  : m.delta > 0
                  ? Icons.south_west
                  : Icons.north_east,
              size: 21,
              color: m.type.startsWith('Return') ? context.stockRust : null,
            ),
          ),
          title: Text(
            m.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${m.type}  ·  ${DateFormat('h:mm a').format(DateTime.parse(m.at).toLocal())}${m.photo == null ? '' : '  ·  Photo'}',
              style: TextStyle(fontSize: 10, color: context.stockMuted),
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                m.type == 'Sale'
                    ? money(store, store.saleTotal(m))
                    : m.type == 'Return restock'
                    ? '+${m.delta}'
                    : m.type == 'Return refund'
                    ? '-${money(store, m.price)}'
                    : '${m.delta > 0 ? '+' : ''}${m.delta}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: m.type.startsWith('Return') ? context.stockRust : null,
                ),
              ),
              if (m.type == 'Sale')
                Text(
                  '${m.saleQuantity ?? -m.delta} ${m.saleUnit ?? 'unit'} sold',
                  style: TextStyle(fontSize: 10, color: context.stockMuted),
                )
              else if (m.type == 'Return restock')
                Text(
                  'restocked',
                  style: TextStyle(fontSize: 10, color: context.stockMuted),
                )
              else if (m.type == 'Return refund')
                Text(
                  'refunded',
                  style: TextStyle(fontSize: 10, color: context.stockMuted),
                ),
            ],
          ),
          onTap: () async {
            final action = await showModalBottomSheet<String>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (sheetCtx) => SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 30),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Tag(m.type),
                          IconButton(
                            icon: const Icon(Icons.close, size: 20),
                            onPressed: () => Navigator.pop(sheetCtx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        m.name,
                        style: Theme.of(sheetCtx).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Quantity change: ${m.delta > 0 ? '+' : ''}${m.delta}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        m.type == 'Sale'
                            ? 'Sold as: ${m.saleQuantity ?? -m.delta} ${m.saleUnit ?? 'unit'} at ${money(store, m.price)} each'
                            : 'Unit price: ${money(store, m.price)}',
                      ),
                      if (m.type == 'Sale') ...[
                        const SizedBox(height: 8),
                        Text('Line total: ${money(store, store.saleTotal(m))}'),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        DateFormat(
                          'd MMM yyyy · h:mm a',
                        ).format(DateTime.parse(m.at).toLocal()),
                        style: TextStyle(color: context.stockMuted),
                      ),
                      if (m.note.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(m.note, style: const TextStyle(height: 1.5)),
                      ],
                      if (m.photo != null) ...[
                        const SizedBox(height: 18),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.memory(
                            base64Decode(m.photo!),
                            height: 220,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ],
                      if (m.reference.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        SelectableText(
                          'Reference: ${m.reference}',
                          style: TextStyle(
                            fontSize: 10,
                            color: context.stockMuted,
                          ),
                        ),
                      ],
                      if (m.type == 'Sale') ...[
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    Navigator.pop(sheetCtx, 'receipt'),
                                icon: const Icon(
                                  Icons.receipt_long_outlined,
                                  size: 18,
                                ),
                                label: const Text('Share receipt'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: rust,
                                  foregroundColor: paper,
                                ),
                                onPressed: () =>
                                    Navigator.pop(sheetCtx, 'return'),
                                icon: const Icon(
                                  Icons.replay_outlined,
                                  size: 18,
                                ),
                                label: const Text('Process return'),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        const SizedBox(height: 22),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(sheetCtx),
                            child: const Text('Close'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );

            if (!context.mounted) return;
            if (action == 'receipt') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReceiptInvoicePage.fromMovement(
                    store: store,
                    movement: m,
                  ),
                ),
              );
            } else if (action == 'return') {
              await _showReturnDialog(context);
            }
          },
        ),
      ),
    );
  }

  Future<void> _showReturnDialog(BuildContext context) async {
    final m = movement;
    final alreadyReturned = store.returnedQuantity(m);
    final maxReturn = store.returnableQuantity(m);
    if (maxReturn <= 0) {
      if (context.mounted) {
        showMessage(
          context,
          'All units from this sale have already been returned.',
        );
      }
      return;
    }

    var returnQty = 1;
    var returnToStock = true;
    var refundMoney = true;
    final noteController = TextEditingController(text: 'Customer return');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Return ${m.name}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Original purchase: ${m.saleQuantity ?? -m.delta} ${m.saleUnit ?? 'units'} for ${money(store, store.saleTotal(m))}. Returns are counted in ${store.product(m.productId).unit}.${alreadyReturned > 0 ? ' ($alreadyReturned base units already returned)' : ''}',
                style: TextStyle(fontSize: 12, color: context.stockMuted),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Text(
                      'Quantity to return',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: returnQty > 1
                            ? () => setDialogState(() => returnQty--)
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '$returnQty',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: returnQty < maxReturn
                            ? () => setDialogState(() => returnQty++)
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 18),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Return item to store shelf',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  returnToStock
                      ? 'Stock will increase by $returnQty'
                      : 'Item is damaged or discarded; stock unchanged',
                  style: TextStyle(fontSize: 11, color: context.stockMuted),
                ),
                value: returnToStock,
                onChanged: (val) => setDialogState(() => returnToStock = val),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Refund customer cash',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  refundMoney
                      ? 'Refund total: ${money(store, store.refundFor(m, returnQty))}'
                      : 'Customer exchange or store credit',
                  style: TextStyle(fontSize: 11, color: context.stockMuted),
                ),
                value: refundMoney,
                onChanged: (val) => setDialogState(() => refundMoney = val),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(
                  labelText: 'Reason for return',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirm return'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && context.mounted) {
      try {
        await store.processReturn(
          saleMovement: m,
          returnQty: returnQty,
          returnToStock: returnToStock,
          refundMoney: refundMoney,
          note: noteController.text,
        );
        if (context.mounted) {
          showMessage(context, 'Return processed successfully.');
        }
      } catch (e) {
        if (context.mounted) showMessage(context, friendlyError(e));
      }
    }
  }
}

class ProductPage extends StatelessWidget {
  final StockStore store;
  final String id;
  const ProductPage({super.key, required this.store, required this.id});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final p = store.products.where((item) => item.id == id).firstOrNull;
      if (p == null) {
        return Scaffold(
          appBar: AppBar(title: Text(context.l10n.itemDetails)),
          body: Center(child: Text(context.l10n.itemRemoved)),
        );
      }
      final qty = store.stock(p);
      void open(Widget page) =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => page));

      Future<void> handleDelete() async {
        if (store.count != null) {
          showMessage(
            context,
            context.l10n.finishCancelCountFirst,
          );
          return;
        }
        if (qty > 0) {
          showMessage(
            context,
            context.l10n.cannotDeleteStockRemaining(store.stockLabel(p)),
          );
          return;
        }
        final confirmed = await confirm(
          context,
          context.l10n.deleteItemConfirmTitle(p.name),
          context.l10n.deleteItemConfirmMessage,
          action: context.l10n.deleteItemAction,
        );
        if (!confirmed) return;
        try {
          await store.deleteProduct(p.id);
          if (context.mounted) {
            Navigator.pop(context);
            showMessage(context, context.l10n.itemDeletedFromInventory(p.name));
          }
        } catch (e) {
          if (context.mounted) showMessage(context, friendlyError(e));
        }
      }

      void showImagePopup() {
        final bytes = ProductImage.decodeBytes(p.photo);
        showDialog<void>(
          context: context,
          builder: (dialogCtx) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 24,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 500,
                  maxHeight: 600,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: dialogCtx.stockPaper,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.25),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    p.category,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: dialogCtx.stockMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: context.l10n.close,
                              onPressed: () => Navigator.pop(dialogCtx),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: bytes != null
                            ? InteractiveViewer(
                                clipBehavior: Clip.antiAlias,
                                maxScale: 4.0,
                                child: Image.memory(
                                  bytes,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => Container(
                                    height: 240,
                                    color: dialogCtx.stockLinen,
                                    alignment: Alignment.center,
                                    child: const Icon(
                                      Icons.broken_image_outlined,
                                      size: 48,
                                    ),
                                  ),
                                ),
                              )
                            : Container(
                                height: 240,
                                color: dialogCtx.stockLinen,
                                alignment: Alignment.center,
                                child: Icon(
                                  categoryIcon(p.category),
                                  size: 72,
                                  color: dialogCtx.stockMuted,
                                ),
                              ),
                      ),
                      if (bytes != null) ...[
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.pinch_outlined,
                                size: 15,
                                color: dialogCtx.stockMuted,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                context.l10n.pinchToZoom((p.photo!.length * .75 / 1024).round()),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: dialogCtx.stockMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      }

      return Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.itemDetails),
          actions: [
            IconButton(
              tooltip: context.l10n.editItem,
              onPressed: () => open(ProductForm(store: store, product: p)),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: context.l10n.deleteItem,
              onPressed: handleDelete,
              icon: Icon(Icons.delete_outline, color: context.stockRust),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Tooltip(
                            message: context.l10n.tapToViewFullImage,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: showImagePopup,
                              child: Stack(
                                children: [
                                  ProductImage(p, size: 110),
                                  Positioned(
                                    right: 6,
                                    bottom: 6,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.55,
                                        ),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.fullscreen_rounded,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Spacer(),
                          Tag(
                            qty == 0
                                ? context.l10n.outOfStock
                                : qty <= p.threshold
                                ? context.l10n.runningLow
                                : context.l10n.inStock,
                            color: qty <= p.threshold
                                ? context.stockRust
                                : context.stockPositive,
                          ),
                        ],
                      ),
                      const SizedBox(height: 25),
                      Eyebrow(p.category),
                      const SizedBox(height: 10),
                      Text(
                        p.name,
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Eyebrow(context.l10n.unitPriceLabel(p.unit)),
                                const SizedBox(height: 8),
                                Text(
                                  money(store, p.price),
                                  style: const TextStyle(
                                    fontSize: 31,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Eyebrow(context.l10n.available),
                              const SizedBox(height: 8),
                              Text(
                                store.stockLabel(p),
                                style: const TextStyle(
                                  fontSize: 25,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 18),
                      Text(
                        context.l10n.costAndAlert(money(store, p.cost), p.threshold),
                        style: TextStyle(
                          fontSize: 12,
                          color: context.stockMuted,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (p.sellsByPack) ...[
                        Text(
                          context.l10n.packInfo(p.packSize, p.unit, money(store, p.packPrice!), p.defaultUnit.name),
                          style: TextStyle(
                            fontSize: 12,
                            color: context.stockMuted,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Row(
                        children: [
                          Icon(
                            Icons.qr_code,
                            size: 20,
                            color: context.stockMuted,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              p.barcode.isEmpty
                                  ? context.l10n.noBarcodeAssigned
                                  : p.barcode,
                              style: TextStyle(
                                color: context.stockMuted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: qty <= 0
                      ? null
                      : () => open(SalePage(store: store, initialProduct: p)),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: Text(context.l10n.recordASale),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => open(
                          AdjustmentPage(
                            store: store,
                            product: p,
                            receiving: true,
                          ),
                        ),
                        icon: const Icon(Icons.add, size: 18),
                        label: Text(context.l10n.receive),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            open(AdjustmentPage(store: store, product: p)),
                        icon: const Icon(Icons.tune, size: 18),
                        label: Text(context.l10n.adjust),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  context.l10n.movementHistory,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                ...store.movements.reversed
                    .where((m) => m.productId == id)
                    .map((m) => MovementTile(movement: m, store: store)),
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: handleDelete,
                  icon: Icon(Icons.delete_outline, color: context.stockRust),
                  label: Text(
                    context.l10n.deleteItem,
                    style: TextStyle(color: context.stockRust),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      );
    },
  );
}
