import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'backup_page.dart';
import 'design.dart';
import 'stock_store.dart';
import 'qr_stream/qr_stream_sender_page.dart';
import 'qr_stream/qr_stream_receiver_page.dart';

class SharePage extends StatefulWidget {
  final StockStore store;
  final DateTime? initialDay;
  final bool startImport;
  const SharePage({
    super.key,
    required this.store,
    this.initialDay,
    this.startImport = false,
  });
  @override
  State<SharePage> createState() => _SharePageState();
}

class _SharePageState extends State<SharePage> {
  late bool daily;
  late DateTime day;
  String format = 'json';
  bool working = false;
  @override
  void initState() {
    super.initState();
    daily = widget.initialDay != null;
    day = widget.initialDay ?? DateTime.now();
    if (widget.startImport) {
      WidgetsBinding.instance.addPostFrameCallback((_) => importFile());
    }
  }

  Future<void> export(bool share, Rect origin) async {
    setState(() => working = true);
    try {
      final data = format == 'json'
          ? jsonEncode(widget.store.bundle(day: daily ? day : null))
          : widget.store.csv(day: daily ? day : null);
      final bytes = Uint8List.fromList(
        utf8.encode(format == 'csv' ? '\uFEFF$data' : data),
      );
      if (bytes.length > 30 * 1024 * 1024 && format == 'json') {
        throw const FormatException(
          'This export exceeds 30 MB. Share individual day records instead.',
        );
      }
      final filename =
          'stockmix-${daily ? dayKey(day) : 'stock-${dayKey(DateTime.now())}'}.$format';
      final mime = format == 'json' ? 'application/json' : 'text/csv';
      if (share) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile.fromData(bytes, mimeType: mime, name: filename)],
            fileNameOverrides: [filename],
            title: daily ? 'Stockmix day record' : 'Stockmix stock snapshot',
            sharePositionOrigin: origin,
          ),
        );
      } else {
        final saved = await FilePicker.saveFile(
          fileName: filename,
          bytes: bytes,
          mimeType: mime,
          dialogTitle: 'Export Stockmix file',
        );
        if (saved != null && mounted) showMessage(context, 'Export saved.');
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> importFile() async {
    if (working) return;
    setState(() => working = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
        dialogTitle: 'Import Stockmix JSON',
      );
      if (file == null) return;
      if (await file.length() > 30 * 1024 * 1024) {
        throw const FormatException('Choose a file smaller than 30 MB.');
      }
      final data = StockStore.decodeBundle(
        utf8.decode(await file.readAsBytes()),
      );
      if (!mounted) return;
      final add = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Review incoming file'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tag(data['kind']),
              const SizedBox(height: 15),
              Text(
                'From ${data['shop']}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                '${(data['products'] as List).length} products · ${(data['movements'] as List).length} stock movements',
              ),
              const SizedBox(height: 15),
              const Text(
                'Save a copy to view in Received records. You can also add new products with their shared stock quantities; existing products and their stock stay unchanged.',
                style: TextStyle(fontSize: 12, height: 1.5),
              ),
              if (data['currency'] != widget.store.currency)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    'File currency: ${data['currency']}. Product import is unavailable because your store uses ${widget.store.currency}.',
                    style: TextStyle(color: context.stockRust, fontSize: 12),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed:
                  data['currency'] != widget.store.currency ||
                      data['kind'] != 'Stock snapshot'
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Also add new products'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Save record'),
            ),
          ],
        ),
      );
      if (add == null) return;
      await widget.store.importBundle(data, addProducts: add);
      if (mounted) {
        showMessage(
          context,
          add
              ? 'Record saved and new products imported. Existing items were skipped.'
              : 'Saved in Received records. Your inventory is unchanged.',
        );
      }
    } catch (e) {
      if (mounted) {
        showMessage(
          context,
          e is TypeError
              ? 'This file is not a valid Stockmix export.'
              : friendlyError(e),
        );
      }
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Share & export')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Eyebrow('Good records travel well'),
            const SizedBox(height: 12),
            Text(
              'Keep a copy.\nKeep everyone in the loop.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 24),
            Surface(
              color: avocado,
              child: Row(
                children: [
                  const Icon(Icons.folder_shared_outlined, size: 45),
                  const SizedBox(width: 18),
                  const Expanded(
                    child: Text(
                      'Your stock book,\nready to go.',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            const Eyebrow('What would you like to send?'),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Stock'),
                  icon: Icon(Icons.inventory_2_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Day record'),
                  icon: Icon(Icons.receipt_long_outlined),
                ),
              ],
              selected: {daily},
              onSelectionChanged: working
                  ? null
                  : (s) => setState(() => daily = s.first),
            ),
            const SizedBox(height: 16),
            if (daily) ...[
              OutlinedButton.icon(
                onPressed: () async {
                  final value = await showDatePicker(
                    context: context,
                    initialDate: day,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (value != null) setState(() => day = value);
                },
                icon: const Icon(Icons.calendar_today_outlined, size: 17),
                label: Text(DateFormat('d MMMM yyyy').format(day)),
              ),
              const SizedBox(height: 16),
            ],
            Surface(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 5),
              child: Column(
                children: [
                  formatOption(
                    'json',
                    'Stockmix file',
                    'Products, prices, records, and compressed photos. Import into Stockmix.',
                    Icons.description_outlined,
                  ),
                  const Divider(),
                  formatOption(
                    'csv',
                    'Spreadsheet · CSV',
                    'A simple table for Excel or Google Sheets. Photos are not included.',
                    Icons.table_chart_outlined,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 23),
            FilledButton.icon(
              onPressed: working
                  ? null
                  : () {
                      final bundle = widget.store.bundle(
                        day: daily ? day : null,
                      );
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => QrStreamSenderPage(
                            store: widget.store,
                            bundle: bundle,
                          ),
                        ),
                      );
                    },
              icon: const Icon(Icons.qr_code_2_rounded, size: 22),
              label: const Text('Stream via animated QR code'),
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (ctx) => OutlinedButton.icon(
                onPressed: working
                    ? null
                    : () {
                        final box = ctx.findRenderObject() as RenderBox;
                        export(true, box.localToGlobal(Offset.zero) & box.size);
                      },
                icon: const Icon(Icons.ios_share_outlined, size: 20),
                label: Text(
                  working ? 'Preparing…' : 'Share file with another user',
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: working ? null : () => export(false, Rect.zero),
              icon: const Icon(Icons.download_outlined, size: 20),
              label: const Text('Save as a file'),
            ),
            const SizedBox(height: 22),
            Surface(
              color: linen,
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.qr_code_scanner, size: 18, color: context.stockInk),
                      SizedBox(width: 8),
                      Text(
                        '100% Offline Stream Transfer',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10),
                  Text(
                    'Animated QR streams transfer stock data camera-to-screen with no Wi-Fi, Bluetooth, or Internet required. Fountain coding ensures missing frames reconstruct automatically with duplicate-safe hashcodes.',
                    style: TextStyle(fontSize: 12, color: context.stockMuted, height: 1.6),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Divider(),
            const SizedBox(height: 20),
            Text(
              'Something coming your way?',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: working
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            QrStreamReceiverPage(store: widget.store),
                      ),
                    ),
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
              label: const Text('Scan incoming QR stream'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: working ? null : importFile,
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('Import a Stockmix file'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: working
                  ? null
                  : () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BackupRestorePage(store: widget.store),
                      ),
                    ),
              icon: const Icon(Icons.backup_outlined),
              label: Text(
                widget.store.lastBackupAt == null
                    ? 'Full backup & restore (Not backed up)'
                    : 'Full backup & restore',
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ReceivedPage(store: widget.store),
                ),
              ),
              child: Text(
                'View received records (${widget.store.received.length})',
              ),
            ),
          ],
        ),
      ),
    ),
  );
  Widget formatOption(
    String value,
    String title,
    String subtitle,
    IconData icon,
  ) => ListTile(
    onTap: working ? null : () => setState(() => format = value),
    leading: Icon(icon, color: context.stockMuted),
    title: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        subtitle,
        style: TextStyle(color: context.stockMuted, fontSize: 11, height: 1.5),
      ),
    ),
    trailing: Icon(
      format == value
          ? Icons.radio_button_checked
          : Icons.radio_button_unchecked,
      color: format == value ? context.stockInk : cement,
    ),
  );
}

