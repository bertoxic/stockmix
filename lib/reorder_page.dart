import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'design.dart';
import 'pages.dart';
import 'stock_store.dart';

class ReorderPage extends StatefulWidget {
  final StockStore store;
  const ReorderPage({super.key, required this.store});

  @override
  State<ReorderPage> createState() => _ReorderPageState();
}

class _ReorderPageState extends State<ReorderPage> {
  final Map<String, int> _quantities = {};
  final Map<String, TextEditingController> _quantityControllers = {};
  final Set<String> _selected = {};
  bool _working = false;

  StockStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _initList();
  }

  void _initList() {
    for (final p in store.low) {
      final onHand = store.stock(p);
      final suggested = max(1, (p.threshold * 2) - onHand);
      _quantities[p.id] = suggested;
      _selected.add(p.id);
    }
  }

  TextEditingController _quantityController(String productId, int quantity) =>
      _quantityControllers.putIfAbsent(
        productId,
        () => TextEditingController(text: '$quantity'),
      );

  void _setQuantity(String productId, int quantity) {
    setState(() => _quantities[productId] = quantity);
    final controller = _quantityControllers[productId];
    if (controller != null && controller.text != '$quantity') {
      controller.value = TextEditingValue(
        text: '$quantity',
        selection: TextSelection.collapsed(offset: '$quantity'.length),
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  int get _totalSelectedUnits {
    var total = 0;
    for (final id in _selected) {
      total += _quantities[id] ?? 0;
    }
    return total;
  }

  int get _totalEstimatedCost {
    var total = 0;
    for (final id in _selected) {
      final p = store.products.where((item) => item.id == id).firstOrNull;
      if (p != null) {
        total += (p.cost * (_quantities[id] ?? 0));
      }
    }
    return total;
  }

  String _formatSupplierList() {
    final buffer = StringBuffer()
      ..writeln('PURCHASE ORDER / SHOPPING LIST')
      ..writeln('Store: ${store.shop}')
      ..writeln(
        'Date: ${DateFormat('d MMM yyyy, h:mm a').format(DateTime.now())}',
      )
      ..writeln('================================');

    var count = 0;
    for (final id in _selected) {
      final p = store.products.where((item) => item.id == id).firstOrNull;
      if (p == null) continue;
      final qty = _quantities[id] ?? 0;
      if (qty <= 0) continue;
      count++;
      buffer.writeln('$count. ${p.name}');
      if (p.barcode.isNotEmpty) buffer.writeln('   Barcode: ${p.barcode}');
      buffer.writeln('   Quantity: $qty ${p.unit}');
      if (p.cost > 0) {
        buffer.writeln('   Est. cost: ${money(store, p.cost * qty)}');
      }
      buffer.writeln('--------------------------------');
    }

    buffer
      ..writeln('SUMMARY:')
      ..writeln('Items: $count | Total units: $_totalSelectedUnits')
      ..writeln('Estimated total: ${money(store, _totalEstimatedCost)}')
      ..writeln('================================')
      ..writeln('Sent via Stockmix');

    return buffer.toString();
  }

  Future<void> _shareOrder({Rect? origin}) async {
    if (_selected.isEmpty) {
      showMessage(context, 'Select at least one item to share.');
      return;
    }
    final text = _formatSupplierList();
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: 'Order list from ${store.shop}',
        sharePositionOrigin: origin,
      ),
    );
  }

  Future<void> _receiveDelivery() async {
    if (_selected.isEmpty) {
      showMessage(context, 'Select at least one item to receive.');
      return;
    }
    final supplierCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Receive Delivery'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Receive $_totalSelectedUnits units across ${_selected.length} items into inventory now?',
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: supplierCtrl,
              decoration: const InputDecoration(
                labelText: 'Supplier name (optional)',
                hintText: 'e.g. Metro Food Wholesalers',
              ),
              textCapitalization: TextCapitalization.words,
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
            child: const Text('Confirm & Receive'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() => _working = true);
      try {
        final toReceive = <String, int>{};
        for (final id in _selected) {
          final qty = _quantities[id] ?? 0;
          if (qty > 0) toReceive[id] = qty;
        }
        final receivedTotal = await store.batchReceive(
          toReceive,
          supplier: supplierCtrl.text,
        );
        if (mounted) {
          showMessage(
            context,
            'Successfully received $receivedTotal units into stock.',
          );
          Navigator.pop(context);
        }
      } catch (e) {
        if (mounted) showMessage(context, friendlyError(e));
      } finally {
        if (mounted) setState(() => _working = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lowProducts = store.low;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shopping List'),
        actions: [
          if (lowProducts.isNotEmpty)
            Builder(
              builder: (btnCtx) => IconButton(
                tooltip: 'Share order list',
                icon: const Icon(Icons.share_outlined),
                onPressed: () {
                  final box = btnCtx.findRenderObject() as RenderBox?;
                  final origin = box != null
                      ? box.localToGlobal(Offset.zero) & box.size
                      : null;
                  _shareOrder(origin: origin);
                },
              ),
            ),
        ],
      ),
      body: lowProducts.isEmpty
          ? Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 500),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: EmptyState(
                    icon: Icons.check_circle_outline_rounded,
                    title: 'All stocked up!',
                    subtitle:
                        'No items are currently at or below their low-stock threshold.',
                    action: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to stock'),
                    ),
                  ),
                ),
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 90),
                  children: [
                    const Eyebrow('Restock & purchasing'),
                    const SizedBox(height: 8),
                    Text(
                      'Items running low.',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Quantities are suggested to reach double the threshold. Adjust as needed to share an order or receive deliveries.',
                      style: TextStyle(
                        color: context.stockMuted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Summary header
                    Surface(
                      color: linen,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Checkbox(
                            value: _selected.length == lowProducts.length
                                ? true
                                : (_selected.isEmpty ? false : null),
                            tristate: true,
                            onChanged: (val) {
                              setState(() {
                                if (val == true) {
                                  _selected.addAll(
                                    lowProducts.map((p) => p.id),
                                  );
                                } else {
                                  _selected.clear();
                                }
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${_selected.length} of ${lowProducts.length} selected',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '$_totalSelectedUnits units',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                              if (_totalEstimatedCost > 0)
                                Text(
                                  'Est. ${money(store, _totalEstimatedCost)}',
                                  style: TextStyle(
                                    color: context.stockMuted,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // List of items
                    ...lowProducts.map((p) {
                      final isSelected = _selected.contains(p.id);
                      final onHand = store.stock(p);
                      final qty = _quantities[p.id] ?? 1;
                      final quantityController = _quantityController(p.id, qty);

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Surface(
                          color: isSelected ? paper : linen.withAlpha(120),
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Checkbox(
                                    value: isSelected,
                                    onChanged: (v) {
                                      setState(() {
                                        if (v == true) {
                                          _selected.add(p.id);
                                        } else {
                                          _selected.remove(p.id);
                                        }
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 6),
                                  ProductImage(p, size: 48),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          p.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          '${p.category}  ·  ${store.stockLabel(p)} left (min ${p.threshold})',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: onHand <= 0
                                                ? context.stockRust
                                                : context.stockMuted,
                                            fontWeight: onHand <= 0
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 18),
                              Row(
                                children: [
                                  const SizedBox(width: 48),
                                  Expanded(
                                    child: Wrap(
                                      spacing: 12,
                                      runSpacing: 8,
                                      alignment: WrapAlignment.spaceBetween,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          'Order quantity:',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: context.stockMuted,
                                          ),
                                        ),
                                        Container(
                                          decoration: BoxDecoration(
                                            color: context.stockLinen,
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.remove,
                                                  size: 16,
                                                ),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                onPressed: qty > 1
                                                    ? () => _setQuantity(
                                                        p.id,
                                                        qty - 1,
                                                      )
                                                    : null,
                                              ),
                                              Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                    ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    SizedBox(
                                                      width: 40,
                                                      child: TextField(
                                                        key: ValueKey(
                                                          'order-quantity-${p.id}',
                                                        ),
                                                        controller:
                                                            quantityController,
                                                        keyboardType:
                                                            TextInputType
                                                                .number,
                                                        inputFormatters: [
                                                          FilteringTextInputFormatter
                                                              .digitsOnly,
                                                        ],
                                                        textAlign:
                                                            TextAlign.center,
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 13,
                                                        ),
                                                        decoration:
                                                            const InputDecoration(
                                                              isDense: true,
                                                              filled: true,
                                                              fillColor: Colors
                                                                  .transparent,
                                                              border:
                                                                  InputBorder
                                                                      .none,
                                                              enabledBorder:
                                                                  InputBorder
                                                                      .none,
                                                              focusedBorder:
                                                                  InputBorder
                                                                      .none,
                                                              contentPadding:
                                                                  EdgeInsets
                                                                      .zero,
                                                            ),
                                                        onChanged: (value) {
                                                          final quantity =
                                                              int.tryParse(
                                                                value,
                                                              );
                                                          if (quantity !=
                                                              null) {
                                                            _setQuantity(
                                                              p.id,
                                                              quantity,
                                                            );
                                                          }
                                                        },
                                                        onEditingComplete: () {
                                                          if (int.tryParse(
                                                                quantityController
                                                                    .text,
                                                              ) ==
                                                              null) {
                                                            _setQuantity(
                                                              p.id,
                                                              _quantities[p
                                                                      .id] ??
                                                                  1,
                                                            );
                                                          }
                                                          FocusScope.of(
                                                            context,
                                                          ).unfocus();
                                                        },
                                                      ),
                                                    ),
                                                    Text(
                                                      ' ${p.unit}',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.add,
                                                  size: 16,
                                                ),
                                                visualDensity:
                                                    VisualDensity.compact,
                                                onPressed: () =>
                                                    _setQuantity(p.id, qty + 1),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (p.cost > 0)
                                          Text(
                                            money(store, p.cost * qty),
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
      bottomNavigationBar: lowProducts.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              decoration: BoxDecoration(
                color: context.stockPaper,
                border: Border(top: BorderSide(color: context.stockLine)),
              ),
              child: SafeArea(
                top: false,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: Row(
                    children: [
                      Builder(
                        builder: (shareBtnCtx) => Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _working
                                ? null
                                : () {
                                    final box =
                                        shareBtnCtx.findRenderObject()
                                            as RenderBox?;
                                    final origin = box != null
                                        ? box.localToGlobal(Offset.zero) &
                                              box.size
                                        : null;
                                    _shareOrder(origin: origin);
                                  },
                            icon: const Icon(Icons.share_outlined, size: 18),
                            label: const Text('Share order'),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: avocado,
                            foregroundColor: plum,
                          ),
                          onPressed: _working ? null : _receiveDelivery,
                          icon: const Icon(
                            Icons.move_to_inbox_outlined,
                            size: 18,
                          ),
                          label: Text(
                            _working ? 'Receiving…' : 'Receive delivery',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
