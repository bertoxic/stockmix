import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:stockmix/core/services/media_service.dart';
import 'package:stockmix/core/theme/design.dart';
import 'package:stockmix/features/scanner/scanner_page.dart';
import 'package:stockmix/features/stock/stock_store.dart';
import 'package:stockmix/l10n/app_localizations.dart';

class PhotoInput extends StatefulWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  final ValueChanged<List<String>>? onTextExtracted;
  const PhotoInput({
    super.key,
    this.value,
    required this.onChanged,
    this.onTextExtracted,
  });
  @override
  State<PhotoInput> createState() => _PhotoInputState();
}

class _PhotoInputState extends State<PhotoInput> {
  bool loading = false;
  Future<void> pick(ImageSource source) async {
    setState(() => loading = true);
    try {
      if (widget.onTextExtracted != null) {
        final result = await pickPhotoWithText(source);
        if (result != null && mounted) {
          widget.onChanged(result.base64Image);
          result.extractedText.then((lines) {
            if (mounted && lines.isNotEmpty) {
              widget.onTextExtracted!(lines);
            }
          });
        }
      } else {
        final image = await pickPhoto(source);
        if (image != null && mounted) widget.onChanged(image);
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.value != null) {
      final bytes = ProductImage.decodeBytes(widget.value);
      if (bytes != null) {
        final kb = (widget.value!.length * .75 / 1024).round();
        return Container(
          decoration: BoxDecoration(
            color: context.stockPaper,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: context.stockLine),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Stack(
                children: [
                  Image.memory(
                    bytes,
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.6),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: context.l10n.removePhoto,
                        iconSize: 18,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => widget.onChanged(null),
                        icon: const Icon(Icons.close, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 16,
                      color: avocado,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${context.l10n.photoAttached} · $kb KB',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.stockInk,
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: loading
                          ? null
                          : () => pick(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt_outlined, size: 15),
                      label: Text(
                        context.l10n.takePhoto,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: loading
                          ? null
                          : () => pick(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library_outlined, size: 15),
                      label: Text(
                        context.l10n.uploadPhoto,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    }

    return Container(
      decoration: BoxDecoration(
        color: context.stockLinen,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.stockLine),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: loading ? null : () => pick(ImageSource.camera),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 13,
                        horizontal: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.stockLine),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.camera_alt_outlined,
                            size: 19,
                            color: context.stockInk,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            context.l10n.camera,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: context.stockInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: loading ? null : () => pick(ImageSource.gallery),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 13,
                        horizontal: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.stockLine),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.photo_library_outlined,
                            size: 19,
                            color: context.stockInk,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            context.l10n.upload,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: context.stockInk,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (loading)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.detectingText,
                  style: TextStyle(fontSize: 11, color: context.stockMuted),
                ),
              ],
            )
          else
            Text(
              context.l10n.addPhotoPrompt,
              style: TextStyle(fontSize: 11, color: context.stockMuted),
            ),
        ],
      ),
    );
  }
}

class ProductForm extends StatefulWidget {
  final StockStore store;
  final Product? product;
  final String? barcode;
  const ProductForm({
    super.key,
    required this.store,
    this.product,
    this.barcode,
  });
  @override
  State<ProductForm> createState() => _ProductFormState();
}

class _ProductFormState extends State<ProductForm> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name,
      price,
      cost,
      quantity,
      threshold,
      code,
      category,
      unit,
      packSize,
      packPrice;
  late final FocusNode categoryFocus;
  String? photo;
  DateTime? expiryDate;
  String? selectedLabel;
  bool saving = false;
  bool sellsByPack = false;
  String defaultSellingUnit = 'base';
  List<String> nameSuggestions = [];
  double _unitDragDistance = 0;
  @override
  void initState() {
    super.initState();
    final p = widget.product;
    name = TextEditingController(text: p?.name);
    price = TextEditingController(
      text: p == null ? '' : (p.price / 100).toStringAsFixed(2),
    );
    cost = TextEditingController(
      text: p == null ? '0' : (p.cost / 100).toStringAsFixed(2),
    );
    quantity = TextEditingController(text: '0');
    threshold = TextEditingController(text: '${p?.threshold ?? 5}');
    code = TextEditingController(text: p?.barcode ?? widget.barcode);
    category = TextEditingController(text: p?.category ?? '');
    categoryFocus = FocusNode()..addListener(_onCategoryFocusChanged);
    unit = TextEditingController(text: p?.unit ?? 'pcs');
    packSize = TextEditingController(text: '${p?.packSize ?? 10}');
    packPrice = TextEditingController(
      text: p?.packPrice == null
          ? ''
          : (p!.packPrice! / 100).toStringAsFixed(2),
    );
    sellsByPack = p?.sellsByPack ?? false;
    defaultSellingUnit = p?.defaultSellingUnit ?? 'base';
    photo = p?.photo;
    expiryDate = p?.expiryDate;
    selectedLabel = p?.label;
  }

