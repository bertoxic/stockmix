import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'backup_page.dart';
import 'design.dart';
import 'forms.dart';
import 'invoice_page.dart';
import 'operations.dart';
import 'reorder_page.dart';
import 'scanner_page.dart';
import 'sharing.dart';
import 'stock_store.dart';
import 'qr_stream/qr_stream_receiver_page.dart';

String money(StockStore store, int cents) =>
    NumberFormat.simpleCurrency(name: store.currency).format(cents / 100);

class StockShell extends StatefulWidget {
  final StockStore store;
  const StockShell({super.key, required this.store});
  @override
  State<StockShell> createState() => _StockShellState();
}

class _StockShellState extends State<StockShell> {
  int tab = 0;
  String search = '', category = 'All items';
  bool lowOnly = false;
  DateTime day = DateTime.now();
  int recordsMode = 0;
  int insightsDays = 7;
  StockStore get store => widget.store;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _showFirstTimeSetup() async {
    final name = TextEditingController(text: store.shop == 'My store' ? '' : store.shop);
    var currency = store.currency;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: avocado.withAlpha(60),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.storefront_outlined, color: plum, size: 22),
              ),
              const SizedBox(width: 12),
              const Text('Welcome to Stockmix', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Set up your store name and local currency. You can change this at any time in settings without affecting your product records.',
                  style: TextStyle(color: muted, fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: name,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Store or shop name',
                    hintText: 'e.g. Maya\'s Corner Grocery',
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: currency,
                  decoration: const InputDecoration(labelText: 'Store currency'),
                  items: const [
                    DropdownMenuItem(value: 'USD', child: Text('USD (\$) - US Dollar', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'EUR', child: Text('EUR (€) - Euro', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'GBP', child: Text('GBP (£) - British Pound', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'PHP', child: Text('PHP (₱) - Philippine Peso', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'INR', child: Text('INR (₹) - Indian Rupee', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'NGN', child: Text('NGN (₦) - Nigerian Naira', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'KES', child: Text('KES (KSh) - Kenyan Shilling', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'GHS', child: Text('GHS (GH₵) - Ghanaian Cedi', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'ZAR', child: Text('ZAR (R) - South African Rand', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'CAD', child: Text('CAD (\$) - Canadian Dollar', overflow: TextOverflow.ellipsis)),
                    DropdownMenuItem(value: 'AUD', child: Text('AUD (\$) - Australian Dollar', overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => update(() => currency = v!),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
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
  Future<void> scan() async {
    final resultCart = await Navigator.push<Map<String, int>>(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerPage(
          store: store,
          mode: ScannerMode.multiItem,
        ),
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
    setState(() => search = code);
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
                        30,
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
            setState(() => tab = 0);
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
        child: const Icon(Icons.layers_outlined, color: plum, size: 23),
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
    color: paper,
    padding: const EdgeInsets.all(24),
    child: SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          logo(),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.only(left: 47),
            child: Text(
              'A little more in order.',
              style: TextStyle(fontSize: 10, color: muted),
            ),
          ),
          const SizedBox(height: 50),
          const Eyebrow('Your workspace'),
          const SizedBox(height: 18),
          for (var i = 0; i < 4; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: tab == i ? linen : Colors.transparent,
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
                    color: tab == i ? plum : muted,
                    size: 21,
                  ),
                  title: Text(
                    ['Overview', 'Inventory', 'Day records', 'More'][i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: tab == i ? FontWeight.w800 : FontWeight.w500,
                    ),
                  ),
                  onTap: () => setState(() => tab = i),
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
                const Icon(Icons.offline_pin_outlined, color: muted, size: 23),
                const SizedBox(height: 10),
                const Text(
                  'Your shop. In your pocket.',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                const SizedBox(height: 7),
                const Text(
                  'Work offline. Share when you’re ready.',
                  style: TextStyle(color: muted, fontSize: 11, height: 1.6),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          const Text(
            'STOCKMIX  /  01',
            style: TextStyle(fontSize: 9, letterSpacing: 2, color: muted),
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
                const Icon(Icons.storefront_outlined, size: 17, color: muted),
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
      const Tag('On this device', color: Color(0xFF62643B)),
      const SizedBox(width: 10),
      InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: () => setState(() => tab = 3),
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
    ],
  );
  Widget bottomNav() => Container(
    decoration: const BoxDecoration(
      color: paper,
      border: Border(top: BorderSide(color: line)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
        child: Row(
          children: [
            navItem(0, Icons.grid_view_rounded, 'Home'),
            navItem(1, Icons.inventory_2_outlined, 'Stock'),
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
                    child: const Icon(Icons.qr_code_scanner, size: 27),
                  ),
                ),
              ),
            ),
            navItem(2, Icons.receipt_long_outlined, 'Records'),
            navItem(3, Icons.tune_rounded, 'More'),
          ],
        ),
      ),
    ),
  );
  Widget navItem(int value, IconData icon, String label) => Expanded(
    child: InkWell(
      onTap: () => setState(() => tab = value),
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 23, color: tab == value ? plum : cement),
            const SizedBox(height: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: tab == value ? FontWeight.w800 : FontWeight.w500,
                color: tab == value ? plum : muted,
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
              const Expanded(
                child: Eyebrow('Today’s sales', color: Color(0xFFCCC5CB)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.circle, size: 6, color: avocado),
                    SizedBox(width: 6),
                    Text(
                      'TODAY',
                      style: TextStyle(
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
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              money(store, store.revenue(today)),
              style: const TextStyle(
                color: paper,
                fontSize: 43,
                fontWeight: FontWeight.w700,
                letterSpacing: -2,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$transactions ${transactions == 1 ? 'sale' : 'sales'} recorded  ·  ${sales.fold(0, (n, m) => n - m.delta)} items sold',
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
              const Text(
                'LAST 7 DAYS',
                style: TextStyle(
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
          'Stock on hand',
          '${store.units}',
          '${store.products.length} unique items',
          avocado,
        ),
        const SizedBox(height: 12),
        stat(
          Icons.trending_down_rounded,
          'Need a little attention',
          '${store.low.length}',
          store.low.isEmpty ? 'All stocked up' : 'items running low · Tap to reorder',
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
                  child: const Icon(Icons.storefront_outlined, color: plum, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Set your store currency',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Store currency is currently ${store.currency}. Set your preferred store currency.',
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _showFirstTimeSetup,
                  child: const Text('Configure'),
                ),
              ],
            ),
          ),
        ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'A good day to\nkeep things in order.',
                  style: Theme.of(
                    context,
                  ).textTheme.headlineLarge?.copyWith(height: 1.12),
                ),
                const SizedBox(height: 12),
                Text(
                  DateFormat('EEEE, d MMMM').format(today),
                  style: const TextStyle(color: muted, fontSize: 13),
                ),
              ],
            ),
          ),
          if (wide)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Icon(Icons.wb_sunny_outlined, color: maple, size: 44),
            ),
        ],
      ),
      const SizedBox(height: 25),
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
                'On hand',
                '${store.units}',
                Icons.inventory_2_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: compactStat(
                'Low stock',
                '${store.low.length}',
                Icons.trending_down_rounded,
                onTap: () => open(ReorderPage(store: store)),
              ),
            ),
          ],
        ),
      ],
      section('Quick actions'),
      Row(
        children: [
          quickAction(
            'New sale',
            Icons.add_shopping_cart_outlined,
            avocado,
            () => open(SalePage(store: store)),
          ),
          const SizedBox(width: 12),
          quickAction(
            'Add item',
            Icons.add_box_outlined,
            paper,
            () => open(ProductForm(store: store)),
          ),
          const SizedBox(width: 12),
          quickAction(
            'Count stock',
            Icons.fact_check_outlined,
            paper,
            () => open(CountPage(store: store)),
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
                  'Stock count in progress (${store.count?['scope'] ?? 'All items'}). Counted items are paused.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: () => open(CountPage(store: store)),
                child: const Text('Resume'),
              ),
            ],
          ),
        ),
      ],
      section(
        'Needs restocking',
        action: store.low.isNotEmpty
            ? 'Shopping list (${store.low.length}) →'
            : 'View inventory →',
        onTap: () => store.low.isNotEmpty
            ? open(ReorderPage(store: store))
            : setState(() => tab = 1),
      ),
      if (store.products.isEmpty)
        Surface(
          child: EmptyState(
            icon: Icons.inventory_2_outlined,
            title: 'Your stock book starts here.',
            subtitle:
                'Add your first item, or import a stock file from another Stockmix user.',
            action: FilledButton.icon(
              onPressed: () => open(ProductForm(store: store)),
              icon: const Icon(Icons.add),
              label: const Text('Add your first item'),
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
        'The latest in your shop',
        action: 'View all →',
        onTap: () => setState(() => tab = 2),
      ),
      if (store.movements.isEmpty)
        const Text(
          'Your stock changes and sales will appear here.',
          style: TextStyle(color: muted),
        )
      else
        ...store.movements.reversed
            .take(3)
            .map((m) => MovementTile(movement: m, store: store)),
      const SizedBox(height: 25),
      const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline, size: 12, color: cement),
          SizedBox(width: 6),
          Text(
            'Saved on your device. Ready when you are.',
            style: TextStyle(color: muted, fontSize: 10),
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
                Text(label, style: const TextStyle(fontSize: 11, color: muted)),
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
                        style: const TextStyle(fontSize: 10, color: muted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right, color: muted, size: 20),
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

  Widget compactStat(String label, String value, IconData icon, {VoidCallback? onTap}) {
    final content = Surface(
      padding: const EdgeInsets.all(17),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: muted, size: 16),
              const SizedBox(width: 7),
              Expanded(child: Text(label, style: const TextStyle(color: muted, fontSize: 11))),
              if (onTap != null)
                const Icon(Icons.chevron_right, color: muted, size: 14),
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
      color: color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: action,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 21, horizontal: 4),
          child: Column(
            children: [
              Icon(icon, size: 25),
              const SizedBox(height: 10),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
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
                  '${p.category}  ·  ${p.barcode.isEmpty ? 'No barcode' : p.barcode}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: muted),
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
                '${store.stock(p)} ${p.unit} left',
                style: TextStyle(
                  color: store.stock(p) <= p.threshold ? rust : muted,
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
      ...store.products.map((p) => p.category).toSet(),
    ];
    final filtered = store.products
        .where(
          (p) =>
              (category == 'All items' || p.category == category) &&
              (!lowOnly || store.stock(p) <= p.threshold) &&
              '${p.name} ${p.barcode} ${p.category}'.toLowerCase().contains(
                search.toLowerCase(),
              ),
        )
        .toList();
    return [
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your stock,\nat a glance.',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  '${store.products.length} items · ${store.units} units in your shop',
                  style: const TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
          IconButton.filled(
            onPressed: () => open(ProductForm(store: store)),
            tooltip: 'Add item',
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
          hintText: 'Find an item, price or barcode…',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: IconButton(
            onPressed: scanToFind,
            tooltip: 'Scan to find',
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ),
      ),
      const SizedBox(height: 17),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final c in categories)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(
                    c,
                    style: TextStyle(
                      color: category == c ? paper : muted,
                      fontSize: 12,
                    ),
                  ),
                  selected: category == c,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => category = c),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          Text(
            '${filtered.length} ITEMS',
            style: const TextStyle(
              fontSize: 10,
              color: muted,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w700,
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChip(
                label: const Text('Low stock', style: TextStyle(fontSize: 11)),
                selected: lowOnly,
                selectedColor: avocado,
                onSelected: (v) => setState(() => lowOnly = v),
              ),
              if (store.low.isNotEmpty)
                ActionChip(
                  avatar: const Icon(Icons.playlist_add_check_outlined, size: 16),
                  label: Text('Shopping list (${store.low.length})', style: const TextStyle(fontSize: 11)),
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
                ? 'A fresh start.'
                : 'No matching items',
            subtitle: store.products.isEmpty
                ? 'Add your first item to start keeping stock.'
                : 'Try another name or change the filters.',
            action: store.products.isEmpty
                ? FilledButton(
                    onPressed: () => open(ProductForm(store: store)),
                    child: const Text('Add item'),
                  )
                : null,
          ),
        )
      else if (wide)
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: filtered
              .map(
                (p) => SizedBox(
                  width:
                      (MediaQuery.sizeOf(context).width - 228 - 80 - 32).clamp(
                        0,
                        988,
                      ) /
                      3,
                  child: Material(
                    color: paper,
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
                                  const Tag('Low stock', color: rust),
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
                              style: const TextStyle(
                                fontSize: 11,
                                color: muted,
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
                                  '${store.stock(p)} ${p.unit}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: muted,
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
        )
      else
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 3),
          child: Column(
            children: [
              for (var i = 0; i < filtered.length; i++) ...[
                productRow(filtered[i]),
                if (i < filtered.length - 1) const Divider(),
              ],
            ],
          ),
        ),
      const SizedBox(height: 22),
      OutlinedButton.icon(
        onPressed: () => open(SharePage(store: store)),
        icon: const Icon(Icons.ios_share_outlined, size: 18),
        label: const Text('Export or share stock'),
      ),
    ];
  }

  List<Widget> records() {
    final entries = store.onDay(day).reversed.toList();
    return [
      Text(
        'Every day.\nAll accounted for.',
        style: Theme.of(context).textTheme.headlineLarge,
      ),
      const SizedBox(height: 10),
      const Text(
        'Your sales and stock changes, in one place.',
        style: TextStyle(color: muted, fontSize: 12),
      ),
      const SizedBox(height: 20),
      SegmentedButton<int>(
        segments: const [
          ButtonSegment(
            value: 0,
            label: Text('Daily activity'),
            icon: Icon(Icons.receipt_long_outlined, size: 18),
          ),
          ButtonSegment(
            value: 1,
            label: Text('Business summary'),
            icon: Icon(Icons.insights_outlined, size: 18),
          ),
        ],
        selected: {recordsMode},
        onSelectionChanged: (s) => setState(() => recordsMode = s.first),
      ),
      const SizedBox(height: 20),
      if (recordsMode == 0) ...[
        Surface(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous day',
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
                tooltip: 'Next day',
                onPressed: dayKey(day) == dayKey(DateTime.now())
                    ? null
                    : () =>
                          setState(() => day = day.add(const Duration(days: 1))),
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
                    const Eyebrow('Sales recorded', color: plum),
                    const SizedBox(height: 10),
                    Text(
                      money(store, store.revenue(day)),
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${entries.length}',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Text('stock movements', style: TextStyle(fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
        section('The day’s activity'),
        if (entries.isEmpty)
          const Surface(
            child: EmptyState(
              icon: Icons.receipt_long_outlined,
              title: 'A quiet page so far.',
              subtitle:
                  'Sales, receipts, and stock adjustments for this day will appear here.',
            ),
          )
        else
          ...entries.map((m) => MovementTile(movement: m, store: store)),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => open(SharePage(store: store, initialDay: day)),
          icon: const Icon(Icons.ios_share_outlined, size: 19),
          label: const Text('Share or export this day'),
        ),
      ] else ...[
        Row(
          children: [
            Expanded(
              child: Text(
                'Performance overview',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 7, label: Text('7 days')),
                ButtonSegment(value: 30, label: Text('30 days')),
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
                            const Eyebrow('Total sales', color: avocado),
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
                              '${summary['salesCount']} sales in $insightsDays days',
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
                            const Eyebrow('Est. gross profit', color: plum),
                            const SizedBox(height: 8),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                money(store, grossProfit),
                                style: const TextStyle(
                                  color: plum,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Revenue minus product costs',
                              style: TextStyle(color: plum, fontSize: 11),
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
                        const Icon(Icons.info_outline, size: 16, color: muted),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '$missingCost sales lacked a cost price. Estimated profit calculates using known costs.',
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                section('Top selling items'),
                if (topSellers.isEmpty)
                  const Surface(
                    child: EmptyState(
                      icon: Icons.trending_up,
                      title: 'No sales recorded yet',
                      subtitle:
                          'Sales in this period will rank your best-selling items here.',
                    ),
                  )
                else
                  Surface(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < topSellers.length; i++) ...[
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
                                    color: i == 0 ? avocado : linen,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: i == 0 ? plum : muted,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        topSellers[i]['name'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        '${topSellers[i]['quantity']} ${topSellers[i]['unit']} sold',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  money(store, topSellers[i]['revenue']),
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
                  ),
                const SizedBox(height: 24),
                section('Slow-moving items (14+ days)'),
                const Text(
                  'Items currently in stock with zero recorded sales in the last 14 days.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                const SizedBox(height: 12),
                if (slowMovers.isEmpty)
                  const Surface(
                    child: EmptyState(
                      icon: Icons.check_circle_outline,
                      title: 'Healthy movement',
                      subtitle:
                          'No stagnant items found. Everything in stock has had sales recently!',
                    ),
                  )
                else
                  Surface(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < slowMovers.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.hourglass_empty_rounded,
                                  size: 20,
                                  color: muted,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        slowMovers[i]['name'],
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        '${slowMovers[i]['stock']} ${slowMovers[i]['unit']} in stock',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      money(store, slowMovers[i]['valuation']),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const Text(
                                      'tied in stock',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: muted,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ];
  }

  List<Widget> more() => [
    Text(
      'Make it\nyour own.',
      style: Theme.of(context).textTheme.headlineLarge,
    ),
    const SizedBox(height: 12),
    const Text(
      'A few good tools for a well-run shop.',
      style: TextStyle(color: muted),
    ),
    const SizedBox(height: 24),
    Surface(
      child: Column(
        children: [
          menu(
            Icons.storefront_outlined,
            'Store settings',
            '${store.shop} · ${store.currency}',
            settings,
          ),
          menu(
            Icons.backup_outlined,
            'Full backup & restore',
            store.lastBackupAt == null
                ? 'Never backed up · Tap to protect data'
                : 'Last backed up: ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.parse(store.lastBackupAt!).toLocal())}',
            () => open(BackupRestorePage(store: store)),
          ),
          menu(
            Icons.playlist_add_check_outlined,
            'Shopping & reorder list',
            store.low.isEmpty
                ? 'All stocked up · No low stock items'
                : '${store.low.length} items running low · Tap to order',
            () => open(ReorderPage(store: store)),
          ),
          menu(
            Icons.swap_horiz_rounded,
            'Share & export',
            'Send stock or day records to another user',
            () => open(SharePage(store: store)),
          ),
          menu(
            Icons.qr_code_scanner_rounded,
            'Stream scanner',
            'Receive entries offline via animated QR stream',
            () => open(QrStreamReceiverPage(store: store)),
          ),
          menu(
            Icons.move_to_inbox_outlined,
            'Import a file',
            'Review records or add new stock items',
            () => open(SharePage(store: store, startImport: true)),
          ),
          menu(
            Icons.fact_check_outlined,
            'Stock count',
            store.count == null
                ? 'Count, review differences, and post'
                : 'Continue your saved count',
            () => open(CountPage(store: store)),
          ),
          menu(
            Icons.folder_open_outlined,
            'Received & saved records',
            '${store.received.length} imported files and completed counts',
            () => open(ReceivedPage(store: store)),
          ),
        ],
      ),
    ),
    const SizedBox(height: 20),
    Surface(
      color: plum,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('A stock book that goes with you', color: avocado),
          const SizedBox(height: 15),
          const Text(
            'No signal?\nNo interruption.',
            style: TextStyle(
              color: paper,
              fontSize: 25,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Items, photos, sales, and counts are saved on this device. Export regularly to keep a copy somewhere safe.',
            style: TextStyle(
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
            'Explore with sample items?',
            'This adds six clearly marked sample products and a sample sale. Use a separate empty store for real records.',
            action: 'Add sample data',
          )) {
            try {
              await store.loadDemo();
            } catch (e) {
              if (mounted) showMessage(context, friendlyError(e));
            }
          }
        },
        child: const Text('Explore with sample items'),
      ),
    ],
    const SizedBox(height: 30),
    const Center(child: Eyebrow('Stockmix · Made for the everyday')),
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
        color: linen,
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
      child: Text(subtitle, style: const TextStyle(color: muted, fontSize: 11)),
    ),
    trailing: const Icon(Icons.chevron_right, color: cement, size: 19),
    onTap: action,
  );
  Future<void> settings() async {
    final name = TextEditingController(text: store.shop);
    var currency = store.currency;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: const Text('Your store'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Store name'),
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<String>(
                initialValue: currency,
                decoration: const InputDecoration(labelText: 'Currency'),
                items:
                    [
                          'USD',
                          'EUR',
                          'GBP',
                          'PHP',
                          'INR',
                          'NGN',
                          'KES',
                          'GHS',
                          'ZAR',
                          'CAD',
                          'AUD',
                        ]
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                onChanged: (v) => update(() => currency = v!),
              ),
              const SizedBox(height: 10),
              const Text(
                'Changing currency updates the symbol across items, receipts, and reports. No exchange rate conversion is applied.',
                style: TextStyle(color: muted, fontSize: 11),
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
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (result == true) {
      try {
        await store.settings(name.text, currency);
      } catch (e) {
        if (mounted) showMessage(context, friendlyError(e));
      }
    }
    // Dialog route transitions can still read the controller until unmounted.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    name.dispose();
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
        color: paper,
        borderRadius: BorderRadius.circular(18),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 15,
            vertical: 7,
          ),
          leading: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: (m.type == 'Sale' ? avocado : cement).withValues(
                alpha: .18,
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              m.type == 'Sale'
                  ? Icons.shopping_bag_outlined
                  : m.delta > 0
                  ? Icons.south_west
                  : Icons.north_east,
              size: 21,
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
              style: const TextStyle(fontSize: 10, color: muted),
            ),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                m.type == 'Sale'
                    ? money(store, -m.delta * m.price)
                    : '${m.delta > 0 ? '+' : ''}${m.delta}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
              if (m.type == 'Sale')
                Text(
                  '${-m.delta} sold',
                  style: const TextStyle(fontSize: 10, color: muted),
                ),
            ],
          ),
          onTap: () => showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (context) => SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 30),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Tag(m.type),
                    const SizedBox(height: 16),
                    Text(
                      m.name,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Quantity change: ${m.delta > 0 ? '+' : ''}${m.delta}',
                    ),
                    const SizedBox(height: 8),
                    Text('Unit price: ${money(store, m.price)}'),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat(
                        'd MMM yyyy · h:mm a',
                      ).format(DateTime.parse(m.at).toLocal()),
                      style: const TextStyle(color: muted),
                    ),
                    const SizedBox(height: 16),
                    Text(m.note, style: const TextStyle(height: 1.5)),
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
                    const SizedBox(height: 18),
                    SelectableText(
                      'Reference: ${m.reference}',
                      style: const TextStyle(fontSize: 10, color: muted),
                    ),
                    if (m.type == 'Sale') ...[
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ReceiptInvoicePage.fromMovement(
                                      store: store,
                                      movement: m,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.receipt_long_outlined, size: 18),
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
                              onPressed: () async {
                                Navigator.pop(context);
                                _showReturnDialog(context);
                              },
                              icon: const Icon(Icons.replay_outlined, size: 18),
                              label: const Text('Process return'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showReturnDialog(BuildContext context) async {
    final m = movement;
    final maxReturn = -m.delta;
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
                'Original purchase: $maxReturn units at ${money(store, m.price)} each.',
                style: const TextStyle(fontSize: 12, color: muted),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Quantity to return', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: returnQty > 1 ? () => setDialogState(() => returnQty--) : null,
                      ),
                      Text('$returnQty', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: returnQty < maxReturn ? () => setDialogState(() => returnQty++) : null,
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 18),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Return item to store shelf', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  returnToStock ? 'Stock will increase by $returnQty' : 'Item is damaged or discarded; stock unchanged',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
                value: returnToStock,
                onChanged: (val) => setDialogState(() => returnToStock = val),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Refund customer cash', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text(
                  refundMoney ? 'Refund total: ${money(store, m.price * returnQty)}' : 'Customer exchange or store credit',
                  style: const TextStyle(fontSize: 11, color: muted),
                ),
                value: refundMoney,
                onChanged: (val) => setDialogState(() => refundMoney = val),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: noteController,
                decoration: const InputDecoration(labelText: 'Reason for return'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
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
          appBar: AppBar(title: const Text('Item details')),
          body: const Center(child: Text('This item has been removed.')),
        );
      }
      final qty = store.stock(p);
      void open(Widget page) =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => page));

      Future<void> handleDelete() async {
        if (store.count != null) {
          showMessage(context, 'Finish or cancel the active stock count first.');
          return;
        }
        if (qty > 0) {
          showMessage(
            context,
            'Cannot delete: You still have $qty ${p.unit} in stock. Please adjust or sell stock to 0 first.',
          );
          return;
        }
        final confirmed = await confirm(
          context,
          'Delete "${p.name}"?',
          'This will permanently remove this item and its records from your store.',
          action: 'Delete item',
        );
        if (!confirmed) return;
        try {
          await store.deleteProduct(p.id);
          if (context.mounted) {
            Navigator.pop(context);
            showMessage(context, '"${p.name}" deleted from your inventory.');
          }
        } catch (e) {
          if (context.mounted) showMessage(context, friendlyError(e));
        }
      }

      return Scaffold(
        appBar: AppBar(
          title: const Text('Item details'),
          actions: [
            IconButton(
              tooltip: 'Edit item',
              onPressed: () => open(ProductForm(store: store, product: p)),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Delete item',
              onPressed: handleDelete,
              icon: const Icon(Icons.delete_outline, color: rust),
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
                          ProductImage(p, size: 110),
                          const Spacer(),
                          Tag(
                            qty == 0
                                ? 'Out of stock'
                                : qty <= p.threshold
                                ? 'Running low'
                                : 'In stock',
                            color: qty <= p.threshold
                                ? rust
                                : const Color(0xFF62643B),
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
                                const Eyebrow('Selling price'),
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
                              const Eyebrow('Available'),
                              const SizedBox(height: 8),
                              Text(
                                '$qty ${p.unit}',
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
                        'Cost: ${money(store, p.cost)}  ·  Low-stock alert: ${p.threshold}',
                        style: const TextStyle(fontSize: 12, color: muted),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.qr_code, size: 20, color: muted),
                          const SizedBox(width: 8),
                          Expanded(
                            child: SelectableText(
                              p.barcode.isEmpty
                                  ? 'No barcode assigned'
                                  : p.barcode,
                              style: const TextStyle(
                                color: muted,
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
                  label: const Text('Record a sale'),
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
                        label: const Text('Receive'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            open(AdjustmentPage(store: store, product: p)),
                        icon: const Icon(Icons.tune, size: 18),
                        label: const Text('Adjust'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  'Item history',
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
                  icon: const Icon(Icons.delete_outline, color: rust),
                  label: const Text(
                    'Delete this item',
                    style: TextStyle(color: rust),
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
