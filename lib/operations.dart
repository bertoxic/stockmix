import 'package:flutter/material.dart';
import 'design.dart';
import 'forms.dart';
import 'pages.dart';
import 'scanner_page.dart';
import 'sharing.dart';
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
  String? photo;
  bool saving = false;
  StockStore get store => widget.store;
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
      await store.checkout(Map.of(cart), note.text, photo: photo);
      if (!mounted) return;
      final recordedTotal = total;
      setState(() {
        cart.clear();
        note.clear();
        photo = null;
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
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        SharePage(store: store, initialDay: DateTime.now()),
                  ),
                );
              },
              child: const Text('Share day record'),
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

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: cart.isEmpty || saving,
    onPopInvokedWithResult: (didPop, result) async {
      if (!didPop &&
          await confirm(
            context,
            'Leave this sale?',
            'The uncompleted sale will be discarded. Stock has not changed.',
            action: 'Leave sale',
          )) {
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
              const SizedBox(height: 23),
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
              const SizedBox(height: 16),
              if (store.products.isEmpty)
                const EmptyState(
                  icon: Icons.shopping_bag_outlined,
                  title: 'Add products first',
                  subtitle:
                      'Your inventory items will appear here, ready to sell.',
                )
              else
                Surface(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 5,
                  ),
                  child: Column(
                    children: [
                      for (final p
                          in store.products
                              .where(
                                (p) => '${p.name} ${p.barcode}'
                                    .toLowerCase()
                                    .contains(query.toLowerCase()),
                              )
                              .take(12))
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                          ),
                          leading: ProductImage(p, size: 44),
                          title: Text(
                            p.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                          subtitle: Text(
                            '${money(store, p.price)}  ·  ${store.stock(p)} available',
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                          trailing: IconButton.filledTonal(
                            tooltip: 'Add ${p.name}',
                            style: IconButton.styleFrom(backgroundColor: linen),
                            onPressed: store.stock(p) <= 0
                                ? null
                                : () => add(p),
                            icon: const Icon(Icons.add, size: 18),
                          ),
                          onTap: store.stock(p) <= 0 ? null : () => add(p),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 25),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Your sale',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  Tag('${cart.values.fold(0, (a, b) => a + b)} items'),
                ],
              ),
              const SizedBox(height: 15),
              if (cart.isEmpty)
                const Text(
                  'Tap an item or scan a barcode to get started.',
                  style: TextStyle(color: muted, fontSize: 12),
                )
              else
                ...cart.entries.map((entry) {
                  final p = store.product(entry.key);
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Surface(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              Text(
                                money(store, p.price * entry.value),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Text(
                                '${money(store, p.price)} each',
                                style: const TextStyle(
                                  color: muted,
                                  fontSize: 11,
                                ),
                              ),
                              const Spacer(),
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
                                  size: 23,
                                ),
                              ),
                              Text(
                                '${entry.value}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Add one ${p.name}',
                                onPressed: () => add(p),
                                icon: const Icon(
                                  Icons.add_circle_outline,
                                  size: 23,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 24),
              TextField(
                controller: note,
                maxLength: 500,
                decoration: const InputDecoration(
                  labelText: 'Sale note (optional)',
                  hintText: 'Customer name, receipt reference…',
                ),
              ),
              const SizedBox(height: 15),
              PhotoInput(
                value: photo,
                onChanged: (v) => setState(() => photo = v),
              ),
              const SizedBox(height: 22),
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
                  const Text(
                    'Count every item, review any differences, then post a new stock adjustment. Sales and other stock changes pause while you count.',
                    style: TextStyle(color: muted, height: 1.6),
                  ),
                  const SizedBox(height: 25),
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
                          '${store.products.length} items to count',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Progress saves automatically on this device.',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 25),
                  FilledButton(
                    onPressed: store.products.isEmpty || store.busy
                        ? null
                        : () {
                            setState(() => review = false);
                            run(store.startCount);
                          },
                    child: const Text('Start full stock count'),
                  ),
                ] else ...[
                  Surface(
                    color: avocado,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${values.length} of ${baseline.length} counted',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 19,
                          ),
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
                        const Text(
                          'Saved on this device · Stock changes paused',
                          style: TextStyle(fontSize: 11),
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