  bool get _addingBlockedByCount =>
      widget.product == null && widget.store.count != null;

  void _onCategoryFocusChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _cancelActiveCount() async {
    final scope = widget.store.count?['scope'] ?? 'All items';
    final shouldCancel = await confirm(
      context,
      context.l10n.cancelActiveStockCountTitle,
      context.l10n.cancelActiveStockCountMessage(scope),
      action: context.l10n.cancelCountAction,
    );
    if (!shouldCancel) return;
    try {
      await widget.store.cancelCount();
      if (mounted) {
        setState(() {});
        showMessage(context, context.l10n.stockCountCancelledMsg);
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    }
  }

  @override
  void dispose() {
    categoryFocus
      ..removeListener(_onCategoryFocusChanged)
      ..dispose();
    for (final c in [
      name,
      price,
      cost,
      quantity,
      threshold,
      code,
      category,
      unit,
      packSize,
      packPrice,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? number(String? value) =>
      int.tryParse(value ?? '') == null ||
          int.parse(value!) < 0 ||
          int.parse(value) > 100000000
      ? context.l10n.wholeNumberValidation
      : null;
  String? money(String? value) {
    try {
      parseMoney(value ?? '');
      return null;
    } catch (_) {
      return context.l10n.validPriceValidation;
    }
  }

  bool get _isSellingAtLoss {
    try {
      final p = parseMoney(price.text);
      final c = parseMoney(cost.text);
      return c > p;
    } catch (_) {
      return false;
    }
  }

  List<String> get _availableLabels {
    final labels = List<String>.from(widget.store.itemLabels);
    final selected = selectedLabel?.trim();
    if (selected != null &&
        selected.isNotEmpty &&
        !labels.any((label) => label.toLowerCase() == selected.toLowerCase())) {
      labels.add(selected);
    }
    return labels;
  }

  List<String> get _categorySuggestions {
    final query = category.text.trim().toLowerCase();
    final all = <String>{};
    for (final p in widget.store.products) {
      final c = p.category.trim();
      if (c.isNotEmpty) all.add(c);
    }
    const defaults = [
      'General',
      'Food & Drinks',
      'Medicine',
      'Cosmetics',
      'Household',
      'Groceries',
      'Clothing',
      'Electronics',
    ];
    for (final d in defaults) {
      all.add(d);
    }
    if (query.isEmpty) {
      return all.take(5).toList();
    }
    return all
        .where(
          (c) => c.toLowerCase().contains(query) && c.toLowerCase() != query,
        )
        .take(5)
        .toList();
  }

  Future<void> save() async {
    if (_addingBlockedByCount) return;
    if (!form.currentState!.validate()) return;
    if (_isSellingAtLoss) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: rust),
              const SizedBox(width: 8),
              Text(context.l10n.costHigherThanPrice),
            ],
          ),
          content: Text(
            context.l10n.costHigherThanPriceMessage,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.l10n.cancelAndEdit),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: rust),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.l10n.saveAnyway),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    setState(() => saving = true);
    try {
      await widget.store.saveProduct(
        Product(
          id: widget.product?.id ?? newId(),
          name: name.text.trim(),
          category: category.text.trim().isEmpty
              ? 'General'
              : category.text.trim(),
          barcode: code.text.trim(),
          price: parseMoney(price.text),
          cost: parseMoney(cost.text),
          opening: widget.product?.opening ?? int.parse(quantity.text),
          threshold: int.parse(threshold.text),
          unit: unit.text.trim().isEmpty ? 'pcs' : unit.text.trim(),
          photo: photo,
          expiryDate: expiryDate,
          label: selectedLabel,
          packSize: sellsByPack ? int.parse(packSize.text) : 1,
          packPrice: sellsByPack ? parseMoney(packPrice.text) : null,
          defaultSellingUnit: sellsByPack ? defaultSellingUnit : 'base',
        ),
      );
      if (mounted) {
        Navigator.pop(context);
        showMessage(
          context,
          widget.product == null
              ? context.l10n.itemAddedToStockBook
              : context.l10n.itemUpdated,
        );
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  static const List<String> _commonUnits = [
    'pcs',
    'box',
    'pack',
    'bottle',
    'can',
    'sachet',
    'bag',
    'kg',
    'g',
    'ltr',
    'card',
    'strip',
    'pair',
    'roll',
    'carton',
    'tray',
    'set',
    'tube',
  ];

  List<String> get _availableUnits {
    final list = <String>[..._commonUnits];
    for (final p in widget.store.products) {
      final u = p.unit.trim();
      if (u.isNotEmpty &&
          !list.any((e) => e.toLowerCase() == u.toLowerCase())) {
        list.add(u);
      }
    }
    return list;
  }

  void _cycleUnit(int direction) {
    final units = _availableUnits;
    if (units.isEmpty) return;
    final current = unit.text.trim().toLowerCase();
    final idx = units.indexWhere((u) => u.toLowerCase() == current);
    int nextIdx;
    if (idx == -1) {
      nextIdx = direction > 0 ? 0 : units.length - 1;
    } else {
      nextIdx = (idx + direction) % units.length;
      if (nextIdx < 0) nextIdx += units.length;
    }
    setState(() {
      unit.text = units[nextIdx];
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.product == null ? context.l10n.addAnItem : context.l10n.editItem),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.product == null
                    ? context.l10n.makeRoomForNew
                    : context.l10n.theLittleDetails,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.clearNamePriceReady,
                style: TextStyle(color: context.stockMuted),
              ),
              if (_addingBlockedByCount) ...[
                const SizedBox(height: 18),
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
                              context.l10n.addingItemsPaused,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        context.l10n.stockCountActiveNotice(widget.store.count?['scope'] ?? 'All items'),
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
              const SizedBox(height: 24),
              PhotoInput(
                value: photo,
                onChanged: (v) => setState(() => photo = v),
                onTextExtracted: (lines) {
                  if (!mounted || lines.isEmpty) return;
                  setState(() {
                    if (name.text.trim().isEmpty) {
                      name.text = lines.first;
                      nameSuggestions = lines.skip(1).take(6).toList();
                      showMessage(context, context.l10n.autoFilledNamePhoto);
                    } else {
                      nameSuggestions = lines.take(6).toList();
                    }
                  });
                },
              ),
              const SizedBox(height: 22),
              TextFormField(
                controller: name,
                maxLength: 100,
                decoration: InputDecoration(labelText: context.l10n.itemName),
                validator: (v) => v == null || v.trim().isEmpty
                    ? context.l10n.giveItemName
                    : null,
              ),
              if (nameSuggestions.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 14, color: avocado),
                    const SizedBox(width: 6),
                    Text(
                      context.l10n.detectedFromPhoto,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.stockMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => setState(() => nameSuggestions.clear()),
                      child: Text(
                        context.l10n.dismiss,
                        style: TextStyle(
                          fontSize: 11,
                          color: context.stockMuted,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final text in nameSuggestions)
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 14),
                        label: Text(text, style: const TextStyle(fontSize: 12)),
                        onPressed: () {
                          setState(() {
                            if (name.text.trim().isEmpty) {
                              name.text = text;
                            } else if (!name.text.contains(text)) {
                              name.text = '${name.text.trim()} $text';
                            } else {
                              name.text = text;
                            }
                          });
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              TextFormField(
                controller: code,
                maxLength: 250,
                decoration: InputDecoration(
                  labelText: context.l10n.barcodeItemCode,
                  suffixIcon: IconButton(
                    tooltip: context.l10n.scanBarcode,
                    onPressed: () async {
                      final result = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(builder: (_) => const ScannerPage()),
                      );
                      if (result != null) code.text = result;
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: price,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: context.l10n.sellingPriceWithCurrency(widget.store.currency),
                      ),
                      validator: money,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: cost,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: context.l10n.costPriceLabel,
                      ),
                      validator: money,
                    ),
                  ),
                ],
              ),
              if (_isSellingAtLoss) ...[
                const SizedBox(height: 10),
                Surface(
                  color: context.stockRust.withValues(alpha: 0.1),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: context.stockRust,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          context.l10n.sellingAtLossWarning,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: context.stockRust,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (widget.product == null) ...[
                TextFormField(
                  controller: quantity,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: context.l10n.openingStock),
                  validator: number,
                ),
                const SizedBox(height: 20),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFormField(
                          controller: category,
                          focusNode: categoryFocus,
                          maxLength: 40,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            labelText: context.l10n.categoryLabel,
                          ),
                        ),
                        if (categoryFocus.hasFocus &&
                            _categorySuggestions.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              for (final cat in _categorySuggestions)
                                ActionChip(
                                  avatar: const Icon(
                                    Icons.label_outline,
                                    size: 12,
                                  ),
                                  label: Text(
                                    cat,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    setState(() {
                                      category.text = cat;
                                    });
                                  },
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Listener(
                      key: const Key('unit_field_listener'),
                      behavior: HitTestBehavior.translucent,
                      onPointerDown: (e) {
                        _unitDragDistance = 0;
                      },
                      onPointerMove: (e) {
                        _unitDragDistance += e.delta.dx;
                      },
                      onPointerUp: (e) {
                        if (_unitDragDistance < -20) {
                          _cycleUnit(1);
                        } else if (_unitDragDistance > 20) {
                          _cycleUnit(-1);
                        }
                        _unitDragDistance = 0;
                      },
                      child: TextFormField(
                        key: const Key('unit_field'),
                        controller: unit,
                        maxLength: 12,
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: context.l10n.unitPcsBox,
                          prefixIcon: IconButton(
                            icon: const Icon(
                              Icons.chevron_left_rounded,
                              size: 20,
                            ),
                            tooltip: context.l10n.previousUnit,
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _cycleUnit(-1),
                          ),
                          suffixIcon: IconButton(
                            icon: const Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                            ),
                            tooltip: context.l10n.nextUnit,
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _cycleUnit(1),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.sellByPackToo),
                subtitle: Text(
                  sellsByPack
                      ? context.l10n.sellByPackSubtitleOn(unit.text.trim().isEmpty ? context.l10n.baseUnit : unit.text.trim())
                      : context.l10n.sellByPackSubtitleOff,
                  style: TextStyle(fontSize: 11, color: context.stockMuted),
                ),
                value: sellsByPack,
                onChanged: (value) => setState(() {
                  sellsByPack = value;
                  if (!value) defaultSellingUnit = 'base';
                }),
              ),
              if (sellsByPack) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: packSize,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: context.l10n.baseUnitsPerPack(unit.text.trim().isEmpty ? context.l10n.baseUnit : unit.text.trim()),
                        ),
                        validator: (value) {
                          final parsed = int.tryParse(value ?? '');
                          if (parsed == null ||
                              parsed < 2 ||
                              parsed > 1000000) {
                            return context.l10n.enterPackRange(2, 1000000);
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: packPrice,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: context.l10n.packPriceWithCurrency(widget.store.currency),
                        ),
                        validator: money,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'base',
                      label: Text(
                        unit.text.trim().isEmpty
                            ? context.l10n.baseUnit
                            : unit.text.trim(),
                      ),
                    ),
                    ButtonSegment(value: 'pack', label: Text(context.l10n.pack)),
                  ],
                  selected: {defaultSellingUnit},
                  onSelectionChanged: (selection) =>
                      setState(() => defaultSellingUnit = selection.first),
                ),
                const SizedBox(height: 5),
                Text(
                  context.l10n.preselectedAfterScan,
                  style: TextStyle(fontSize: 11, color: context.stockMuted),
                ),
              ],
              const SizedBox(height: 14),
              TextFormField(
                controller: threshold,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.l10n.reorderAlertAt,
                ),
                validator: number,
              ),
              if (widget.store.showExpiryDateField || expiryDate != null) ...[
                const SizedBox(height: 14),
                Material(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () async {
                      final now = DateTime.now();
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: expiryDate ?? now,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(now.year + 100),
                      );
                      if (selected != null && mounted) {
                        setState(() => expiryDate = selected);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: context.stockLine),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.event_outlined, color: context.stockInk),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  context.l10n.expiryDate,
                                  style: const TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  expiryDate == null
                                      ? context.l10n.notSet
                                      : DateFormat(
                                          'EEE, d MMM yyyy',
                                        ).format(expiryDate!),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.stockMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (expiryDate != null)
                            IconButton(
                              tooltip: context.l10n.clearExpiryDate,
                              icon: const Icon(Icons.close),
                              onPressed: () =>
                                  setState(() => expiryDate = null),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              if ((widget.store.showItemLabels &&
                      widget.store.itemLabels.isNotEmpty) ||
                  selectedLabel != null) ...[
                const SizedBox(height: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.labelTag,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _availableLabels.map((label) {
                        final isSelected = selectedLabel == label;
                        return TextButton(
                          style: TextButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            foregroundColor: isSelected
                                ? context.stockInk
                                : context.stockMuted,
                            side: BorderSide(
                              color: isSelected ? avocado : context.stockLine,
                              width: isSelected ? 1.5 : 1,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                          onPressed: () => setState(
                            () => selectedLabel = isSelected ? null : label,
                          ),
                          child: Text(label),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: saving || _addingBlockedByCount ? null : save,
                icon: const Icon(Icons.check),
                label: Text(saving ? context.l10n.savingEllipsis : context.l10n.saveItem),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    ),
  );
}

class AdjustmentPage extends StatefulWidget {
  final StockStore store;
  final Product product;
  final bool receiving;
  const AdjustmentPage({
    super.key,
    required this.store,
    required this.product,
    this.receiving = false,
  });
  @override
  State<AdjustmentPage> createState() => _AdjustmentPageState();
}

class _AdjustmentPageState extends State<AdjustmentPage> {
  final quantity = TextEditingController(text: '1'),
      note = TextEditingController();
  String reason = 'Damage';
  String? photo;
  bool add = false, saving = false;
  String adjustmentUnit = 'base';

  bool get canChoosePack => widget.product.sellsByPack;
  bool get addingStock => widget.receiving || add;
  int get unitMultiplier =>
      adjustmentUnit == 'pack' ? widget.product.packSize : 1;

  @override
  void initState() {
    super.initState();
    if (widget.receiving && widget.product.defaultSellingUnit == 'pack') {
      adjustmentUnit = 'pack';
    }
  }

  @override
  void dispose() {
    quantity.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final qty = int.tryParse(quantity.text);
    if (qty == null || qty <= 0 || qty * unitMultiplier > 100000000) {
      showMessage(context, context.l10n.enterPositiveQuantity);
      return;
    }
    if (note.text.trim().isEmpty) {
      showMessage(context, context.l10n.addSupplierOrReason);
      return;
    }
    setState(() => saving = true);
    try {
      await widget.store.adjust(
        widget.product,
        addingStock ? qty * unitMultiplier : -qty * unitMultiplier,
        widget.receiving ? 'Received' : reason,
        note.text,
        photo: photo,
      );
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, context.l10n.stockUpdatedSaved);
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.receiving ? context.l10n.receiveStockTitle : context.l10n.adjustStockTitle),
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Surface(
              child: Row(
                children: [
                  ProductImage(widget.product),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.product.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${widget.store.stockLabel(widget.product)} ${context.l10n.onHand.toLowerCase()}',
                          style: TextStyle(color: context.stockMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (!widget.receiving) ...[
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(context.l10n.removeStock),
                    icon: const Icon(Icons.remove),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text(context.l10n.addStock),
                    icon: const Icon(Icons.add),
                  ),
                ],
                selected: {add},
                onSelectionChanged: (v) => setState(() {
                  add = v.first;
                  reason = add ? 'Correction' : 'Damage';
                }),
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: reason,
                key: ValueKey(add),
                decoration: InputDecoration(labelText: context.l10n.reasonLabel),
                items:
                    (add
                            ? ['Correction', 'Return restock']
                            : ['Damage', 'Loss', 'Expiry', 'Correction'])
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                onChanged: (v) => setState(() => reason = v!),
              ),
              const SizedBox(height: 20),
            ],
            if (canChoosePack) ...[
              const SizedBox(height: 20),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(
                    value: 'base',
                    label: Text(widget.product.unit),
                  ),
                  ButtonSegment(value: 'pack', label: Text(context.l10n.pack)),
                ],
                selected: {adjustmentUnit},
                onSelectionChanged: (selection) =>
                    setState(() => adjustmentUnit = selection.first),
              ),
              const SizedBox(height: 8),
              Text(
                adjustmentUnit == 'pack'
                    ? context.l10n.packRatioStockSaved(widget.product.packSize, widget.product.unit)
                    : context.l10n.stockSavedIn(widget.product.unit),
                style: TextStyle(fontSize: 11, color: context.stockMuted),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.l10n.quantityWithUnit(adjustmentUnit == 'pack' ? context.l10n.pack : widget.product.unit),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: note,
              maxLength: 500,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: widget.receiving
                    ? context.l10n.supplierReceiptNote
                    : context.l10n.whatHappened,
              ),
            ),
            const SizedBox(height: 20),
            PhotoInput(
              value: photo,
              onChanged: (v) => setState(() => photo = v),
            ),
            const SizedBox(height: 26),
            FilledButton(
              onPressed: saving ? null : save,
              child: Text(
                saving
                    ? context.l10n.savingEllipsis
                    : widget.receiving
                    ? context.l10n.confirmReceipt
                    : context.l10n.recordAdjustment,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
