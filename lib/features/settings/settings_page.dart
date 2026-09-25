import 'package:flutter/material.dart';
import 'package:stockmix/core/services/scan_feedback.dart';
import 'package:stockmix/core/theme/design.dart';
import 'package:stockmix/features/app/pages.dart';
import 'package:stockmix/features/settings/backup_page.dart';
import 'package:stockmix/features/settings/privacy_policy_page.dart';
import 'package:stockmix/features/stock/stock_store.dart';
import 'package:stockmix/l10n/app_localizations.dart';

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
  late String _language;
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
    _language = store.languageCode ?? 'system';
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
        languageCode: _language,
      );
      ScanFeedback.soundEnabled = _sound;
      ScanFeedback.hapticsEnabled = _haptics;

      if (mounted) {
        showMessage(context, context.l10n.storeSettingsUpdated);
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Row(
                  children: [
                    const Icon(Icons.payments_outlined),
                    const SizedBox(width: 10),
                    Text(
                      sheetContext.l10n.displayCurrency,
                      style: const TextStyle(
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
                  sheetContext.l10n.chooseCurrencyDescription,
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

  String get _currentLanguageLabel {
    if (_language == 'system') return 'Match System';
    final match = AppLocalizations.supportedLanguages.where((l) => l.code == _language);
    if (match.isNotEmpty) return match.first.englishName;
    return _language;
  }

  String get _currentLanguageNative {
    if (_language == 'system') return 'System default';
    final match = AppLocalizations.supportedLanguages.where((l) => l.code == _language);
    if (match.isNotEmpty) return match.first.name;
    return _language;
  }

  Future<void> _pickLanguage() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
        child: Container(
          height: MediaQuery.sizeOf(sheetContext).height * .75,
          decoration: BoxDecoration(
            color: sheetContext.stockPaper,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: sheetContext.stockLine,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: Row(
                  children: [
                    Text(
                      sheetContext.l10n.selectLanguage,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: sheetContext.l10n.close,
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 22),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    sheetContext.l10n.chooseLanguageDescription,
                    style: TextStyle(
                      fontSize: 12,
                      color: sheetContext.stockMuted,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    _languageItem(
                      sheetContext,
                      code: 'system',
                      nativeName: sheetContext.l10n.systemDefault,
                      englishName: sheetContext.l10n.matchSystemTheme,
                      isSelected: _language == 'system',
                    ),
                    const SizedBox(height: 8),
                    for (final lang in AppLocalizations.supportedLanguages) ...[
                      _languageItem(
                        sheetContext,
                        code: lang.code,
                        nativeName: lang.name,
                        englishName: lang.englishName,
                        isSelected: _language == lang.code,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() => _language = selected);
    }
  }

  Widget _languageItem(
    BuildContext sheetContext, {
    required String code,
    required String nativeName,
    required String englishName,
    required bool isSelected,
  }) {
    return Material(
      color: isSelected ? avocado : sheetContext.stockLinen,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.pop(sheetContext, code),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nativeName,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: isSelected ? plum : sheetContext.stockInk,
                      ),
                    ),
                    Text(
                      englishName,
                      style: TextStyle(
                        fontSize: 11,
                        color: isSelected ? plum.withAlpha(200) : sheetContext.stockMuted,
                      ),
                    ),
                  ],
                ),
              ),
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.storeAppSettings),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    context.l10n.save,
                    style: const TextStyle(fontWeight: FontWeight.bold),
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
                Eyebrow(context.l10n.storeIdentity),
                const SizedBox(height: 10),
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _nameController,
                        maxLength: 60,
                        decoration: InputDecoration(
                          labelText: context.l10n.storeName,
                          hintText: context.l10n.storeNameHint,
                          prefixIcon: const Icon(Icons.storefront_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _userNameController,
                        maxLength: 60,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: context.l10n.yourName,
                          hintText: context.l10n.yourNameHint,
                          prefixIcon: const Icon(Icons.person_outline),
                        ),
                      ),
                      Text(
                        context.l10n.yourNameCaption,
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

                // Currency & Display Card
                Eyebrow(context.l10n.currencyAndDisplay),
                const SizedBox(height: 10),
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        button: true,
                        label: context.l10n.displayCurrency,
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
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          context.l10n.displayCurrency,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
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
                        context.l10n.displayCurrencyCaption,
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

                Eyebrow(context.l10n.addItemFields),
                const SizedBox(height: 10),
                Surface(
                  child: Column(
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.event_outlined),
                        title: Text(
                          context.l10n.expiryDate,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          context.l10n.expiryDateSubtitle,
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
                        title: Text(
                          context.l10n.customItemLabels,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          context.l10n.customLabelsSubtitle,
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
                            context.l10n.customLabelsCaption,
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
                              labelText: '${context.l10n.labelTag} ${index + 1}',
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
                Eyebrow(context.l10n.scanFeedbackSounds),
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
                        title: Text(
                          context.l10n.scanAudioTone,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          context.l10n.scanAudioToneSubtitle,
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
                        title: Text(
                          context.l10n.hapticVibration,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: Text(
                          context.l10n.hapticVibrationSubtitle,
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
                Eyebrow(context.l10n.themeAppearance),
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
                            context.l10n.lightThemeDefault,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            context.l10n.lightThemeDescription,
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
                            context.l10n.matchSystemTheme,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            context.l10n.matchSystemThemeDescription,
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
                            context.l10n.darkTheme,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            context.l10n.darkThemeDescription,
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

                Eyebrow(context.l10n.languageAndRegion),
                const SizedBox(height: 10),
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        button: true,
                        label: context.l10n.displayLanguage,
                        child: Material(
                          color: context.stockLinen,
                          borderRadius: BorderRadius.circular(16),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: _pickLanguage,
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
                                      Icons.language_rounded,
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          context.l10n.language,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Text(
                                          _currentLanguageLabel,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: context.stockMuted,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      _currentLanguageNative,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
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
                        context.l10n.languageCaption,
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

                Eyebrow(context.l10n.storeOverviewMetrics),
                const SizedBox(height: 10),
                Surface(
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    secondary: const Icon(Icons.bar_chart_rounded),
                    title: Text(
                      context.l10n.showStoreStats,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.showStoreStatsSubtitle,
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
                  Eyebrow(context.l10n.storeStatistics),
                  const SizedBox(height: 10),
                  Surface(
                    child: Wrap(
                      spacing: 28,
                      runSpacing: 20,
                      children: [
                        _statistic(context.l10n.productsLabel, '${store.products.length}'),
                        _statistic(context.l10n.movementsLabel, '${store.movements.length}'),
                        _statistic(
                          context.l10n.stockValueLabel,
                          money(store, store.valuation),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                Eyebrow(context.l10n.dataManagement),
                const SizedBox(height: 10),
                Surface(
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: avocado.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.settings_backup_restore_outlined,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      context.l10n.fullBackupRestore,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.backupRestoreCaption,
                      style: TextStyle(
                        fontSize: 11,
                        color: context.stockMuted,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right, size: 20),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => BackupRestorePage(store: store),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  onPressed: _saving ? null : _save,
                  child: Text(context.l10n.saveSettings),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton.icon(
                    onPressed: () => showPrivacyPolicyDialog(context),
                    icon: const Icon(Icons.privacy_tip_outlined, size: 18),
                    label: Text(context.l10n.privacyAndDataPolicy),
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
