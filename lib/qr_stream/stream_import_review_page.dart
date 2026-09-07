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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review Streamed Entries'),
      ),
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
                        const Icon(Icons.verified_outlined, color: Colors.green, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'From ${analysis.shopName} · ${analysis.bundleKind}',
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: context.stockPaper,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: cement),
                          ),
                          child: Text(
                            EntryHasher.shortHash(widget.verifiedSha256),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w600),
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
                          style: TextStyle(fontSize: 12, color: context.stockMuted),
                        ),
                        if (durationString != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: avocado.withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.timer_outlined, size: 13, color: context.stockInk),
                                const SizedBox(width: 4),
                                Text(
                                  'Time taken: $durationString',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.stockInk),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'SHA-256: ${widget.verifiedSha256}',
                      style: TextStyle(fontSize: 10, color: context.stockMuted, fontFamily: 'monospace'),
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
                              Icon(Icons.add_circle_outline, size: 18, color: plum),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text('New to your store', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            isStockSnapshot
                                ? '${analysis.newProductsCount} new products'
                                : '${analysis.newMovementsCount} new movements',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Safe to import without duplicate risk',
                            style: TextStyle(fontSize: 11, color: context.stockMuted),
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
                              Icon(Icons.copy_all_outlined, size: 18, color: context.stockRust),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text('Duplicates detected', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            isStockSnapshot
                                ? '${analysis.duplicateProductsCount} duplicate items'
                                : '${analysis.duplicateMovementsCount} duplicate records',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: context.stockRust),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Will be safely skipped to protect inventory',
                            style: TextStyle(fontSize: 11, color: context.stockMuted),
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
                      Icon(Icons.warning_amber_rounded, color: context.stockRust),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Store currency mismatch (${widget.store.currency} vs ${analysis.currency}). Product inventory cannot be directly imported.',
                          style: TextStyle(fontSize: 12, color: context.stockRust),
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
                      Icon(Icons.info_outline, size: 18, color: context.stockMuted),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Note: An identical snapshot or record has already been saved in Received Records.',
                          style: TextStyle(fontSize: 12, color: context.stockMuted),
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
                for (final item in analysis.products)
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
                                        style: const TextStyle(fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    _buildStatusChip(item.isDuplicate, item.matchReason),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '${item.onHand} ${item.product.unit} · ${widget.store.currency} ${(item.product.price / 100).toStringAsFixed(2)} · Barcode: ${item.product.barcode.isEmpty ? "None" : item.product.barcode}',
                                  style: TextStyle(fontSize: 12, color: context.stockMuted),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Hash: ${EntryHasher.shortHash(item.contentHash)}',
                                  style: TextStyle(fontSize: 10, color: context.stockMuted, fontFamily: 'monospace'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ] else ...[
                for (final item in analysis.movements)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Surface(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.movement.name,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                              _buildStatusChip(item.isDuplicate, item.matchReason),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${item.movement.type} · ${item.movement.delta} units · ${widget.store.currency} ${(item.movement.price / 100).toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 12, color: context.stockMuted),
                          ),
                          if (item.movement.note.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(item.movement.note, style: const TextStyle(fontSize: 12)),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'Ref: ${item.movement.reference} · Hash: ${EntryHasher.shortHash(item.contentHash)}',
                            style: TextStyle(fontSize: 10, color: context.stockMuted, fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],

              const SizedBox(height: 24),

              // Action Buttons
              if (currencyMatch && isStockSnapshot && analysis.newProductsCount > 0)
                FilledButton.icon(
                  onPressed: working
                      ? null
                      : () => _executeImport(addProducts: true, importMovements: false),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: Text(working ? 'Processing...' : 'Import ${analysis.newProductsCount} New Products (Skip Duplicates)'),
                ),

              if (currencyMatch && isDayRecord && analysis.newMovementsCount > 0)
                FilledButton.icon(
                  onPressed: working
                      ? null
                      : () => _executeImport(addProducts: false, importMovements: true),
                  icon: const Icon(Icons.sync_alt),
                  label: Text(working ? 'Processing...' : 'Import ${analysis.newMovementsCount} New Movements (Skip Duplicates)'),
                ),

              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: working
                    ? null
                    : () => _executeImport(addProducts: false, importMovements: false),
                icon: const Icon(Icons.folder_shared_outlined),
                label: const Text('Save as Received Record Only (No Inventory Changes)'),
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
              style: TextStyle(fontSize: 10, color: context.stockRust, fontWeight: FontWeight.w600),
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
              style: TextStyle(fontSize: 10, color: context.stockInk, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      );
    }
  }
}