class ReceivedPage extends StatelessWidget {
  final StockStore store;
  const ReceivedPage({super.key, required this.store});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Received & saved records')),
    body: AnimatedBuilder(
      animation: store,
      builder: (context, _) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (store.received.isEmpty)
                const EmptyState(
                  icon: Icons.move_to_inbox_outlined,
                  title: 'A place for shared records.',
                  subtitle:
                      'Import a Stockmix file or complete a stock count to see it here.',
                ),
              for (final r in store.received.reversed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Material(
                    color: context.stockPaper,
                    borderRadius: BorderRadius.circular(20),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(18),
                      leading: const Icon(Icons.description_outlined),
                      title: Text(
                        '${r['kind']} · ${r['shop']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      subtitle: Text(
                        DateFormat(
                          'd MMM yyyy · h:mm a',
                        ).format(DateTime.parse(r['exportedAt']).toLocal()),
                        style: TextStyle(fontSize: 11, color: context.stockMuted),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Delete record',
                            icon: Icon(
                              Icons.delete_outline,
                              color: context.stockMuted,
                              size: 20,
                            ),
                            onPressed: () async {
                              if (await confirm(
                                context,
                                'Delete saved record?',
                                'This removes "${r['kind']} from ${r['shop']}" from your saved records.',
                                action: 'Delete',
                              )) {
                                try {
                                  await store.deleteReceived(r['id']);
                                  if (context.mounted) {
                                    showMessage(context, 'Record removed.');
                                  }
                                } catch (e) {
                                  if (context.mounted) {
                                    showMessage(context, friendlyError(e));
                                  }
                                }
                              }
                            },
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              SharedRecordPage(record: r, store: store),
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
  );
}

class SharedRecordPage extends StatefulWidget {
  final Map<String, dynamic> record;
  final StockStore? store;
  const SharedRecordPage({super.key, required this.record, this.store});

  @override
  State<SharedRecordPage> createState() => _SharedRecordPageState();
}

enum _CurrencyMergeChoice { cancel, changeLabelOnly, useExchangeRate }

class _ExchangeRateDialog extends StatefulWidget {
  final String sourceCurrency;
  final String targetCurrency;
  const _ExchangeRateDialog({
    required this.sourceCurrency,
    required this.targetCurrency,
  });

  @override
  State<_ExchangeRateDialog> createState() => _ExchangeRateDialogState();
}

class _ExchangeRateDialogState extends State<_ExchangeRateDialog> {
  late final TextEditingController _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = double.tryParse(_controller.text.trim());
    if (parsed == null || !parsed.isFinite || parsed <= 0) {
      setState(() => _error = 'Enter a number greater than zero.');
      return;
    }
    Navigator.pop(context, parsed);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Row(
      children: [
        Icon(Icons.currency_exchange_outlined, color: context.stockInk),
        SizedBox(width: 10),
        Text('Set exchange rate'),
      ],
    ),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 360),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How many ${widget.targetCurrency} equal 1 ${widget.sourceCurrency}?',
            style: TextStyle(fontSize: 13, color: context.stockMuted),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: InputDecoration(
              labelText: 'Your conversion rate',
              prefixText: '1 ${widget.sourceCurrency} = ',
              suffixText: widget.targetCurrency,
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Text(
            'Stock quantities will stay the same. We will convert item prices, costs, sales, and refunds before merging.',
            style: TextStyle(fontSize: 11, color: context.stockMuted, height: 1.45),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _submit,
        child: const Text('Use this rate'),
      ),
    ],
  );
}

class _SharedRecordPageState extends State<SharedRecordPage> {
  bool merging = false;

