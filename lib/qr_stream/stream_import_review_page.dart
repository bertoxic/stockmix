import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../design.dart';
import '../stock_store.dart';
import 'entry_hasher.dart';

/// Duplicate-Safe Stream Import Review Screen.
class StreamImportReviewPage extends StatefulWidget {
  final StockStore store;
  final Map<String, dynamic> rawPayload;
  final String verifiedSha256;
  final Duration? transferDuration;

  const StreamImportReviewPage({
    super.key,
    required this.store,
    required this.rawPayload,
    required this.verifiedSha256,
    this.transferDuration,
  });

  @override
  State<StreamImportReviewPage> createState() => _StreamImportReviewPageState();
}

class _StreamImportReviewPageState extends State<StreamImportReviewPage> {
  late final StreamImportAnalysis analysis;
  bool working = false;
  int visibleEntries = 5;

  @override
  void initState() {
    super.initState();
    analysis = StreamImportAnalysis.analyze(widget.rawPayload, widget.store);
  }

  Future<void> _executeImport({
    required bool addProducts,
    required bool importMovements,
  }) async {
    if (working) return;
    setState(() => working = true);
    try {
      await widget.store.importStreamBundle(
        widget.rawPayload,
        addProducts: addProducts,
        importMovements: importMovements,
      );
      if (mounted) {
        Navigator.pop(context, true);
        showMessage(
          context,
          addProducts || importMovements
              ? 'Import complete. New entries added, duplicates safely skipped.'
              : 'Record saved to Received Records.',
        );
      }
    } catch (e) {
      if (mounted) {
        showMessage(context, friendlyError(e));
        setState(() => working = false);
      }
    }
  }

  List<List<MovementAnalysisItem>> _movementEntryGroups() {
    final groups = <List<MovementAnalysisItem>>[];
    final processedReferences = <String>{};
    for (final item in analysis.movements) {
      final movement = item.movement;
      if (movement.type == 'Sale' && movement.reference.isNotEmpty) {
        final key = 'sale:${movement.reference}';
        if (processedReferences.add(key)) {
          groups.add(
            analysis.movements
                .where(
                  (other) =>
                      other.movement.type == 'Sale' &&
                      other.movement.reference == movement.reference,
                )
                .toList(),
          );
        }
      } else if (movement.type.startsWith('Return') &&
          movement.reference.isNotEmpty &&
          movement.reference.startsWith('ret-')) {
        final key = 'return:${movement.reference}';
        if (processedReferences.add(key)) {
          groups.add(
            analysis.movements
                .where(
                  (other) =>
                      other.movement.type.startsWith('Return') &&
                      other.movement.reference == movement.reference,
                )
                .toList(),
          );
        }
      } else {
        groups.add([item]);
      }
    }
    return groups;
  }

