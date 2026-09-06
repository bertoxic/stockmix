import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'design.dart';
import 'media_service.dart';
import 'scanner_page.dart';
import 'stock_store.dart';

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
          if (result.extractedText.isNotEmpty) {
            widget.onTextExtracted!(result.extractedText);
          }
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
  Widget build(BuildContext context) => Surface(
    color: linen,
    child: Column(
      children: [
        if (widget.value != null) ...[
          Builder(builder: (_) {
            final bytes = ProductImage.decodeBytes(widget.value);
            if (bytes == null) return const SizedBox.shrink();
            return ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                bytes,
                height: 130,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            );
          }),
          const SizedBox(height: 10),
        ],
        Row(
          children: [
            Icon(
              widget.value == null
                  ? Icons.add_photo_alternate_outlined
                  : Icons.check_circle_outline,
              color: muted,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                loading
                    ? 'Compressing photo…'
                    : widget.value == null
                    ? 'Add a photo (optional)'
                    : 'Photo attached · ${(widget.value!.length * .75 / 1024).round()} KB',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (widget.value != null)
              IconButton(
                tooltip: 'Remove photo',
                onPressed: () => widget.onChanged(null),
                icon: const Icon(Icons.close, size: 19),
              ),
          ],
        ),
        if (!loading)
          Row(
            children: [
              TextButton.icon(
                onPressed: () => pick(ImageSource.camera),
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: const Text('Camera'),
              ),
              TextButton.icon(
                onPressed: () => pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 18),
                label: const Text('Upload'),
              ),
            ],
          ),
        const Text(
          'Photos are resized and compressed before saving.',
          style: TextStyle(fontSize: 11, color: muted),
        ),
      ],
    ),
  );
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
      unit;
  String? photo;
  bool saving = false;
  List<String> nameSuggestions = [];
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
    category = TextEditingController(text: p?.category ?? 'General');
    unit = TextEditingController(text: p?.unit ?? 'pcs');
    photo = p?.photo;
  }

  @override
  void dispose() {
    for (final c in [
      name,
      price,
      cost,
      quantity,
      threshold,
      code,
      category,
      unit,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? number(String? value) =>
      int.tryParse(value ?? '') == null ||
          int.parse(value!) < 0 ||
          int.parse(value) > 100000000
      ? 'Enter a whole number, 0–100 million'
      : null;
  String? money(String? value) {
    try {
      parseMoney(value ?? '');
      return null;
    } catch (_) {
      return 'Use a valid price, e.g. 12.50';
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
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
        ),
      );
      if (mounted) {
        Navigator.pop(context);
        showMessage(
          context,
          widget.product == null
              ? 'Item added to your stock book.'
              : 'Item updated.',
        );
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
      title: Text(widget.product == null ? 'Add an item' : 'Edit item'),
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
                    ? 'Make room for something new.'
                    : 'The little details.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'A clear name, a price, and you’re ready to go.',
                style: TextStyle(color: muted),
              ),
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
                      showMessage(context, 'Auto-filled item name from photo');
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
                decoration: const InputDecoration(labelText: 'Item name'),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Give this item a name'
                    : null,
              ),
              if (nameSuggestions.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.auto_awesome, size: 14, color: avocado),
                    const SizedBox(width: 6),
                    const Text(
                      'Detected from photo (tap to use):',
                      style: TextStyle(
                        fontSize: 11,
                        color: muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => setState(() => nameSuggestions.clear()),
                      child: const Text(
                        'Dismiss',
                        style: TextStyle(fontSize: 11, color: muted),
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
                  labelText: 'Barcode / item code',
                  suffixIcon: IconButton(
                    tooltip: 'Scan barcode',
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
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Selling price (${widget.store.currency})',
                      ),
                      validator: money,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: cost,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Cost price',
                      ),
                      validator: money,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (widget.product == null) ...[
                TextFormField(
                  controller: quantity,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Opening stock'),
                  validator: number,
                ),
                const SizedBox(height: 20),
              ],
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: category,
                      maxLength: 40,
                      decoration: const InputDecoration(labelText: 'Category'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: unit,
                      maxLength: 12,
                      decoration: const InputDecoration(
                        labelText: 'Unit (pcs, box…)',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: threshold,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Low-stock alert at',
                ),
                validator: number,
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: saving ? null : save,
                icon: const Icon(Icons.check),
                label: Text(saving ? 'Saving…' : 'Save item'),
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
  @override
  void dispose() {
    quantity.dispose();
    note.dispose();
    super.dispose();
  }

  Future<void> save() async {
    final qty = int.tryParse(quantity.text);
    if (qty == null || qty <= 0 || qty > 100000000) {
      showMessage(context, 'Enter a positive whole quantity.');
      return;
    }
    if (note.text.trim().isEmpty) {
      showMessage(context, 'Add a supplier or a reason for the change.');
      return;
    }
    setState(() => saving = true);
    try {
      await widget.store.adjust(
        widget.product,
        widget.receiving || add ? qty : -qty,
        widget.receiving ? 'Received' : reason,
        note.text,
        photo: photo,
      );
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, 'Stock updated and saved on this device.');
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
      title: Text(widget.receiving ? 'Receive stock' : 'Adjust stock'),
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
                          '${widget.store.stock(widget.product)} ${widget.product.unit} on hand',
                          style: const TextStyle(color: muted),
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
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('Remove stock'),
                    icon: Icon(Icons.remove),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Add stock'),
                    icon: Icon(Icons.add),
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
                decoration: const InputDecoration(labelText: 'Reason'),
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
            TextField(
              controller: quantity,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Quantity'),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: note,
              maxLength: 500,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: widget.receiving
                    ? 'Supplier / receipt note'
                    : 'What happened?',
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
                    ? 'Saving…'
                    : widget.receiving
                    ? 'Confirm receipt'
                    : 'Record adjustment',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