  Future<void> _startMergeFlow() async {
    final store = widget.store;
    if (store == null || merging) return;

    if (store.count != null) {
      showMessage(
        context,
        'Cannot merge: Finish the stock count before merging items.',
      );
      return;
    }

    final r = widget.record;
    if (r['currency'] != store.currency) {
      final choice = await showDialog<_CurrencyMergeChoice>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(
            'Choose how to merge currencies',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          content: Text(
            'This record uses ${r['currency']}; your store uses ${store.currency}. Choose how amounts from this record should be added to your store.',
            style: TextStyle(fontSize: 13, color: context.stockMuted, height: 1.45),
          ),
          actions: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () =>
                      Navigator.pop(ctx, _CurrencyMergeChoice.cancel),
                  child: const Text('Cancel'),
                ),
                const SizedBox(height: 4),
                TextButton(
                  onPressed: () =>
                      Navigator.pop(ctx, _CurrencyMergeChoice.changeLabelOnly),
                  child: const Text('Change label only'),
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(ctx, _CurrencyMergeChoice.useExchangeRate),
                  child: const Text('Use my exchange rate'),
                ),
              ],
            ),
          ],
        ),
      );

      if (choice == null || choice == _CurrencyMergeChoice.cancel) return;
      if (choice == _CurrencyMergeChoice.changeLabelOnly) {
        await _handleMerge(exchangeRate: 1.0, isLabelOnly: true);
        return;
      }
      if (choice == _CurrencyMergeChoice.useExchangeRate) {
        await _promptForExchangeRate();
        return;
      }
    } else {
      await _handleMerge();
    }
  }

  Future<void> _handleMerge({
    double? exchangeRate,
    bool isLabelOnly = false,
  }) async {
    final store = widget.store;
    if (store == null || merging) return;

    final r = widget.record;
    if (r['currency'] != store.currency && exchangeRate == null) {
      await _startMergeFlow();
      return;
    }
    if (store.count != null) {
      showMessage(
        context,
        'Cannot merge: Finish the stock count before merging items.',
      );
      return;
    }

    Map<String, dynamic> preview;
    try {
      preview = store.previewMerge(r['id'], exchangeRate: exchangeRate);
    } catch (e) {
      showMessage(context, friendlyError(e));
      return;
    }

    final stockChanges =
        (preview['stockChanges'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];
    final newProductsCount = preview['newProductsCount'] as int? ?? 0;
    final newMovementsCount = preview['newMovementsCount'] as int? ?? 0;
    final backfilledPhotosCount = preview['backfilledPhotosCount'] as int? ?? 0;
    final isDayRecord = r['kind'] == 'Day record';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.preview_outlined, size: 24),
            SizedBox(width: 8),
            Text('Merge preview'),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460, maxHeight: 420),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDayRecord
                      ? 'Review incoming day movements and see how your on-hand stock balances will adjust:'
                      : 'Review new products and quantities to be imported into your store:',
                  style: TextStyle(
                    fontSize: 13,
                    color: context.stockMuted,
                    height: 1.4,
                  ),
                ),
                if (exchangeRate != null &&
                    r['currency'] != store.currency) ...[
                  const SizedBox(height: 12),
                  Surface(
                    color: linen,
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      isLabelOnly
                          ? 'Amounts will be kept as-is and labeled in ${store.currency} without currency conversion (label change only). Stock quantities stay the same.'
                          : 'Using your rate: 1 ${r['currency']} = ${exchangeRate.toStringAsFixed(4)} ${store.currency}. All monetary values will be converted; stock quantities stay the same.',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.stockMuted,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                if (stockChanges.isEmpty)
                  Surface(
                    color: paper,
                    padding: const EdgeInsets.all(12),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          color: avocado,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'No on-hand stock balances will change. Existing items remain at their current counts.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  const Text(
                    'Stock balance changes:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Surface(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        for (final sc in stockChanges)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              sc['name'] ?? '',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 13,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (sc['isNew'] == true) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 1,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: avocado.withValues(
                                                  alpha: .3,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'New item',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${sc['currentStock']} → ${sc['newStock']}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      ),
                                    ),
                                    Text(
                                      '${(sc['delta'] as int) > 0 ? '+' : ''}${sc['delta']} ${sc['unit']}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: (sc['delta'] as int) < 0
                                            ? context.stockRust
                                            : context.stockPositive,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (newProductsCount > 0)
                      Tag('+$newProductsCount new products', color: avocado),
                    if (newMovementsCount > 0)
                      Tag('+$newMovementsCount movements', color: paper),
                    if (backfilledPhotosCount > 0)
                      Tag(
                        '+$backfilledPhotosCount photos backfilled',
                        color: paper,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Apply merge'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => merging = true);
    try {
      final res = await store.mergeReceived(
        r['id'],
        exchangeRate: exchangeRate,
      );
      if (mounted) {
        final newP = res['newProducts'] ?? 0;
        final backP = res['backfilledPhotos'] ?? 0;
        final newM = res['newMovements'] ?? 0;
        final skippedP = res['skippedProducts'] ?? 0;

        final parts = <String>[];
        if (newP > 0) {
          parts.add('$newP new product${newP == 1 ? '' : 's'} added');
        }
        if (backP > 0) {
          parts.add('$backP photo${backP == 1 ? '' : 's'} updated');
        }
        if (newM > 0) {
          parts.add('$newM movement${newM == 1 ? '' : 's'} recorded');
        }
        if (skippedP > 0) {
          parts.add(
            '$skippedP existing item${skippedP == 1 ? '' : 's'} stock unchanged',
          );
        }

        showMessage(
          context,
          parts.isEmpty
              ? 'Inventory is already up to date.'
              : 'Merged: ${parts.join(', ')}.',
        );
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => merging = false);
    }
  }

  Future<void> _promptForExchangeRate() async {
    final store = widget.store;
    if (store == null || merging) return;
    final r = widget.record;
    final sourceCurrency = r['currency'] as String? ?? 'record currency';

    final rate = await showDialog<double>(
      context: context,
      builder: (ctx) => _ExchangeRateDialog(
        sourceCurrency: sourceCurrency,
        targetCurrency: store.currency,
      ),
    );
    if (rate != null && mounted) {
      await _handleMerge(exchangeRate: rate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    final store = widget.store;
    final products = r['products'] as List? ?? [];
    final movements = r['movements'] as List? ?? [];
    String price(int value) =>
        '${r['currency'] ?? ''} ${(value / 100).toStringAsFixed(2)}';
    return Scaffold(
      appBar: AppBar(
        title: Text(r['kind']),
        actions: [
          if (store != null)
            IconButton(
              tooltip: 'Delete record',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(
                  context,
                  'Delete this record?',
                  'This removes this saved record. Your active store inventory will not be affected.',
                  action: 'Delete',
                )) {
                  try {
                    await store.deleteReceived(r['id']);
                    if (context.mounted) {
                      Navigator.pop(context);
                      showMessage(context, 'Record deleted.');
                    }
                  } catch (e) {
                    if (context.mounted) showMessage(context, friendlyError(e));
                  }
                }
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Eyebrow('Saved copy'),
              const SizedBox(height: 12),
              Text(r['shop'], style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(height: 10),
              Text(
                DateFormat(
                  'd MMM yyyy · h:mm a',
                ).format(DateTime.parse(r['exportedAt']).toLocal()),
                style: TextStyle(color: context.stockMuted),
              ),
              const SizedBox(height: 25),
              if (r['kind'] == 'Posted count') ...[
                for (final entry in (r['count']['baseline'] as Map).entries)
                  Surface(
                    child: Text(
                      '${r['count']['names']?[entry.key] ?? entry.key}\nExpected ${entry.value} · Counted ${r['count']['values'][entry.key]}',
                    ),
                  ),
              ] else ...[
                if (r['kind'] == 'Day record')
                  Surface(
                    color: avocado,
                    child: Text(
                      'Sales: ${price(movements.where((m) => m['type'] == 'Sale').fold<int>(0, (n, m) => n - (m['delta'] as int) * (m['price'] as int)))}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 24,
                      ),
                    ),
                  ),
                const SizedBox(height: 15),
                Text(
                  r['kind'] == 'Stock snapshot'
                      ? 'Shared inventory'
                      : 'Stock movements',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                if (r['kind'] == 'Stock snapshot')
                  ...products.map((raw) {
                    final p = Product.fromJson(Map<String, dynamic>.from(raw));
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Surface(
                        child: Row(
                          children: [
                            ProductImage(p),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    p.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${raw['onHand']} ${p.unit} · ${price(p.price)}',
                                    style: TextStyle(
                                      color: context.stockMuted,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  })
                else
                  ...movements.map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Surface(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              m['name'],
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              '${m['type']} · ${m['delta']} units · ${price(m['price'])} each',
                              style: TextStyle(
                                color: context.stockMuted,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(m['note']),
                            if (m['photo'] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 14),
                                child: Image.memory(
                                  base64Decode(m['photo']),
                                  height: 160,
                                  errorBuilder: (_, _, _) =>
                                      const Text('Photo unavailable'),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
              if (store != null) ...[
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 18),
                if (['Stock snapshot', 'Day record'].contains(r['kind'])) ...[
                  FilledButton.icon(
                    onPressed: merging ? null : _startMergeFlow,
                    icon: merging
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.call_merge_rounded, size: 20),
                    label: Text(
                      merging
                          ? 'Merging into inventory…'
                          : 'Merge into store stock',
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Imports new products and day movements. Shows a stock balance preview before changes are applied.',
                    style: TextStyle(fontSize: 11, color: context.stockMuted, height: 1.4),
                  ),
                  const SizedBox(height: 18),
                ],
                OutlinedButton.icon(
                  onPressed: () async {
                    if (await confirm(
                      context,
                      'Delete this record?',
                      'This removes this saved record from your device. Your active inventory is unchanged.',
                      action: 'Delete',
                    )) {
                      try {
                        await store.deleteReceived(r['id']);
                        if (context.mounted) {
                          Navigator.pop(context);
                          showMessage(context, 'Record deleted.');
                        }
                      } catch (e) {
                        if (context.mounted) {
                          showMessage(context, friendlyError(e));
                        }
                      }
                    }
                  },
                  icon: Icon(Icons.delete_outline, color: context.stockRust),
                  label: Text(
                    'Delete this record',
                    style: TextStyle(color: context.stockRust),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
