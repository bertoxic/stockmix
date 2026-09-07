import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'design.dart';
import 'invoice_page.dart';
import 'pages.dart';
import 'scanner_page.dart';
import 'stock_store.dart';

class SalePage extends StatefulWidget {
  final StockStore store;
  final Product? initialProduct;
  final Map<String, int>? initialCart;
  const SalePage({
    super.key,
    required this.store,
    this.initialProduct,
    this.initialCart,
  });
  @override
  State<SalePage> createState() => _SalePageState();
}

class _SalePageState extends State<SalePage> {
  final cart = <String, int>{};
  final note = TextEditingController();
  String query = '';
  bool saving = false;
  StockStore get store => widget.store;

  List<Product> get _filteredProducts {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return store.products.reversed.take(4).toList();
    }
    return store.products
        .where((p) => '${p.name} ${p.barcode}'.toLowerCase().contains(q))
        .take(12)
        .toList();
  }
  @override
  void initState() {
    super.initState();
    if (widget.initialCart != null) cart.addAll(widget.initialCart!);
    if (widget.initialProduct != null) {
      cart[widget.initialProduct!.id] =
          (cart[widget.initialProduct!.id] ?? 0) + 1;
    }
  }

  @override
  void dispose() {
    note.dispose();
    super.dispose();
  }

  void add(Product p) {
    if (store.count != null &&
        (store.count!['baseline'] as Map).containsKey(p.id)) {
      showMessage(
        context,
        '${p.name} is currently in an active stock count and cannot be sold until the count is completed.',
      );
      return;
    }
    if ((cart[p.id] ?? 0) >= store.stock(p)) {
      showMessage(
        context,
        'All available units of this item are already in the sale.',
      );
      return;
    }
    setState(() => cart[p.id] = (cart[p.id] ?? 0) + 1);
  }

  Future<void> scan() async {
    final updated = await Navigator.push<Map<String, int>>(
      context,
      MaterialPageRoute(
        builder: (_) => ScannerPage(
          store: store,
          initialCart: cart,
          onCartChanged: (liveCart) {
            if (mounted) {
              setState(() {
                cart.clear();
                cart.addAll(liveCart);
              });
            }
          },
          mode: ScannerMode.multiItem,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        cart.clear();
        cart.addAll(updated);
      });
    }
  }

  int get total => cart.entries.fold(
    0,
    (n, entry) => n + store.product(entry.key).price * entry.value,
  );

  Future<void> checkout() async {
    final accepted = await confirm(
      context,
      'Record cash received?',
      'Confirm you received ${money(store, total)}. This will save the sale and deduct ${cart.values.fold(0, (a, b) => a + b)} units from stock.',
      action: 'Cash received',
    );
    if (!accepted || !mounted) return;
    setState(() => saving = true);
    try {
      final soldCart = Map<String, int>.from(cart);
      final recordedTotal = total;
      final saleTime = DateTime.now();
      final receiptRef = await store.checkout(soldCart, note.text);
      if (!mounted) return;

      setState(() {
        cart.clear();
        note.clear();
      });

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_outline,
            size: 48,
            color: Color(0xFF737638),
          ),
          title: const Text('Sale recorded.'),
          content: Text(
            '${money(store, recordedTotal)} saved on this device. Your stock is up to date.',
          ),
          actions: [
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReceiptInvoicePage.fromCart(
                      store: store,
                      reference: receiptRef,
                      cart: soldCart,
                      total: recordedTotal,
                      date: saleTime,
                      note: note.text,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('Share receipt'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Next sale'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> _holdCurrentSale() async {
    if (cart.isEmpty) return;
    try {
      await store.holdSale(cart, note: note.text);
      if (mounted) {
        showMessage(context, 'Sale held. You can resume it anytime from Home or Sales.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  Future<void> _discardHeldSale(String id) async {
    try {
      await store.deleteHeldSale(id);
      if (mounted) {
        setState(() {});
        showMessage(context, 'Held sale discarded.');
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (_, _) => PopScope(
      canPop: cart.isEmpty || saving,
    onPopInvokedWithResult: (didPop, result) async {
      if (didPop || cart.isEmpty) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Leave unfinished sale?'),
          content: const Text(
            'You have items in this sale. Would you like to hold this sale so you can resume it later, or discard it?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancel'),
              child: const Text('Stay'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: const Text('Discard', style: TextStyle(color: rust)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'hold'),
              child: const Text('Hold sale'),
            ),
          ],
        ),
      );
      if (choice == 'hold') {
        await _holdCurrentSale();
      } else if (choice == 'discard') {
        if (context.mounted) {
          setState(() => cart.clear());
          Navigator.pop(context);
        }
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('New sale'),
        actions: [
          if (cart.isNotEmpty)
            TextButton.icon(
              onPressed: _holdCurrentSale,
              icon: const Icon(Icons.pause_circle_outline, size: 18),
              label: const Text('Hold'),
            ),
          IconButton(
            onPressed: scan,
            tooltip: 'Scan item into sale',
            icon: const Icon(Icons.qr_code_scanner),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Eyebrow('The everyday checkout'),
              const SizedBox(height: 10),
              Text(
                'A good find.\nA simple sale.',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              if (store.heldSales.isNotEmpty) ...[
                const SizedBox(height: 16),
                Surface(
                  color: linen,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.pause_circle_outline, size: 18, color: plum),
                          const SizedBox(width: 8),
                          Text(
                            '${store.heldSales.length} held ${store.heldSales.length == 1 ? 'sale' : 'sales'} waiting',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      for (final held in store.heldSales) ...[
                        Builder(builder: (ctx) {
                          final hCart = Map<String, int>.from(held['cart'] as Map);
                          final itemCount = hCart.values.fold(0, (a, b) => a + b);
                          final hTotal = hCart.entries.fold(
                            0,
                            (sum, e) => sum + (store.product(e.key).price * e.value),
                          );
                          final timeStr = DateFormat('h:mm a').format(
                            DateTime.parse(held['heldAt'] as String).toLocal(),
                          );
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '$itemCount items · ${money(store, hTotal)} ($timeStr)',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () async {
                                    final resumed = await store.resumeSale(held['id'] as String);
                                    if (resumed != null && mounted) {
                                      setState(() {
                                        cart.addAll(resumed);
                                      });
                                    }
                                  },
                                  child: const Text('Resume'),
                                ),
                                IconButton(
                                  tooltip: 'Discard held sale',
                                  icon: const Icon(Icons.close, size: 16, color: muted),
                                  onPressed: () => _discardHeldSale(held['id'] as String),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your sale',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Tag(
                    cart.isEmpty
                        ? '0 items'
                        : '${cart.values.fold(0, (a, b) => a + b)} items · ${money(store, total)}',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (cart.isEmpty)
                const Text(
                  'Tap an item below or scan a barcode to add to this sale.',
                  style: TextStyle(color: muted, fontSize: 12),
                )
              else
                ...cart.entries.map((entry) {
                  final p = store.product(entry.key);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Surface(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          ProductImage(p, size: 46),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${money(store, p.price)} each · ${money(store, p.price * entry.value)}',
                                  style: const TextStyle(
                                    color: muted,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Remove one ${p.name}',
                            onPressed: () => setState(() {
                              if (entry.value == 1) {
                                cart.remove(entry.key);
                              } else {
                                cart[entry.key] = entry.value - 1;
                              }
                            }),
                            icon: const Icon(
                              Icons.remove_circle_outline,
                              size: 22,
                            ),
                          ),
                          Text(
                            '${entry.value}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Add one ${p.name}',
                            onPressed: () => add(p),
                            icon: const Icon(
                              Icons.add_circle_outline,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 24),
              TextField(
                onChanged: (v) => setState(() => query = v),
                decoration: InputDecoration(
                  hintText: 'Search items to add…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                    onPressed: scan,
                    tooltip: 'Scan item',
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (store.products.isEmpty)
                const EmptyState(
                  icon: Icons.shopping_bag_outlined,
                  title: 'Add products first',
                  subtitle:
                      'Your inventory items will appear here, ready to sell.',
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    query.trim().isEmpty
                        ? 'Recent items'
                        : 'Matching items (${_filteredProducts.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: muted,
                    ),
                  ),
                ),
                if (_filteredProducts.isEmpty)
                  Surface(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'No items match "$query"',
                        style: const TextStyle(color: muted, fontSize: 13),
                      ),
                    ),
                  )
                else
                  Surface(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 13,
                      vertical: 5,
                    ),
                    child: Column(
                      children: [
                        for (final p in _filteredProducts)
                          Builder(
                            builder: (context) {
                              final isCountLocked = store.count != null &&
                                  (store.count!['baseline'] as Map)
                                      .containsKey(p.id);
                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                leading: ProductImage(p, size: 44),
                                title: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        p.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                    if (isCountLocked)
                                      const Tag('Counting', color: avocado),
                                  ],
                                ),
                                subtitle: Text(
                                  isCountLocked
                                      ? 'Locked in active count'
                                      : '${money(store, p.price)}  ·  ${store.stock(p)} available',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isCountLocked ? rust : muted,
                                  ),
                                ),
                                trailing: IconButton.filledTonal(
                                  tooltip: isCountLocked
                                      ? 'Locked in active count'
                                      : 'Add ${p.name}',
                                  style: IconButton.styleFrom(
                                      backgroundColor: linen),
                                  onPressed: store.stock(p) <= 0 || isCountLocked
                                      ? null
                                      : () => add(p),
                                  icon: const Icon(Icons.add, size: 18),
                                ),
                                onTap: store.stock(p) <= 0 || isCountLocked
                                    ? null
                                    : () => add(p),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 24),
              TextField(
                controller: note,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Sale note (optional)',
                  hintText: 'Customer name, receipt reference…',
                ),
              ),
              const SizedBox(height: 18),
              Surface(
                color: avocado,
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Total',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      money(store, total),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Cash recording only. Prices are final; no additional tax or discounts are applied.',
                style: TextStyle(fontSize: 11, color: muted, height: 1.5),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: saving || cart.isEmpty ? null : checkout,
                icon: const Icon(Icons.check),
                label: Text(saving ? 'Saving…' : 'Record cash sale'),
              ),
              const SizedBox(height: 15),
            ],
          ),
        ),
      ),
    ),
  ),
);
}

class CountPage extends StatefulWidget {
  final StockStore store;
  const CountPage({super.key, required this.store});
  @override
  State<CountPage> createState() => _CountPageState();
}

class _CountPageState extends State<CountPage> {
  StockStore get store => widget.store;
  bool review = false;
  String selectedScope = 'All items';

  List<Product> get _scopedProducts {
    if (selectedScope == 'All items') return store.products;
    return store.products
        .where((p) => p.category.toLowerCase() == selectedScope.toLowerCase())
        .toList();
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  Future<void> enter(Product p) async {
    final values = store.count!['values'] as Map;
    final c = TextEditingController(text: values[p.id]?.toString() ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.name),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Actual quantity on the shelf',
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Save count'),
          ),
        ],
      ),
    );
    if (result != null) {
      final qty = int.tryParse(result);
      if (qty == null || qty < 0 || qty > 100000000) {
        if (mounted) {
          showMessage(context, 'Enter a whole quantity, zero or more.');
        }
      } else {
        await run(() => store.setCount(p.id, qty));
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    c.dispose();
  }

  Future<void> scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScannerPage()),
    );
    if (code == null || !mounted) return;
    final p = store.lookup(code);
    if (p == null || !(store.count!['baseline'] as Map).containsKey(p.id)) {
      showMessage(context, 'This item is not in the current count.');
      return;
    }
    await enter(p);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: store,
    builder: (context, _) {
      final count = store.count;
      final baseline = count?['baseline'] as Map? ?? {};
      final values = count?['values'] as Map? ?? {};
      final scope = (count?['scope'] as String?) ?? 'All items';
      return Scaffold(
        appBar: AppBar(
          title: Text(review ? 'Review stock count' : 'Count your stock'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Eyebrow('A place for every piece'),
                const SizedBox(height: 12),
                Text(
                  count == null
                      ? 'A fresh look\nat what’s on hand.'
                      : review
                      ? 'A moment to\ncheck the difference.'
                      : 'One shelf\nat a time.',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 18),
                if (count == null) ...[
                  Surface(
                    color: linen,
                    padding: const EdgeInsets.all(16),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.storefront_outlined, color: plum, size: 22),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Counting during business hours',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Only the items included in this count will have their sales and stock adjustments locked. Uncounted items remain fully available to sell at the checkout.',
                                style: TextStyle(
                                  color: muted,
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (store.categories.isNotEmpty) ...[
                    DropdownButtonFormField<String>(
                      initialValue: selectedScope,
                      decoration: const InputDecoration(
                        labelText: 'Count scope',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'All items',
                          child: Text('All items (${store.products.length})'),
                        ),
                        for (final cat in store.categories)
                          DropdownMenuItem(
                            value: cat,
                            child: Text(
                              '$cat (${store.products.where((p) => p.category.toLowerCase() == cat.toLowerCase()).length})',
                            ),
                          ),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => selectedScope = val);
                      },
                    ),
                    const SizedBox(height: 18),
                  ],
                  Surface(
                    child: Column(
                      children: [
                        const Icon(
                          Icons.fact_check_outlined,
                          size: 65,
                          color: cement,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '${_scopedProducts.length} items to count',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          selectedScope == 'All items'
                              ? 'Full store inventory count. Progress saves automatically.'
                              : 'Category count: $selectedScope. Progress saves automatically.',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  FilledButton(
                    onPressed: _scopedProducts.isEmpty || store.busy
                        ? null
                        : () {
                            setState(() => review = false);
                            run(() => store.startCount(
                              category: selectedScope == 'All items' ? null : selectedScope,
                            ));
                          },
                    child: Text(
                      selectedScope == 'All items'
                          ? 'Start full stock count'
                          : 'Start count for $selectedScope',
                    ),
                  ),
                ] else ...[
                  Surface(
                    color: avocado,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${values.length} of ${baseline.length} counted',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 19,
                              ),
                            ),
                            Tag(scope, color: paper),
                          ],
                        ),
                        const SizedBox(height: 14),
                        LinearProgressIndicator(
                          value: baseline.isEmpty
                              ? 0
                              : values.length / baseline.length,
                          color: plum,
                          backgroundColor: paper.withValues(alpha: .5),
                          borderRadius: BorderRadius.circular(8),
                          minHeight: 6,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          scope == 'All items'
                              ? 'Saved on this device · All stock changes paused'
                              : 'Saved on this device · Counted items locked · Other items sellable',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!review) ...[
                    OutlinedButton.icon(
                      onPressed: scan,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan an item to count'),
                    ),
                    const SizedBox(height: 18),
                  ],
                  for (final id in baseline.keys)
                    Builder(
                      builder: (context) {
                        final p = store.product(id);
                        final value = values[id] as int?;
                        final variance = value == null
                            ? null
                            : value - (baseline[id] as int);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Material(
                            color: paper,
                            borderRadius: BorderRadius.circular(18),
                            child: ListTile(
                              onTap: () => enter(p),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              leading: ProductImage(p, size: 45),
                              title: Text(
                                p.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Text(
                                review
                                    ? 'Expected ${baseline[id]} · Counted ${value ?? '—'}'
                                    : 'Expected ${baseline[id]} ${p.unit}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: muted,
                                ),
                              ),
                              trailing: review
                                  ? Tag(
                                      variance == null
                                          ? 'Not counted'
                                          : variance == 0
                                          ? 'Matches'
                                          : '${variance > 0 ? '+' : ''}$variance',
                                      color: variance == 0
                                          ? const Color(0xFF62643B)
                                          : rust,
                                    )
                                  : Text(
                                      value?.toString() ?? 'Count',
                                      style: TextStyle(
                                        color: value == null ? muted : plum,
                                        fontWeight: FontWeight.w800,
                                        fontSize: value == null ? 12 : 22,
                                      ),
                                    ),
                            ),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: values.length != baseline.length || store.busy
                        ? null
                        : () async {
                            if (!review) {
                              setState(() => review = true);
                              return;
                            }
                            if (await confirm(
                              context,
                              'Post reviewed count?',
                              'Stock will be adjusted to these counted quantities. The reviewed snapshot will be kept in saved records.',
                              action: 'Post count',
                            )) {
                              await run(store.postCount);
                              if (context.mounted && store.count == null) {
                                setState(() => review = false);
                                showMessage(
                                  context,
                                  'Count posted. Your stock is up to date.',
                                );
                              }
                            }
                          },
                    child: Text(
                      review ? 'Post reviewed count' : 'Review differences',
                    ),
                  ),
                  if (values.length != baseline.length)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text(
                        'Count every item, including zeros, before reviewing.',
                        style: TextStyle(fontSize: 11, color: muted),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () async {
                      if (await confirm(
                        context,
                        'Cancel this count?',
                        'Saved count entries will be discarded. Inventory will stay unchanged.',
                        action: 'Cancel count',
                      )) {
                        await run(store.cancelCount);
                        if (mounted) setState(() => review = false);
                      }
                    },
                    child: const Text(
                      'Cancel count',
                      style: TextStyle(color: rust),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
