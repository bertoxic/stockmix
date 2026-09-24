import 'dart:io';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:stockmix/core/theme/design.dart';
import 'package:stockmix/features/app/pages.dart';
import 'package:stockmix/features/stock/stock_store.dart';

class ReceiptLineItem {
  final Product product;
  final int quantity;
  final int unitPrice;
  final String unitName;

  const ReceiptLineItem({
    required this.product,
    required this.quantity,
    required this.unitPrice,
    required this.unitName,
  });

  int get total => unitPrice * quantity;
}

class ReceiptInvoicePage extends StatefulWidget {
  final StockStore store;
  final String reference;
  final DateTime date;
  final List<ReceiptLineItem> items;
  final int totalAmount;
  final int discountAmount;
  final String? customerNote;

  const ReceiptInvoicePage({
    super.key,
    required this.store,
    required this.reference,
    required this.date,
    required this.items,
    required this.totalAmount,
    this.discountAmount = 0,
    this.customerNote,
  });

  factory ReceiptInvoicePage.fromCart({
    required StockStore store,
    required String reference,
    required Map<String, int> cart,
    required int total,
    int discount = 0,
    required DateTime date,
    String? note,
  }) {
    final list = cart is SaleCart
        ? cart.lines
              .map(
                (line) => ReceiptLineItem(
                  product: store.product(line.productId),
                  quantity: line.quantity,
                  unitPrice: line.unitPrice,
                  unitName: line.unitName,
                ),
              )
              .toList()
        : cart.entries.map((e) {
            final p = store.product(e.key);
            return ReceiptLineItem(
              product: p,
              quantity: e.value,
              unitPrice: p.price,
              unitName: p.unit,
            );
          }).toList();

    return ReceiptInvoicePage(
      store: store,
      reference: reference,
      date: date,
      items: list,
      totalAmount: total,
      discountAmount: discount,
      customerNote: note,
    );
  }

  factory ReceiptInvoicePage.fromMovement({
    required StockStore store,
    required Movement movement,
  }) {
    final relatedMovements = movement.reference.isNotEmpty
        ? store.movements
              .where(
                (m) => m.reference == movement.reference && m.type == 'Sale',
              )
              .toList()
        : <Movement>[];

    final movementsToUse = relatedMovements.isNotEmpty
        ? relatedMovements
        : [movement];

    final list = movementsToUse.map((m) {
      final p = store.product(m.productId);
      final qty = m.saleQuantity ?? -m.delta;
      return ReceiptLineItem(
        product: p,
        quantity: qty > 0 ? qty : 1,
        unitPrice: m.price,
        unitName: m.saleUnit ?? p.unit,
      );
    }).toList();

    final subtotal = list.fold(0, (sum, i) => sum + i.total);
    final total = movementsToUse.fold(0, (sum, m) => sum + store.saleTotal(m));
    final dt = DateTime.tryParse(movement.at)?.toLocal() ?? DateTime.now();

    return ReceiptInvoicePage(
      store: store,
      reference: movement.reference.isNotEmpty
          ? movement.reference
          : movement.id,
      date: dt,
      items: list,
      totalAmount: total,
      discountAmount: subtotal - total,
      customerNote: movement.note.isNotEmpty && movement.note != 'Cash sale'
          ? movement.note
          : null,
    );
  }

  String get shortRef => reference.length > 8
      ? reference.substring(0, 8).toUpperCase()
      : reference.toUpperCase();

  String formatReceiptText() {
    final buffer = StringBuffer();
    buffer.writeln('================================');
    buffer.writeln(store.shop.toUpperCase());
    buffer.writeln('Receipt #$shortRef');
    buffer.writeln('Date: ${DateFormat('d MMM yyyy, h:mm a').format(date)}');
    if (customerNote != null && customerNote!.trim().isNotEmpty) {
      buffer.writeln('Note: ${customerNote!.trim()}');
    }
    buffer.writeln('--------------------------------');
    for (final item in items) {
      final line =
          '${item.quantity} ${item.unitName} · ${item.product.name.padRight(18)} ${money(store, item.total)}';
      buffer.writeln(line);
      buffer.writeln('   @ ${money(store, item.unitPrice)} / ${item.unitName}');
    }
    buffer.writeln('--------------------------------');
    if (discountAmount > 0) {
      buffer.writeln('DISCOUNT: -${money(store, discountAmount)}');
    }
    buffer.writeln('TOTAL: ${money(store, totalAmount)}');
    buffer.writeln('Payment: Cash');
    buffer.writeln('Items: ${items.fold(0, (a, b) => a + b.quantity)}');
    buffer.writeln('--------------------------------');
    buffer.writeln('Thank you for your business!');
    buffer.writeln('================================');
    return buffer.toString();
  }

