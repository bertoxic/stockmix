import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'design.dart';
import 'forms.dart';
import 'pages.dart';
import 'scan_feedback.dart';
import 'stock_store.dart';

enum ScannerMode {
  /// Continuous multi-item scanning for sales. Scanned items appear in the live list below the camera,
  /// quantities auto-increment on repeat scan, running total is displayed, and user can checkout or finish.
  multiItem,

  /// Legacy single barcode return (e.g. for ProductForm barcode field or CountPage).
  singleBarcode,
}

class _UnitSelection {
  final SellingUnit unit;
  final int quantity;
  const _UnitSelection(this.unit, this.quantity);
}

class ScannerPage extends StatefulWidget {
  final StockStore? store;
  final ScannerMode mode;
  final Map<String, int>? initialCart;
  final String? title;
  final void Function(Map<String, int> cart)? onCartChanged;

  const ScannerPage({
    super.key,
    this.store,
    this.mode = ScannerMode.singleBarcode,
    this.initialCart,
    this.title,
    this.onCartChanged,
  });

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  late final MobileScannerController controller;
  final manual = TextEditingController();
  late final SaleCart cart;
  bool returned = false;
  bool scanPulsing = false;
  bool flashOn = false;
  bool popping = false;
  String? unrecognizedCode;
  String? lastCode;
  DateTime? lastScannedAt;
  bool selectingUnit = false;

  bool get isMultiItem =>
      widget.mode == ScannerMode.multiItem && widget.store != null;

  bool get cameraSupported =>
      kIsWeb ||
      [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ].contains(defaultTargetPlatform);

  @override
  void initState() {
    super.initState();
    controller = MobileScannerController(
      detectionSpeed: isMultiItem
          ? DetectionSpeed.normal
          : DetectionSpeed.noDuplicates,
    );
    cart = widget.store == null
        ? SaleCart()
        : SaleCart.fromLegacy(widget.initialCart, widget.store!);
  }

  int get totalCost => cart.total;

  int get totalUnits => cart.totalBaseUnits;

  void detected(String? value) {
    if (value == null || value.trim().isEmpty) return;
    final code = value.trim();

    if (!isMultiItem) {
      if (returned) return;
      returned = true;
      unawaited(ScanFeedback.success());
      Navigator.pop(context, code);
      return;
    }

    // Debounce duplicate scans of the identical barcode within 1.2s
    final now = DateTime.now();
    if (lastCode == code &&
        lastScannedAt != null &&
        now.difference(lastScannedAt!) < const Duration(milliseconds: 1200)) {
      return;
    }
    lastCode = code;
    lastScannedAt = now;

    unawaited(_addScannedCode(code));
  }

