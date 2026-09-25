import 'package:flutter/material.dart';
import 'package:stockmix/core/theme/design.dart';
import 'package:stockmix/features/app/pages.dart';
import 'package:stockmix/features/stock/stock_store.dart';
import 'package:stockmix/l10n/app_localizations.dart';

class SlowMovingItemsPage extends StatefulWidget {
  final StockStore store;
  final List<dynamic>? slowMovers;

  const SlowMovingItemsPage({
    super.key,
    required this.store,
    this.slowMovers,
  });

  @override
  State<SlowMovingItemsPage> createState() => _SlowMovingItemsPageState();
}

class _SlowMovingItemsPageState extends State<SlowMovingItemsPage> {
  String _searchQuery = '';
  // 0: Highest value, 1: Most stock, 2: Name A-Z
  int _sortBy = 0;

  StockStore get store => widget.store;

  List<Map<String, dynamic>> _getItems() {
    final raw = widget.slowMovers != null
        ? widget.slowMovers!
        : (store.businessSummary(days: 14)['slowMovers'] as List? ?? []);

    return raw.map((item) {
      if (item is Map<String, dynamic>) return item;
      if (item is Map) return Map<String, dynamic>.from(item);
      return <String, dynamic>{};
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final allItems = _getItems();
    final query = _searchQuery.trim().toLowerCase();

    final filtered = allItems.where((item) {
      if (query.isEmpty) return true;
      final name = (item['name'] as String? ?? '').toLowerCase();
      return name.contains(query);
    }).toList();

    if (_sortBy == 0) {
      filtered.sort((a, b) =>
          (b['valuation'] as int? ?? 0).compareTo(a['valuation'] as int? ?? 0));
    } else if (_sortBy == 1) {
      filtered.sort((a, b) =>
          (b['stock'] as int? ?? 0).compareTo(a['stock'] as int? ?? 0));
    } else {
      filtered.sort((a, b) => (a['name'] as String? ?? '')
          .toLowerCase()
          .compareTo((b['name'] as String? ?? '').toLowerCase()));
    }

    final totalValuation = filtered.fold<int>(
      0,
      (sum, item) => sum + (item['valuation'] as int? ?? 0),
    );
    final totalUnits = filtered.fold<int>(
      0,
      (sum, item) => sum + (item['stock'] as int? ?? 0),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.slowMovingItems),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        hintText: context.l10n.findItemPlaceholder,
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () =>
                                    setState(() => _searchQuery = ''),
                              )
                            : null,
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${filtered.length} ${filtered.length == 1 ? "item" : "items"}  ·  $totalUnits units  ·  ${money(store, totalValuation)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.stockMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        PopupMenuButton<int>(
                          initialValue: _sortBy,
                          tooltip: 'Sort slow-moving items',
                          icon: const Icon(Icons.sort_rounded, size: 20),
                          onSelected: (val) => setState(() => _sortBy = val),
                          itemBuilder: (ctx) => const [
                            PopupMenuItem(
                              value: 0,
                              child: Text('Highest valuation tied up'),
                            ),
                            PopupMenuItem(
                              value: 1,
                              child: Text('Most stock on hand'),
                            ),
                            PopupMenuItem(
                              value: 2,
                              child: Text('Name (A - Z)'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: EmptyState(
                            icon: Icons.check_circle_outline,
                            title: query.isEmpty
                                ? context.l10n.healthyMovement
                                : context.l10n.noMatchingItems,
                            subtitle: query.isEmpty
                                ? context.l10n.healthyMovementSubtitle
                                : context.l10n.tryAnotherNameOrFilter,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                        itemCount: filtered.length,
                        separatorBuilder: (_, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final id = item['id'] as String? ?? '';
                          final name = item['name'] as String? ?? '';
                          final stockVal = item['stock'] as int? ?? 0;
                          final unit = item['unit'] as String? ?? 'unit';
                          final valuation = item['valuation'] as int? ?? 0;

                          Product? p;
                          try {
                            p = store.product(id);
                          } catch (_) {}

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: id.isNotEmpty
                                  ? () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => ProductPage(
                                            store: store,
                                            id: id,
                                          ),
                                        ),
                                      )
                                  : null,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                  horizontal: 8,
                                ),
                                child: Row(
                                  children: [
                                    if (p != null)
                                      ProductImage(p, size: 44)
                                    else
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: context.stockLinen,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Icon(
                                          Icons.hourglass_empty_rounded,
                                          size: 20,
                                          color: context.stockMuted,
                                        ),
                                      ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            context.l10n.quantityInStockLabel(
                                              stockVal,
                                              unit,
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
                                          money(store, valuation),
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
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.chevron_right,
                                      size: 16,
                                      color: context.stockMuted,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
