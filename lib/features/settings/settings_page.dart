import 'package:flutter/material.dart';
import 'package:stockmix/core/services/scan_feedback.dart';
import 'package:stockmix/core/theme/design.dart';
import 'package:stockmix/features/app/pages.dart';
import 'package:stockmix/features/settings/privacy_policy_page.dart';
import 'package:stockmix/features/stock/stock_store.dart';

class StoreSettingsPage extends StatefulWidget {
  final StockStore store;
  const StoreSettingsPage({super.key, required this.store});

  @override
  State<StoreSettingsPage> createState() => _StoreSettingsPageState();
}

class _StoreSettingsPageState extends State<StoreSettingsPage> {
  late TextEditingController _nameController;
  late TextEditingController _userNameController;
  late String _currency;
  late bool _sound;
  late bool _haptics;
  late String _theme;
  late bool _showStatistics;
  late bool _showExpiryField;
  late bool _showLabels;
  late List<TextEditingController> _labelControllers;
  bool _saving = false;

  StockStore get store => widget.store;

  static const _currencies = [
    'USD',
    'EUR',
    'GBP',
    'NGN',
    'KES',
    'GHS',
    'ZAR',
    'CAD',
    'AUD',
    'INR',
    'JPY',
    'UGX',
    'TZS',
    'RWF',
    'EGP',
    'BRL',
    'MXN',
    'PHP',
    'IDR',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: store.shop);
    _userNameController = TextEditingController(text: store.userName);
    _currency = _currencies.contains(store.currency) ? store.currency : 'USD';
    _sound = store.soundEnabled;
    _haptics = store.hapticsEnabled;
    _theme = store.themeMode;
    _showStatistics = store.showStoreStatistics;
    _showExpiryField = store.showExpiryDateField;
    _showLabels = store.showItemLabels;
    _labelControllers = List.generate(
      3,
      (index) => TextEditingController(
        text: index < store.itemLabels.length ? store.itemLabels[index] : '',
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _userNameController.dispose();
    for (final controller in _labelControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await store.updateSettings(
        storeName: _nameController.text.trim(),
        userName: _userNameController.text.trim(),
        currencyCode: _currency,
        sound: _sound,
        haptics: _haptics,
        theme: _theme,
        showStatistics: _showStatistics,
        showExpiryField: _showExpiryField,
        showLabels: _showLabels,
        labels: _labelControllers.map((controller) => controller.text),
      );
      ScanFeedback.soundEnabled = _sound;
      ScanFeedback.hapticsEnabled = _haptics;

      if (mounted) {
        showMessage(context, 'Store settings updated.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickCurrency() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          height: MediaQuery.sizeOf(sheetContext).height * .72,
          decoration: BoxDecoration(
            color: sheetContext.stockPaper,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: cement,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 18),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    Icon(Icons.payments_outlined),
                    SizedBox(width: 10),
                    Text(
                      'Display currency',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Text(
                  'Choose the currency shown across your store.',
                  style: TextStyle(
                    fontSize: 12,
                    color: sheetContext.stockMuted,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: _currencies.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final currency = _currencies[index];
                    final isSelected = currency == _currency;
                    return Material(
                      color: isSelected ? avocado : sheetContext.stockLinen,
                      borderRadius: BorderRadius.circular(16),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => Navigator.pop(sheetContext, currency),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Text(
                                currency,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: isSelected
                                      ? plum
                                      : sheetContext.stockInk,
                                ),
                              ),
                              const Spacer(),
                              if (isSelected)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: plum,
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
    if (selected != null && mounted) setState(() => _currency = selected);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Store & App Settings'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Save',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                // Store Identity Card
                const Eyebrow('Store Identity'),
                const SizedBox(height: 10),
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _nameController,
                        maxLength: 60,
                        decoration: const InputDecoration(
                          labelText: 'Store name',
                          hintText: 'e.g. Corner Grocery',
                          prefixIcon: Icon(Icons.storefront_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _userNameController,
                        maxLength: 60,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Your name',
                          hintText: 'e.g. Maya Okafor',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                      ),
                      Text(
                        'Shown as the sender on files and QR streams you share. If left blank, your store name is used.',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.stockMuted,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Semantics(
                        button: true,
                        label: 'Display currency',
                        child: Material(
                          color: context.stockLinen,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: _pickCurrency,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: avocado.withValues(alpha: .55),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: const Icon(
                                      Icons.payments_outlined,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Display currency',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        SizedBox(height: 3),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    _currency,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.keyboard_arrow_down_rounded),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Changing currency updates the symbol across items, receipts, and reports. No exchange rate conversion is applied.',
                        style: TextStyle(
                          fontSize: 11,
                          color: context.stockMuted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                const Eyebrow('Add Item Fields'),
                const SizedBox(height: 10),
                Surface(
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.event_outlined),
                        title: const Text(
                          'Expiry date',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          'Show an expiry-date entry when adding or editing an item',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.stockMuted,
                          ),
                        ),
                        value: _showExpiryField,
                        onChanged: _saving
                            ? null
                            : (value) =>
                                  setState(() => _showExpiryField = value),
                      ),
                      const Divider(height: 20),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.sell_outlined),
                        title: const Text(
                          'Label',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          'Show up to three label buttons when adding an item',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.stockMuted,
                          ),
                        ),
                        value: _showLabels,
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _showLabels = value),
                      ),
                      if (_showLabels) ...[
                        const Divider(height: 20),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            'Set up to three labels. They become transparent buttons on the Add Item page.',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.stockMuted,
                              height: 1.4,
                            ),
                          ),
                        ),
                        for (
                          var index = 0;
                          index < _labelControllers.length;
                          index++
                        ) ...[
                          TextField(
                            controller: _labelControllers[index],
                            enabled: !_saving,
                            maxLength: 30,
                            textCapitalization: TextCapitalization.words,
                            decoration: InputDecoration(
                              labelText: 'Label ${index + 1}',
                              hintText: 'e.g. Fragile',
                            ),
                          ),
                          if (index < _labelControllers.length - 1)
                            const SizedBox(height: 8),
                        ],
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Sound & Haptic Feedback
                const Eyebrow('Scan Feedback'),
                const SizedBox(height: 10),
                Surface(
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: avocado.withAlpha(50),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.volume_up_outlined,
                            color: context.stockInk,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Scan audio tone',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          'Plays a crisp tone on accepted barcode scans',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.stockMuted,
                          ),
                        ),
                        value: _sound,
                        onChanged: (val) => setState(() => _sound = val),
                      ),
                      const Divider(height: 20),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: avocado.withAlpha(50),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.vibration_rounded,
                            color: context.stockInk,
                            size: 20,
                          ),
                        ),
                        title: const Text(
                          'Haptic vibration',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          'Vibrates device upon successful barcode scan',
                          style: TextStyle(
                            fontSize: 11,
                            color: context.stockMuted,
                          ),
                        ),
                        value: _haptics,
                        onChanged: (val) => setState(() => _haptics = val),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Theme & Appearance
                const Eyebrow('Theme & Appearance'),
                const SizedBox(height: 10),
                Surface(
                  child: RadioGroup<String>(
                    groupValue: _theme,
                    onChanged: (v) {
                      if (v != null) setState(() => _theme = v);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Light Theme (Default)',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            'Artisanal linen, avocado, and plum palette',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.stockMuted,
                            ),
                          ),
                          value: 'light',
                        ),
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Match System Theme',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            'Adapts automatically to device dark / light mode',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.stockMuted,
                            ),
                          ),
                          value: 'system',
                        ),
                        RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Dark Theme',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            'Warm plum surfaces with linen and avocado accents',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.stockMuted,
                            ),
                          ),
                          value: 'dark',
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                Surface(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.bar_chart_rounded),
                    title: const Text(
                      'Show store statistics',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      'Display product counts, movements, and stock value',
                      style: TextStyle(fontSize: 11, color: context.stockMuted),
                    ),
                    value: _showStatistics,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _showStatistics = value),
                  ),
                ),
                if (_showStatistics) ...[
                  const SizedBox(height: 24),
                  const Eyebrow('Store Statistics'),
                  const SizedBox(height: 10),
                  Surface(
                    child: Wrap(
                      spacing: 28,
                      runSpacing: 20,
                      children: [
                        _statistic('Products', '${store.products.length}'),
                        _statistic('Movements', '${store.movements.length}'),
                        _statistic(
                          'Stock Value',
                          money(store, store.valuation),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: _saving ? null : _save,
                  child: const Text('Save Settings'),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    onPressed: () => showPrivacyPolicyDialog(context),
                    icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                    label: const Text('Privacy & Data Policy'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statistic(String label, String value) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
      ),
      Text(label, style: TextStyle(fontSize: 11, color: context.stockMuted)),
    ],
  );
}