  Future<void> _addScannedCode(String code) async {
    if (selectingUnit) return;
    final store = widget.store!;

    if (code.toUpperCase().startsWith('SMX:REC:')) {
      final sale = store.findSaleByReference(code);
      if (sale.isNotEmpty) {
        unawaited(ScanFeedback.success());
        final action = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Receipt QR scanned'),
            content: Text(
              'Found sale record with ${sale.length} item${sale.length == 1 ? '' : 's'}.\n\nWould you like to open this sale transaction?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'continue'),
                child: const Text('Keep scanning'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, 'view'),
                child: const Text('Open receipt / returns'),
              ),
            ],
          ),
        );
        if (action == 'view' && mounted) {
          Navigator.pop(context);
          await showSaleTransactionDetails(context, store, sale);
        }
        return;
      }
    }

    final product = store.lookup(code);

    if (product == null) {
      HapticFeedback.vibrate();
      setState(() {
        unrecognizedCode = code;
      });
      return;
    }

    final currentQty = cart.baseQuantityFor(product.id);
    final maxStock = store.stock(product);
    if (currentQty >= maxStock) {
      showMessage(
        context,
        'All available units of "${product.name}" ($maxStock) are already in the sale.',
      );
      return;
    }

    if (!product.sellsByPack) {
      _addUnit(product, product.defaultUnit);
      return;
    }

    setState(() => selectingUnit = true);
    final selection = await _chooseSellingUnit(product, maxStock - currentQty);
    if (!mounted) {
      return;
    }
    setState(() => selectingUnit = false);
    if (selection != null) {
      _addUnit(product, selection.unit, selection.quantity);
    }
  }

  void _addUnit(Product product, SellingUnit unit, [int quantity = 1]) {
    final available =
        widget.store!.stock(product) - cart.baseQuantityFor(product.id);
    final requested = quantity * unit.multiplier;
    if (requested > available) {
      showMessage(
        context,
        'Only ${widget.store!.stockLabel(product)} is available for ${product.name}.',
      );
      return;
    }
    setState(() {
      cart.add(product, unit, quantity: quantity);
      unrecognizedCode = null;
      scanPulsing = true;
    });
    _notifyCartChanged();
    unawaited(ScanFeedback.success());
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => scanPulsing = false);
    });
  }

  Future<_UnitSelection?> _chooseSellingUnit(
    Product product,
    int availableBaseUnits,
  ) => showModalBottomSheet<_UnitSelection>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => _UnitChooserSheet(
      product: product,
      availableBaseUnits: availableBaseUnits,
      stockLabel: widget.store!.stockLabel(product),
      currency: widget.store!.currency,
    ),
  );

  void _notifyCartChanged() {
    widget.onCartChanged?.call(cart.copy());
  }

  void _popWithCart() {
    if (popping) return;
    popping = true;
    Navigator.pop(context, cart.copy());
  }

  void _increment(SaleLine line) {
    final p = widget.store!.product(line.productId);
    final currentQty = cart.baseQuantityFor(p.id);
    final maxStock = widget.store!.stock(p);
    if (currentQty + line.unitMultiplier > maxStock) {
      showMessage(
        context,
        'All available units of "${p.name}" are already in the sale.',
      );
      return;
    }
    setState(
      () => cart.add(
        p,
        SellingUnit(
          name: line.unitName,
          multiplier: line.unitMultiplier,
          price: line.unitPrice,
        ),
      ),
    );
    _notifyCartChanged();
  }

  void _decrement(SaleLine line) {
    setState(() => cart.removeOne(line));
    _notifyCartChanged();
  }

  Future<void> _quickAddProduct(String code) async {
    final store = widget.store!;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ProductForm(store: store, barcode: code),
      ),
    );
    if (!mounted) return;
    final created = store.lookup(code);
    if (created != null) {
      unawaited(_addScannedCode(code));
    }
  }

  Future<void> upload() async {
    try {
      final file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null || !mounted) return;
      final result = await controller.analyzeImage(file.path);
      if (!mounted) return;
      if (result == null || result.barcodes.isEmpty) {
        showMessage(
          context,
          'No barcode found. Try a clearer image or enter the code.',
        );
        return;
      }
      detected(result.barcodes.first.rawValue);
    } catch (_) {
      if (mounted) {
        showMessage(
          context,
          'Image scanning is unavailable here. Use the camera or enter the code.',
        );
      }
    }
  }

  Future<void> checkoutDirectly() async {
    if (cart.isEmpty || widget.store == null) return;
    final store = widget.store!;
    final total = totalCost;
    final accepted = await confirm(
      context,
      'Record cash received?',
      'Confirm you received ${money(store, total)}. This will save the sale and deduct $totalUnits units from stock.',
      action: 'Cash received',
    );
    if (!accepted || !mounted) return;

    try {
      await store.checkoutSale(cart.copy(), '');
      if (!mounted) return;
      final recordedTotal = total;
      setState(() => cart.clear());
      _notifyCartChanged();

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
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _popWithCart();
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  @override
  void dispose() {
    controller.dispose();
    manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isMultiItem) {
      return _buildSingleScanScaffold();
    }
    return _buildMultiItemScanScaffold();
  }

  Widget _buildSingleScanScaffold() => Scaffold(
    appBar: AppBar(title: Text(widget.title ?? 'Scan an item')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Eyebrow('Less typing. More doing.'),
          const SizedBox(height: 12),
          Text(
            'Point. Scan. Find.',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Scan a barcode or QR label to look up the item.',
            style: TextStyle(color: context.stockMuted, height: 1.5),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 290,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cameraSupported)
                    MobileScanner(
                      controller: controller,
                      onDetect: (capture) {
                        if (capture.barcodes.isNotEmpty) {
                          detected(capture.barcodes.first.rawValue);
                        }
                      },
                      errorBuilder: (_, error) => Container(
                        color: plum,
                        padding: const EdgeInsets.all(26),
                        child: Center(
                          child: Text(
                            'Camera unavailable. Allow camera access in device settings or enter code below.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: paper, height: 1.6),
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      color: plum,
                      child: Center(
                        child: Text(
                          'Enter a barcode below on this device.',
                          style: TextStyle(color: paper),
                        ),
                      ),
                    ),
                  if (cameraSupported)
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 230,
                          height: 150,
                          decoration: BoxDecoration(
                            border: Border.all(color: avocado, width: 3),
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (cameraSupported)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        await controller.toggleTorch();
                        setState(() => flashOn = !flashOn);
                      } catch (_) {
                        if (mounted) {
                          showMessage(
                            context,
                            'Flash is unavailable on this camera.',
                          );
                        }
                      }
                    },
                    icon: Icon(
                      flashOn ? Icons.flash_off : Icons.flash_on_outlined,
                    ),
                    label: Text(flashOn ? 'Turn off' : 'Flash'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: upload,
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Scan image'),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 30),
          const Eyebrow('Or enter the code'),
          const SizedBox(height: 12),
          TextField(
            controller: manual,
            decoration: const InputDecoration(
              labelText: 'Barcode / item code',
              prefixIcon: Icon(Icons.qr_code),
            ),
            onSubmitted: detected,
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: () => detected(manual.text),
            child: const Text('Find item'),
          ),
          const SizedBox(height: 20),
          Text(
            'Codes are used for lookup only. Scanned links are never opened automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: context.stockMuted),
          ),
        ],
      ),
    ),
  );

  Widget _buildMultiItemScanScaffold() {
    final store = widget.store!;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final cameraHeight = (screenHeight * 0.28).clamp(180.0, 250.0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _popWithCart();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: _popWithCart,
          ),
          title: Text(widget.title ?? 'Scan into sale'),
          actions: [
            if (cameraSupported)
              IconButton(
                tooltip: flashOn ? 'Turn off flash' : 'Turn on flash',
                icon: Icon(flashOn ? Icons.flash_off : Icons.flash_on_outlined),
                onPressed: () async {
                  try {
                    await controller.toggleTorch();
                    setState(() => flashOn = !flashOn);
                  } catch (_) {
                    if (mounted) {
                      showMessage(
                        context,
                        'Flash is unavailable on this camera.',
                      );
                    }
                  }
                },
              ),
            IconButton(
              tooltip: 'Scan from gallery image',
              icon: const Icon(Icons.photo_library_outlined),
              onPressed: upload,
            ),
            if (cart.isNotEmpty)
              IconButton(
                tooltip: 'Clear scanned items',
                icon: const Icon(Icons.delete_sweep_outlined),
                onPressed: () async {
                  if (await confirm(
                    context,
                    'Clear scanned items?',
                    'This will empty all ${cart.length} items from this scan session.',
                    action: 'Clear',
                  )) {
                    setState(() => cart.clear());
                    _notifyCartChanged();
                  }
                },
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Fixed top camera viewfinder
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  height: cameraHeight,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (cameraSupported)
                          MobileScanner(
                            controller: controller,
                            onDetect: (capture) {
                              if (capture.barcodes.isNotEmpty) {
                                detected(capture.barcodes.first.rawValue);
                              }
                            },
                            errorBuilder: (_, error) => Container(
                              color: plum,
                              padding: const EdgeInsets.all(20),
                              child: Center(
                                child: Text(
                                  'Camera unavailable. Check permissions or enter barcode manually below.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: paper, height: 1.5),
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            color: plum,
                            child: Center(
                              child: Text(
                                'Camera scanning is not supported on this platform. Enter code below.',
                                style: TextStyle(color: paper),
                              ),
                            ),
                          ),
                        // Animated scanning reticle
                        IgnorePointer(
                          child: Center(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              width: 220,
                              height: 125,
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: scanPulsing
                                      ? Colors.greenAccent
                                      : avocado,
                                  width: scanPulsing ? 4.5 : 3,
                                ),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: scanPulsing
                                    ? [
                                        BoxShadow(
                                          color: Colors.greenAccent.withValues(
                                            alpha: 0.4,
                                          ),
                                          blurRadius: 16,
                                          spreadRadius: 2,
                                        ),
                                      ]
                                    : null,
                              ),
                            ),
                          ),
                        ),
                        // Overlay instruction badge
                        Positioned(
                          top: 10,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: plum.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(
                                scanPulsing
                                    ? 'Item Scanned!'
                                    : 'Align barcode within frame',
                                style: TextStyle(
                                  color: scanPulsing
                                      ? Colors.greenAccent
                                      : paper,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Live list of scanned item widgets placed directly under the camera
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    // Unrecognized barcode banner if detected
                    if (unrecognizedCode != null) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: rust.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: rust.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: context.stockRust,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Unregistered barcode',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: context.stockRust,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    unrecognizedCode!,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: context.stockMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: context.stockRust,
                              ),
                              onPressed: () =>
                                  _quickAddProduct(unrecognizedCode!),
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text(
                                'Add item',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                size: 16,
                                color: context.stockMuted,
                              ),
                              onPressed: () =>
                                  setState(() => unrecognizedCode = null),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Header for scanned items
                    Row(
                      children: [
                        Eyebrow('Scanned items (${cart.length})'),
                        const Spacer(),
                        if (cart.isNotEmpty)
                          Text(
                            '$totalUnits units',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.stockMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Scanned item widgets
                    if (cart.isEmpty)
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 16),
                        padding: const EdgeInsets.symmetric(
                          vertical: 24,
                          horizontal: 16,
                        ),
                        decoration: BoxDecoration(
                          color: context.stockPaper,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: context.stockLine),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.qr_code_scanner,
                              size: 36,
                              color: cement,
                            ),
                            SizedBox(height: 10),
                            Text(
                              'Ready to scan',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Scan item barcodes continuously. Each scanned item will appear here with its price and count.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: context.stockMuted,
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ...cart.lines.map((line) {
                        final p = store.product(line.productId);
                        final qty = line.quantity;
                        final lineTotal = line.total;
                        final maxStock = store.stock(p);
                        final baseQuantity = cart.baseQuantityFor(p.id);

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Surface(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                InkWell(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          ProductPage(store: store, id: p.id),
                                    ),
                                  ),
                                  child: ProductImage(p, size: 44),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${money(store, line.unitPrice)} / ${line.unitName}  ·  ${store.stockLabel(p)} in stock',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: context.stockMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Quantity controls
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: 'Remove one',
                                      icon: Icon(
                                        qty == 1
                                            ? Icons.delete_outline
                                            : Icons.remove_circle_outline,
                                        size: 20,
                                        color: qty == 1 ? context.stockRust : context.stockInk,
                                      ),
                                      onPressed: () => _decrement(line),
                                    ),
                                    Container(
                                      constraints: const BoxConstraints(
                                        minWidth: 24,
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '$qty ${line.unitName}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      tooltip: 'Add one',
                                      icon: const Icon(
                                        Icons.add_circle_outline,
                                        size: 20,
                                      ),
                                      onPressed:
                                          baseQuantity + line.unitMultiplier >
                                              maxStock
                                          ? null
                                          : () => _increment(line),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 4),
                                // Line total
                                SizedBox(
                                  width: 62,
                                  child: Text(
                                    money(store, lineTotal),
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),

                    const SizedBox(height: 12),
                    // Manual code entry row
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: manual,
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: 'Or type barcode…',
                              prefixIcon: Icon(Icons.qr_code, size: 20),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                            onSubmitted: (v) {
                              detected(v);
                              manual.clear();
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                          ),
                          onPressed: () {
                            detected(manual.text);
                            manual.clear();
                          },
                          child: const Text('Add'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),

              // Sticky bottom summary and actions bar
              Container(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                decoration: BoxDecoration(
                  color: context.stockPaper,
                  border: Border(top: BorderSide(color: context.stockLine)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Eyebrow('Total'),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              money(store, totalCost),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: context.stockInk,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          Text(
                            '$totalUnits ${totalUnits == 1 ? 'unit' : 'units'}',
                            style: TextStyle(fontSize: 11, color: context.stockMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (widget.initialCart != null)
                      FilledButton.icon(
                        onPressed: _popWithCart,
                        icon: const Icon(Icons.check),
                        label: Text(cart.isEmpty ? 'Done' : 'Apply to sale'),
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              minimumSize: const Size(0, 48),
                            ),
                            onPressed: cart.isEmpty ? null : _popWithCart,
                            child: const Text('Review'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: avocado,
                              foregroundColor: plum,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              minimumSize: const Size(0, 48),
                            ),
                            onPressed: cart.isEmpty ? null : checkoutDirectly,
                            icon: const Icon(Icons.point_of_sale, size: 16),
                            label: const Text('Cash sale'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UnitChooserSheet extends StatefulWidget {
  final Product product;
  final int availableBaseUnits;
  final String stockLabel;
  final String currency;

  const _UnitChooserSheet({
    required this.product,
    required this.availableBaseUnits,
    required this.stockLabel,
    required this.currency,
  });

  @override
  State<_UnitChooserSheet> createState() => _UnitChooserSheetState();
}

class _UnitChooserSheetState extends State<_UnitChooserSheet> {
  late SellingUnit selectedUnit;
  int quantity = 1;

  @override
  void initState() {
    super.initState();
    final preferred = widget.product.defaultUnit;
    selectedUnit = preferred.multiplier <= widget.availableBaseUnits
        ? preferred
        : widget.product.sellingUnits.first;
  }

  int get maxQuantity => widget.availableBaseUnits ~/ selectedUnit.multiplier;

  String _price(SellingUnit unit) =>
      '${widget.currency} ${(unit.price / 100).toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final units = widget.product.sellingUnits;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.product.name,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 5),
            Text(
              'In stock: ${widget.stockLabel}',
              style: TextStyle(fontSize: 12, color: context.stockMuted),
            ),
            const SizedBox(height: 22),
            const Text(
              'How are you adding it?',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (var index = 0; index < units.length; index++) ...[
                  Expanded(
                    child: _UnitChoiceButton(
                      unit: units[index],
                      price: _price(units[index]),
                      selected:
                          selectedUnit.name == units[index].name &&
                          selectedUnit.multiplier == units[index].multiplier,
                      enabled:
                          units[index].multiplier <= widget.availableBaseUnits,
                      onTap: () => setState(() {
                        selectedUnit = units[index];
                        quantity = 1;
                      }),
                    ),
                  ),
                  if (index < units.length - 1) const SizedBox(width: 12),
                ],
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Quantity',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
                IconButton(
                  tooltip: 'Remove one ${selectedUnit.name}',
                  onPressed: quantity > 1
                      ? () => setState(() => quantity--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                SizedBox(
                  width: 38,
                  child: Text(
                    '$quantity',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Add one ${selectedUnit.name}',
                  onPressed: quantity < maxQuantity
                      ? () => setState(() => quantity++)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            if (selectedUnit.multiplier > 1) ...[
              const SizedBox(height: 4),
              Text(
                '1 ${selectedUnit.name} = ${selectedUnit.multiplier} ${widget.product.unit}',
                style: TextStyle(fontSize: 12, color: context.stockMuted),
              ),
            ],
            const SizedBox(height: 22),
            FilledButton(
              onPressed: maxQuantity == 0
                  ? null
                  : () => Navigator.pop(
                      context,
                      _UnitSelection(selectedUnit, quantity),
                    ),
              child: Text('Add $quantity ${selectedUnit.name} to sale'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnitChoiceButton extends StatelessWidget {
  final SellingUnit unit;
  final String price;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _UnitChoiceButton({
    required this.unit,
    required this.price,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? avocado : context.stockLinen,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
        child: Column(
          children: [
            Text(
              '1 ${unit.name}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: enabled ? (selected ? plum : context.stockInk) : context.stockMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              price,
              style: TextStyle(fontSize: 12, color: enabled ? (selected ? plum : context.stockInk) : context.stockMuted),
            ),
          ],
        ),
      ),
    ),
  );
}