  @override
  State<ReceiptInvoicePage> createState() => _ReceiptInvoicePageState();
}

class _ReceiptInvoicePageState extends State<ReceiptInvoicePage> {
  final GlobalKey _receiptBoundaryKey = GlobalKey();
  bool _isProcessing = false;

  Future<Uint8List?> _captureReceiptPng() async {
    try {
      final boundary =
          _receiptBoundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) return null;
      // PNG is lossless; capture at 4× so text and the embedded receipt QR
      // stay sharp when the saved image is viewed or printed off-device.
      final image = await boundary.toImage(pixelRatio: 4.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      debugPrint('Error capturing receipt PNG: $e');
      return null;
    }
  }

  Future<void> _shareReceipt() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final bytes = await _captureReceiptPng();
      if (bytes == null || bytes.isEmpty) {
        if (mounted) showMessage(context, 'Unable to capture receipt image.');
        return;
      }

      final filename = 'receipt-${widget.shortRef}.png';
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/$filename');
      await tempFile.writeAsBytes(bytes);

      if (!mounted) return;

      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null;

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(tempFile.path, mimeType: 'image/png', name: filename)],
          fileNameOverrides: [filename],
          subject: 'Receipt #${widget.shortRef} from ${widget.store.shop}',
          title: 'Share receipt',
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _downloadReceipt() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final bytes = await _captureReceiptPng();
      if (bytes == null || bytes.isEmpty) {
        if (mounted) showMessage(context, 'Unable to capture receipt image.');
        return;
      }

      final filename = 'receipt-${widget.shortRef}.png';

      final saved = await FilePicker.saveFile(
        fileName: filename,
        bytes: bytes,
        type: FileType.image,
        allowedExtensions: ['png'],
        mimeType: 'image/png',
        dialogTitle: 'Save receipt image to device',
      );

      if (saved != null && mounted) {
        showMessage(context, 'Receipt saved to device.');
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final items = widget.items;
    final date = widget.date;
    final reference = widget.reference;
    final totalAmount = widget.totalAmount;
    final discountAmount = widget.discountAmount;
    final customerNote = widget.customerNote;
    final shortRef = widget.shortRef;
    final totalUnits = items.fold(0, (a, b) => a + b.quantity);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoice & Receipt'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'Download receipt',
            onPressed: _isProcessing ? null : _downloadReceipt,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Share receipt',
            onPressed: _isProcessing ? null : _shareReceipt,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top artisanal receipt card (isolated for image capture; buttons outside)
                  RepaintBoundary(
                    key: _receiptBoundaryKey,
                    child: Container(
                      decoration: BoxDecoration(
                        color: context.stockPaper,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: context.stockLine),
                        boxShadow: [
                          BoxShadow(
                            color: plum.withValues(alpha: 0.04),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header banner
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                            child: Column(
                              children: [
                                Container(
                                  width: 52,
                                  height: 52,
                                  decoration: BoxDecoration(
                                    color: avocado,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Icon(
                                    Icons.receipt_long_outlined,
                                    color: plum,
                                    size: 28,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  store.shop.toUpperCase(),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Sales Receipt & Proof of Purchase',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: context.stockMuted),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Tag('#$shortRef', color: context.stockInk),
                                    const SizedBox(width: 8),
                                    Tag('PAID · CASH', color: avocado),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Meta info row
                          Container(
                            color: context.stockLinen.withValues(alpha: 0.5),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              runSpacing: 10,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Eyebrow('Date & time'),
                                    const SizedBox(height: 2),
                                    Text(
                                      DateFormat(
                                        'd MMM yyyy, h:mm a',
                                      ).format(date),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    const Eyebrow('Items'),
                                    const SizedBox(height: 2),
                                    Text(
                                      '$totalUnits ${totalUnits == 1 ? 'unit' : 'units'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          if (customerNote != null &&
                              customerNote.trim().isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: context.stockPaper,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: context.stockLine),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.note_alt_outlined,
                                      size: 16,
                                      color: context.stockMuted,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        customerNote.trim(),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: context.stockInk,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],

                          // Dotted separator
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Row(
                              children: List.generate(
                                30,
                                (index) => Expanded(
                                  child: Container(
                                    height: 1.5,
                                    color: index.isEven
                                        ? context.stockLine
                                        : Colors.transparent,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Column titles
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: [
                                Expanded(child: Eyebrow('Item description')),
                                SizedBox(
                                  width: 30,
                                  child: Eyebrow(
                                    'Qty',
                                    color: context.stockMuted,
                                  ),
                                ),
                                SizedBox(
                                  width: 58,
                                  child: Eyebrow(
                                    'Unit',
                                    color: context.stockMuted,
                                  ),
                                ),
                                SizedBox(
                                  width: 64,
                                  child: Text(
                                    'TOTAL',
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5,
                                      color: context.stockMuted,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),

                          // Line items list
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              children: [
                                for (final item in items) ...[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        ProductImage(item.product, size: 36),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.product.name,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w700,
                                                  fontSize: 13,
                                                ),
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (item
                                                  .product
                                                  .category
                                                  .isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  item.product.category,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    color: context.stockMuted,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        SizedBox(
                                          width: 54,
                                          child: Text(
                                            '${item.quantity} ${item.unitName}',
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 58,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerLeft,
                                            child: Text(
                                              money(store, item.unitPrice),
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: context.stockMuted,
                                              ),
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 64,
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            alignment: Alignment.centerRight,
                                            child: Text(
                                              money(store, item.total),
                                              textAlign: TextAlign.end,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),

                          // Dotted separator before total
                          const SizedBox(height: 16),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Row(
                              children: List.generate(
                                30,
                                (index) => Expanded(
                                  child: Container(
                                    height: 1.5,
                                    color: index.isEven
                                        ? context.stockLine
                                        : Colors.transparent,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Total breakdown
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      discountAmount > 0 ? 'Subtotal' : 'Total',
                                      style: TextStyle(
                                        color: context.stockMuted,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      money(
                                        store,
                                        totalAmount + discountAmount,
                                      ),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                if (discountAmount > 0) ...[
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Discount',
                                        style: TextStyle(
                                          color: context.stockMuted,
                                          fontSize: 13,
                                        ),
                                      ),
                                      Text(
                                        '−${money(store, discountAmount)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Payment method',
                                      style: TextStyle(
                                        color: context.stockMuted,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      'Cash',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Total Paid',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        color: context.stockInk,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          money(store, totalAmount),
                                          style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 22,
                                            color: context.stockInk,
                                            letterSpacing: -0.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Footer with transaction verification QR
                          const SizedBox(height: 24),
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: context.stockLinen,
                              borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(24),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: paper,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: context.stockLine,
                                    ),
                                  ),
                                  child: QrImageView(
                                    data: 'SMX:REC:$reference',
                                    size: 68,
                                    padding: EdgeInsets.zero,
                                    version: QrVersions.auto,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Thank you for your visit!',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: context.stockInk,
                                        ),
                                      ),
                                      SizedBox(height: 3),
                                      Text(
                                        'Retain this receipt for returns or exchanges within standard store policy.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: context.stockMuted,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Primary action buttons
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: plum,
                            foregroundColor: paper,
                            minimumSize: const Size(0, 52),
                          ),
                          onPressed: _isProcessing ? null : _shareReceipt,
                          icon: _isProcessing
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: context.stockPaper,
                                  ),
                                )
                              : const Icon(Icons.share, size: 18),
                          label: const Text('Share receipt'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 52),
                            foregroundColor: context.stockInk,
                            side: BorderSide(color: context.stockLine),
                          ),
                          onPressed: _isProcessing ? null : _downloadReceipt,
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: const Text('Download receipt'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back to store'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