  Widget _movementEntryTile(List<MovementAnalysisItem> group) {
    final first = group.first.movement;
    final isSale = first.type == 'Sale';
    final isReturn = first.type.startsWith('Return');
    final itemNames = group
        .map((item) => item.movement.name)
        .toSet()
        .join(', ');
    final newCount = group.where((item) => !item.isDuplicate).length;
    final duplicateCount = group.length - newCount;
    final total = isSale
        ? group.fold<int>(
            0,
            (sum, item) =>
                sum +
                (item.movement.lineTotal ??
                    -item.movement.delta * item.movement.price),
          )
        : group.fold<int>(0, (sum, item) => sum + item.movement.delta.abs());
    final time = DateFormat(
      'h:mm a',
    ).format(DateTime.parse(first.at).toLocal());
    final status = newCount == group.length
        ? 'New'
        : duplicateCount == group.length
        ? 'Duplicate'
        : '$newCount new · $duplicateCount duplicate';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Surface(
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color:
                    (isSale
                            ? avocado
                            : isReturn
                            ? rust
                            : cement)
                        .withValues(alpha: .18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isSale
                    ? Icons.shopping_bag_outlined
                    : isReturn
                    ? Icons.replay_outlined
                    : first.delta >= 0
                    ? Icons.south_west
                    : Icons.north_east,
                size: 20,
                color: isReturn ? context.stockRust : context.stockInk,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    itemNames,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    isSale
                        ? 'Sale (${group.length} ${group.length == 1 ? 'item' : 'items'}) · $time'
                        : isReturn
                        ? 'Customer return (${group.length} ${group.length == 1 ? 'item' : 'items'}) · $time'
                        : '${first.type} · $time',
                    style: TextStyle(fontSize: 11, color: context.stockMuted),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    status,
                    style: TextStyle(
                      fontSize: 10,
                      color: duplicateCount == 0
                          ? context.stockPositive
                          : duplicateCount == group.length
                          ? context.stockRust
                          : context.stockMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              isSale
                  ? '${widget.store.currency} ${(total / 100).toStringAsFixed(2)}'
                  : '$total units',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: isReturn ? context.stockRust : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Represents all duplicate-only entries in a compact form, so the review
  /// stays focused on the entries that will actually be imported.
  Widget _duplicateSummaryTile({
    required Iterable<String> names,
    required int total,
    required String label,
  }) {
    final visibleNames = names.toSet().take(4).toList();
    final remaining = total - visibleNames.length;
    final nameSummary = [
      visibleNames.join(', '),
      if (remaining > 0) '+$remaining others',
    ].where((part) => part.isNotEmpty).join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Surface(
        color: context.stockLinen,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: rust.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.content_copy_outlined,
                size: 20,
                color: context.stockRust,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nameSummary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$total duplicate $label',
                    style: TextStyle(
                      fontSize: 11,
                      color: context.stockRust,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyMatch = analysis.currency == widget.store.currency;
    final isStockSnapshot = analysis.bundleKind == 'Stock snapshot';
    final isDayRecord = analysis.bundleKind == 'Day record';
    final duration = widget.transferDuration;
    final durationString = duration != null
        ? (duration.inMilliseconds < 1000
              ? '${duration.inMilliseconds} ms'
              : '${(duration.inMilliseconds / 1000).toStringAsFixed(1)} s')
        : null;
    final movementGroups = isStockSnapshot
        ? const <List<MovementAnalysisItem>>[]
        : _movementEntryGroups();
    final newProducts = analysis.products
        .where((item) => !item.isDuplicate)
        .toList();
    final duplicateProducts = analysis.products
        .where((item) => item.isDuplicate)
        .toList();
    final newMovementGroups = movementGroups
        .where((group) => group.any((item) => !item.isDuplicate))
        .toList();
    final duplicateMovementItems = movementGroups
        .where((group) => group.every((item) => item.isDuplicate))
        .expand((group) => group)
        .toList();
    final entryCount = isStockSnapshot
        ? newProducts.length + (duplicateProducts.isEmpty ? 0 : 1)
        : newMovementGroups.length + (duplicateMovementItems.isEmpty ? 0 : 1);
    final displayedProducts = newProducts.take(visibleEntries);
    final displayedMovementGroups = newMovementGroups.take(visibleEntries);
    final showProductDuplicateSummary =
        duplicateProducts.isNotEmpty && visibleEntries > newProducts.length;
    final showMovementDuplicateSummary =
        duplicateMovementItems.isNotEmpty &&
        visibleEntries > newMovementGroups.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Review Streamed Entries')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 750),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Eyebrow('Offline Stream Transfer Complete'),
              const SizedBox(height: 8),
              Text(
                'Duplicate-Safe Import',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 14),

              // Integrity & Origin Banner
              Surface(
                color: linen,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.verified_outlined,
                          color: Colors.green,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'From ${analysis.senderName} · ${analysis.shopName} · ${analysis.bundleKind}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: context.stockPaper,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: cement),
                          ),
                          child: Text(
                            EntryHasher.shortHash(widget.verifiedSha256),
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        Text(
                          'Streamed at ${DateFormat('d MMM yyyy · h:mm a').format(analysis.exportedAt.toLocal())}',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.stockMuted,
                          ),
                        ),
                        if (durationString != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: avocado.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.timer_outlined,
                                  size: 13,
                                  color: context.stockInk,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Time taken: $durationString',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: context.stockInk,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'SHA-256: ${widget.verifiedSha256}',
                      style: TextStyle(
                        fontSize: 10,
                        color: context.stockMuted,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              // Duplicate Detection Stats Card
              Row(
                children: [
                  Expanded(
                    child: Surface(
                      color: avocado,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.add_circle_outline,
                                size: 18,
                                color: plum,
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'New to your store',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            isStockSnapshot
                                ? '${analysis.newProductsCount} new products'
                                : '${analysis.newMovementsCount} new movements',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Safe to import without duplicate risk',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.stockMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Surface(
                      color: paper,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.copy_all_outlined,
                                size: 18,
                                color: context.stockRust,
                              ),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Duplicates detected',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            isStockSnapshot
                                ? '${analysis.duplicateProductsCount} duplicate items'
                                : '${analysis.duplicateMovementsCount} duplicate records',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: context.stockRust,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Will be safely skipped to protect inventory',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.stockMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              if (!currencyMatch) ...[
                const SizedBox(height: 16),
                Surface(
                  color: Colors.amber.shade50,
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: context.stockRust,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Store currency mismatch (${widget.store.currency} vs ${analysis.currency}). Product inventory cannot be directly imported.',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.stockRust,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (analysis.isBundleAlreadyReceived) ...[
                const SizedBox(height: 14),
                Surface(
                  color: linen,
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: context.stockMuted,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Note: An identical snapshot or record has already been saved in Received Records.',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.stockMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 24),
              const Eyebrow('Itemized Entries & Status'),
              const SizedBox(height: 12),

              // Detailed Item List
              if (isStockSnapshot) ...[
                for (final item in displayedProducts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Surface(
                      child: Row(
                        children: [
                          ProductImage(item.product, size: 52),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        item.product.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    _buildStatusChip(
                                      item.isDuplicate,
                                      item.matchReason,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${item.onHand} ${item.product.unit} · ${widget.store.currency} ${(item.product.price / 100).toStringAsFixed(2)} · Barcode: ${item.product.barcode.isEmpty ? "None" : item.product.barcode}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.stockMuted,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Hash: ${EntryHasher.shortHash(item.contentHash)}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: context.stockMuted,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (showProductDuplicateSummary)
                  _duplicateSummaryTile(
                    names: duplicateProducts.map((item) => item.product.name),
                    total: duplicateProducts.length,
                    label: duplicateProducts.length == 1 ? 'item' : 'items',
                  ),
              ] else ...[
                for (final group in displayedMovementGroups)
                  _movementEntryTile(group),
                if (showMovementDuplicateSummary)
                  _duplicateSummaryTile(
                    names: duplicateMovementItems.map(
                      (item) => item.movement.name,
                    ),
                    total: duplicateMovementItems.length,
                    label: duplicateMovementItems.length == 1
                        ? 'entry'
                        : 'entries',
                  ),
              ],
              if (entryCount > visibleEntries) ...[
                const SizedBox(height: 2),
                Center(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => visibleEntries += 5),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text(
                      'See more (${entryCount - visibleEntries} more)',
                    ),
                  ),
                ),
              ] else if (entryCount > 5) ...[
                const SizedBox(height: 2),
                Center(
                  child: TextButton.icon(
                    onPressed: () => setState(() => visibleEntries = 5),
                    icon: const Icon(Icons.expand_less_rounded),
                    label: const Text('Show less'),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Action Buttons
              if (currencyMatch &&
                  isStockSnapshot &&
                  analysis.newProductsCount > 0)
                FilledButton.icon(
                  onPressed: working
                      ? null
                      : () => _executeImport(
                          addProducts: true,
                          importMovements: false,
                        ),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: Text(
                    working
                        ? 'Processing...'
                        : 'Import ${analysis.newProductsCount} New Products (Skip Duplicates)',
                  ),
                ),

              if (currencyMatch &&
                  isDayRecord &&
                  analysis.newMovementsCount > 0)
                FilledButton.icon(
                  onPressed: working
                      ? null
                      : () => _executeImport(
                          addProducts: false,
                          importMovements: true,
                        ),
                  icon: const Icon(Icons.sync_alt),
                  label: Text(
                    working
                        ? 'Processing...'
                        : 'Import ${analysis.newMovementsCount} New Movements (Skip Duplicates)',
                  ),
                ),

              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: working
                    ? null
                    : () => _executeImport(
                        addProducts: false,
                        importMovements: false,
                      ),
                icon: const Icon(Icons.folder_shared_outlined),
                label: const Text(
                  'Save as Received Record Only (No Inventory Changes)',
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: working ? null : () => Navigator.pop(context),
                child: const Text('Discard / Cancel'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(bool isDuplicate, String reason) {
    if (isDuplicate) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: context.stockLinen,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: cement),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: 12, color: context.stockRust),
            const SizedBox(width: 4),
            Text(
              'Duplicate · $reason',
              style: TextStyle(
                fontSize: 10,
                color: context.stockRust,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: avocado.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check, size: 12, color: context.stockInk),
            SizedBox(width: 4),
            Text(
              'New Entry',
              style: TextStyle(
                fontSize: 10,
                color: context.stockInk,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
  }
}
