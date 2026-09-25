import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:stockmix/core/theme/design.dart';
import 'package:stockmix/core/widgets/calculator.dart';
import 'package:stockmix/features/app/pages.dart';
import 'package:stockmix/features/sales/invoice_page.dart';
import 'package:stockmix/features/scanner/scanner_page.dart';
import 'package:stockmix/features/stock/stock_store.dart';
import 'package:stockmix/l10n/app_localizations.dart';

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
  late final SaleCart cart;
  final note = TextEditingController();
  String query = '';
  bool saving = false;
  int discount = 0;
  StockStore get store => widget.store;

  int _catalogDisplayLimit = 20;

  List<Product> get _allMatchingProducts {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) {
      return store.products.reversed.toList();
    }
    return store.products
        .where((p) => '${p.name} ${p.barcode}'.toLowerCase().contains(q))
        .toList();
  }

  List<Product> get _filteredProducts {
    final all = _allMatchingProducts;
    final limit = query.trim().isEmpty ? 4 : _catalogDisplayLimit;
    return all.take(limit).toList();
  }

  @override
  void initState() {
    super.initState();
    cart = SaleCart.fromLegacy(widget.initialCart, store);
    if (widget.initialProduct != null) {
      cart.add(widget.initialProduct!, widget.initialProduct!.defaultUnit);
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
        context.l10n.itemInActiveCountCannotSell(p.name),
      );
      return;
    }
    if (cart.baseQuantityFor(p.id) + p.defaultUnit.multiplier >
        store.stock(p)) {
      showMessage(
        context,
        context.l10n.allUnitsInSale,
      );
      return;
    }
    setState(() => cart.add(p, p.defaultUnit));
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
                cart.replaceWith(SaleCart.fromLegacy(liveCart, store));
              });
            }
          },
          mode: ScannerMode.multiItem,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        cart.replaceWith(SaleCart.fromLegacy(updated, store));
      });
    }
  }

  int get subtotal => cart.total;
  int get total => subtotal - discount;

  Future<int?> _promptDiscount() async {
    final amount = TextEditingController(
      text: discount == 0 ? '' : (discount / 100).toStringAsFixed(2),
    );
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.addDiscount),
        content: TextField(
          controller: amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: context.l10n.discountAmount,
            hintText: '0.00',
            helperText: context.l10n.helperDiscountCash,
          ),
        ),
        actions: [
          if (discount > 0)
            TextButton(
              onPressed: () => Navigator.pop(ctx, 0),
              child: Text(context.l10n.removeDiscount),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final parsed = double.tryParse(amount.text.trim());
              if (parsed == null || parsed < 0 || parsed * 100 > subtotal) {
                showMessage(
                  ctx,
                  context.l10n.enterAmountFromZeroTo(money(store, subtotal)),
                );
                return;
              }
              Navigator.pop(ctx, (parsed * 100).round());
            },
            child: Text(context.l10n.applyDiscount),
          ),
        ],
      ),
    );
    amount.dispose();
    return result;
  }

  Future<bool> _confirmCashReceived() async {
    var pendingDiscount = discount;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, update) => AlertDialog(
          title: Text(context.l10n.recordCashReceivedTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.recordCashReceivedMessage(
                  money(store, subtotal - pendingDiscount),
                  cart.totalBaseUnits,
                ),
              ),
              if (pendingDiscount > 0) ...[
                const SizedBox(height: 12),
                Text(
                  context.l10n.discountDeduction(money(store, pendingDiscount)),
                  style: TextStyle(color: context.stockMuted),
                ),
              ],
            ],
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                final value = await _promptDiscount();
                if (value != null) update(() => pendingDiscount = value);
              },
              icon: const Icon(Icons.sell_outlined, size: 18),
              label: Text(
                pendingDiscount == 0
                    ? context.l10n.addDiscount
                    : context.l10n.editDiscount,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.cashReceived),
            ),
          ],
        ),
      ),
    );
    if (accepted == true && mounted) setState(() => discount = pendingDiscount);
    return accepted == true;
  }

  Future<void> _cancelActiveCount() async {
    final scope = store.count?['scope'] ?? 'All items';
    final shouldCancel = await confirm(
      context,
      context.l10n.cancelActiveStockCountTitle,
      context.l10n.cancelActiveStockCountMessage(scope),
      action: context.l10n.cancelCountAction,
    );
    if (!shouldCancel) return;
    try {
      await store.cancelCount();
      if (mounted) {
        showMessage(
          context,
          context.l10n.stockCountCancelledSellMsg,
        );
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  Future<void> checkout() async {
    final accepted = await _confirmCashReceived();
    if (!accepted || !mounted) return;
    setState(() => saving = true);
    try {
      final soldCart = cart.copy();
      final recordedTotal = total;
      final recordedDiscount = discount;
      final recordedNote = note.text;
      final saleTime = DateTime.now();
      final receiptRef = await store.checkoutSale(
        soldCart,
        note.text,
        discount: discount,
      );
      if (!mounted) return;

      setState(() {
        cart.clear();
        note.clear();
        discount = 0;
      });

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(
            Icons.check_circle_outline,
            size: 48,
            color: Color(0xFF737638),
          ),
          title: Text(context.l10n.saleRecorded),
          content: Text(
            context.l10n.saleSavedOnDevice(money(store, recordedTotal)),
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
                      note: recordedNote,
                      discount: recordedDiscount,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: Text(context.l10n.shareReceipt),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(context.l10n.nextSale),
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
        showMessage(
          context,
          context.l10n.saleHeldMessage,
        );
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
        showMessage(context, context.l10n.heldSaleDiscarded);
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
            title: Text(context.l10n.leaveUnfinishedSaleTitle),
            content: Text(
              context.l10n.leaveUnfinishedSaleMessage,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'cancel'),
                child: Text(context.l10n.stay),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'discard'),
                child: Text(
                  context.l10n.discard,
                  style: TextStyle(color: context.stockRust),
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'hold'),
                child: Text(context.l10n.holdSale),
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
          title: Text(context.l10n.newSale),
          actions: [
            IconButton(
              onPressed: () => showCalculator(context),
              tooltip: context.l10n.calculator,
              icon: const Icon(Icons.calculate_outlined),
            ),
            if (cart.isNotEmpty)
              TextButton.icon(
                onPressed: _holdCurrentSale,
                icon: const Icon(Icons.pause_circle_outline, size: 18),
                label: Text(context.l10n.hold),
              ),
            IconButton(
              onPressed: scan,
              tooltip: context.l10n.scanItemIntoSale,
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
                Eyebrow(context.l10n.theEverydayCheckout),
                const SizedBox(height: 10),
                Text(
                  context.l10n.goodFindSimpleSale,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                if (store.count != null) ...[
                  const SizedBox(height: 16),
                  Surface(
                    color: context.stockRust.withValues(alpha: .1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.pause_circle_outline,
                              color: context.stockRust,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                context.l10n.someSalesPaused,
                                style: const TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          context.l10n.stockCountActiveSaleNotice(store.count?['scope'] ?? 'All items'),
                          style: TextStyle(
                            fontSize: 12,
                            color: context.stockMuted,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _cancelActiveCount,
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: Text(context.l10n.cancelActiveCount),
                        ),
                      ],
                    ),
                  ),
                ],
                if (store.heldSales.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Surface(
                    color: linen,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.pause_circle_outline,
                              size: 18,
                              color: context.stockInk,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              store.heldSales.length == 1
                                  ? context.l10n.heldSaleWaitingOne
                                  : context.l10n.heldSalesWaiting(store.heldSales.length),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        for (final held in store.heldSales) ...[
                          Builder(
                            builder: (ctx) {
                              final savedLines = held['lines'];
                              final hCart = savedLines is List
                                  ? SaleCart.fromJson(savedLines)
                                  : SaleCart.fromLegacy(
                                      Map<String, int>.from(
                                        held['cart'] as Map,
                                      ),
                                      store,
                                    );
                              final itemCount = hCart.totalBaseUnits;
                              final hTotal = hCart.total;
                              final timeStr = DateFormat('h:mm a').format(
                                DateTime.parse(
                                  held['heldAt'] as String,
                                ).toLocal(),
                              );
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '$itemCount ${context.l10n.units} · ${money(store, hTotal)} ($timeStr)',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () async {
                                        final resumed = await store
                                            .resumeSaleCart(
                                              held['id'] as String,
                                            );
                                        if (resumed != null && mounted) {
                                          setState(() {
                                            cart.replaceWith(resumed);
                                          });
                                        }
                                      },
                                      child: Text(context.l10n.resume),
                                    ),
                                    IconButton(
                                      tooltip: context.l10n.discard,
                                      icon: Icon(
                                        Icons.close,
                                        size: 16,
                                        color: context.stockMuted,
                                      ),
                                      onPressed: () => _discardHeldSale(
                                        held['id'] as String,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
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
                        context.l10n.yourSale,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    Tag(
                      cart.isEmpty
                          ? '0 ${context.l10n.items}'
                          : '${cart.totalBaseUnits} ${cart.totalBaseUnits == 1 ? context.l10n.unit : context.l10n.units} · ${money(store, total)}',
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (cart.isEmpty)
                  Text(
                    context.l10n.tapItemOrScanToAdd,
                    style: TextStyle(color: context.stockMuted, fontSize: 12),
                  )
                else
                  ...cart.lines.map((line) {
                    final p = store.product(line.productId);
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
                                    '${money(store, line.unitPrice)} / ${line.unitName} · ${money(store, line.total)}',
                                    style: TextStyle(
                                      color: context.stockMuted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: '${context.l10n.delete} ${p.name}',
                              onPressed: () => setState(() {
                                cart.removeOne(line);
                              }),
                              icon: const Icon(
                                Icons.remove_circle_outline,
                                size: 22,
                              ),
                            ),
                            Text(
                              '${line.quantity} ${line.unitName}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            IconButton(
                              tooltip: '${context.l10n.addItem} ${p.name}',
                              onPressed:
                                  cart.baseQuantityFor(p.id) +
                                          line.unitMultiplier >
                                      store.stock(p)
                                  ? null
                                  : () => setState(
                                      () => cart.add(
                                        p,
                                        SellingUnit(
                                          name: line.unitName,
                                          multiplier: line.unitMultiplier,
                                          price: line.unitPrice,
                                        ),
                                      ),
                                    ),
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
                  onChanged: (v) => setState(() {
                    query = v;
                    _catalogDisplayLimit = 20;
                  }),
                  decoration: InputDecoration(
                    hintText: context.l10n.searchItemsToAdd,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      onPressed: scan,
                      tooltip: context.l10n.scanItem,
                      icon: const Icon(Icons.qr_code_scanner),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                if (store.products.isEmpty)
                  EmptyState(
                    icon: Icons.shopping_bag_outlined,
                    title: context.l10n.addProductsFirst,
                    subtitle: context.l10n.inventoryItemsAppearHere,
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      query.trim().isEmpty
                          ? context.l10n.recentItems
                          : context.l10n.matchingItems(_allMatchingProducts.length),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                        color: context.stockMuted,
                      ),
                    ),
                  ),
                  if (_filteredProducts.isEmpty)
                    Surface(
                      padding: const EdgeInsets.all(16),
                      child: Center(
                        child: Text(
                          context.l10n.noItemsMatch(query),
                          style: TextStyle(
                            color: context.stockMuted,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  else ...[
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
                                final isCountLocked =
                                    store.count != null &&
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
                                        Tag(context.l10n.countingTag, color: avocado),
                                    ],
                                  ),
                                  subtitle: Text(
                                    isCountLocked
                                        ? context.l10n.lockedInActiveCount
                                        : '${money(store, p.price)}  ·  ${context.l10n.availableCount(store.stock(p))}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isCountLocked
                                          ? context.stockRust
                                          : context.stockMuted,
                                    ),
                                  ),
                                  trailing: IconButton.filledTonal(
                                    tooltip: isCountLocked
                                        ? context.l10n.lockedInActiveCount
                                        : '${context.l10n.addItem} ${p.name}',
                                    style: IconButton.styleFrom(
                                      backgroundColor: context.stockLinen,
                                    ),
                                    onPressed:
                                        store.stock(p) <= 0 || isCountLocked
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
                    if (query.trim().isNotEmpty &&
                        _allMatchingProducts.length > _filteredProducts.length)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Center(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _catalogDisplayLimit += 20;
                              });
                            },
                            icon: const Icon(Icons.expand_more, size: 16),
                            label: Text(
                              'Load more products (${_allMatchingProducts.length - _filteredProducts.length} more)',
                            ),
                          ),
                        ),
                      ),
                    if (_catalogDisplayLimit > 20 && query.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Center(
                          child: TextButton(
                            onPressed: () {
                              setState(() {
                                _catalogDisplayLimit = 20;
                              });
                            },
                            child: const Text('Show less'),
                          ),
                        ),
                      ),
                  ],
                ],
                const SizedBox(height: 24),
                TextField(
                  controller: note,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: context.l10n.saleNoteOptional,
                    hintText: context.l10n.saleNoteHint,
                  ),
                ),
                const SizedBox(height: 18),
                Surface(
                  color: avocado,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.l10n.total,
                              style: const TextStyle(
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
                      if (discount > 0) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                context.l10n.discountDeduction(money(store, discount)),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              context.l10n.beforeDiscount(money(store, subtotal)),
                              style: TextStyle(
                                fontSize: 11,
                                color: context.stockMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  context.l10n.cashRecordingOnlyNote,
                  style: TextStyle(
                    fontSize: 11,
                    color: context.stockMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: saving || cart.isEmpty ? null : checkout,
                  icon: const Icon(Icons.check),
                  label: Text(saving ? context.l10n.savingEllipsis : context.l10n.recordCashSale),
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
  int _countDisplayLimit = 30;

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
          decoration: InputDecoration(
            labelText: context.l10n.actualQtyShelf,
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: Text(context.l10n.saveCount),
          ),
        ],
      ),
    );
    if (result != null) {
      final qty = int.tryParse(result);
      if (qty == null || qty < 0 || qty > 100000000) {
        if (mounted) {
          showMessage(context, context.l10n.enterWholeQuantity);
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
      showMessage(context, context.l10n.itemNotInCurrentCount);
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
          title: Text(review ? context.l10n.reviewStockCount : context.l10n.countYourStock),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 740),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Eyebrow(context.l10n.placeForEveryPiece),
                const SizedBox(height: 12),
                Text(
                  count == null
                      ? context.l10n.freshLookOnHand
                      : review
                      ? context.l10n.momentCheckDifference
                      : context.l10n.oneShelfAtATime,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 18),
                if (count == null) ...[
                  Surface(
                    color: linen,
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.storefront_outlined,
                          color: context.stockInk,
                          size: 22,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.l10n.countingDuringHours,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                context.l10n.countingDuringHoursNote,
                                style: TextStyle(
                                  color: context.stockMuted,
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
                      decoration: InputDecoration(
                        labelText: context.l10n.countScope,
                        prefixIcon: const Icon(Icons.category_outlined),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'All items',
                          child: Text('${context.l10n.allItems} (${store.products.length})'),
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
                        if (val != null) {
                          setState(() {
                            selectedScope = val;
                            _countDisplayLimit = 30;
                          });
                        }
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
                          context.l10n.itemsToCount(_scopedProducts.length),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          selectedScope == 'All items'
                              ? context.l10n.fullStoreCountNotice
                              : context.l10n.categoryCountNotice(selectedScope),
                          style: TextStyle(
                            color: context.stockMuted,
                            fontSize: 12,
                          ),
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
                            run(
                              () => store.startCount(
                                category: selectedScope == 'All items'
                                    ? null
                                    : selectedScope,
                              ),
                            );
                          },
                    child: Text(
                      selectedScope == 'All items'
                          ? context.l10n.startFullStockCount
                          : context.l10n.startCountFor(selectedScope),
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
                              context.l10n.countedOfTotal(values.length, baseline.length),
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
                              ? context.l10n.allChangesPaused
                              : context.l10n.categoryChangesPaused,
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
                      label: Text(context.l10n.scanItemToCount),
                    ),
                    const SizedBox(height: 18),
                  ],
                  Builder(
                    builder: (context) {
                      final baselineKeys = baseline.keys.toList();
                      final visibleKeys =
                          baselineKeys.take(_countDisplayLimit).toList();
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final id in visibleKeys)
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
                                    color: context.stockPaper,
                                    borderRadius: BorderRadius.circular(18),
                                    child: ListTile(
                                      onTap: () => enter(p),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
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
                                            ? context.l10n.expectedAndCounted(
                                                baseline[id] as int,
                                                value?.toString() ?? '—',
                                              )
                                            : context.l10n.expectedQty(
                                                baseline[id] as int,
                                                p.unit,
                                              ),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: context.stockMuted,
                                        ),
                                      ),
                                      trailing: review
                                          ? Tag(
                                              variance == null
                                                  ? context.l10n.notCounted
                                                  : variance == 0
                                                      ? context.l10n.matches
                                                      : '${variance > 0 ? '+' : ''}$variance',
                                              color: variance == 0
                                                  ? context.stockPositive
                                                  : context.stockRust,
                                            )
                                          : Text(
                                              value?.toString() ??
                                                  context.l10n.adjust,
                                              style: TextStyle(
                                                color: value == null
                                                    ? context.stockMuted
                                                    : context.stockInk,
                                                fontWeight: FontWeight.w800,
                                                fontSize:
                                                    value == null ? 12 : 22,
                                              ),
                                            ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          if (baselineKeys.length > 30)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                children: [
                                  if (_countDisplayLimit <
                                      baselineKeys.length) ...[
                                    OutlinedButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _countDisplayLimit += 30;
                                        });
                                      },
                                      icon: const Icon(
                                        Icons.expand_more,
                                        size: 18,
                                      ),
                                      label: Text(
                                        'Show more (${baselineKeys.length - _countDisplayLimit} remaining)',
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _countDisplayLimit =
                                              baselineKeys.length;
                                        });
                                      },
                                      child: Text(
                                        'Show all (${baselineKeys.length})',
                                      ),
                                    ),
                                  ],
                                  if (_countDisplayLimit > 30)
                                    TextButton(
                                      onPressed: () {
                                        setState(() {
                                          _countDisplayLimit = 30;
                                        });
                                      },
                                      child: const Text('Show less'),
                                    ),
                                ],
                              ),
                            ),
                        ],
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
                              context.l10n.postReviewedCountTitle,
                              context.l10n.postReviewedCountMessage,
                              action: context.l10n.postCountAction,
                            )) {
                              await run(store.postCount);
                              if (context.mounted && store.count == null) {
                                setState(() => review = false);
                                showMessage(
                                  context,
                                  context.l10n.countPostedSuccess,
                                );
                              }
                            }
                          },
                    child: Text(
                      review ? context.l10n.postCountAction : context.l10n.reviewDifferences,
                    ),
                  ),
                  if (values.length != baseline.length)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        context.l10n.countEveryItemNotice,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.stockMuted,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () async {
                      if (await confirm(
                        context,
                        context.l10n.cancelCountConfirmTitle,
                        context.l10n.cancelCountConfirmMessage,
                        action: context.l10n.cancelCountAction,
                      )) {
                        await run(store.cancelCount);
                        if (mounted) setState(() => review = false);
                      }
                    },
                    child: Text(
                      context.l10n.cancelCountAction,
                      style: TextStyle(color: context.stockRust),
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
