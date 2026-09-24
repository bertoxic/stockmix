import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:stockmix/core/theme/design.dart';
import 'package:stockmix/features/stock/stock_store.dart';

class BackupRestorePage extends StatefulWidget {
  final StockStore store;
  const BackupRestorePage({super.key, required this.store});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  bool working = false;
  StockStore get store => widget.store;

  String _formatBackupDate(String? iso) {
    if (iso == null) return 'Never backed up';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('d MMM yyyy, h:mm a').format(dt);
    } catch (_) {
      return iso;
    }
  }

  Future<void> _backupNow({required bool share, Rect? origin}) async {
    if (working) return;
    setState(() => working = true);
    try {
      final backupData = store.fullBackup();
      final jsonStr = const JsonEncoder.withIndent('  ').convert(backupData);
      final bytes = Uint8List.fromList(utf8.encode(jsonStr));
      final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final filename = 'stockmix-backup-$dateStr.json';

      if (share) {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                bytes,
                mimeType: 'application/json',
                name: filename,
              ),
            ],
            fileNameOverrides: [filename],
            title: 'Stockmix Full Backup',
            sharePositionOrigin: origin,
          ),
        );
        await store.markBackupCompleted();
        if (mounted) {
          showMessage(context, 'Backup shared and timestamp recorded.');
        }
      } else {
        final saved = await FilePicker.saveFile(
          fileName: filename,
          bytes: bytes,
          mimeType: 'application/json',
          dialogTitle: 'Save Stockmix Backup',
        );
        if (saved != null) {
          await store.markBackupCompleted();
          if (mounted) {
            showMessage(context, 'Full backup saved successfully.');
          }
        }
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  Future<void> _restoreBackup() async {
    if (working) return;
    setState(() => working = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json', 'stockmix-backup'],
        dialogTitle: 'Select Stockmix Backup File',
      );
      if (file == null) {
        setState(() => working = false);
        return;
      }

      final content = utf8.decode(await file.readAsBytes());
      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Selected file is not a valid Stockmix backup.');
      }

      final Map<String, dynamic> data = decoded.containsKey('data') && decoded['data'] is Map
          ? Map<String, dynamic>.from(decoded['data'] as Map)
          : decoded;

      final productsCount = (data['products'] as List?)?.length ?? 0;
      final movementsCount = (data['movements'] as List?)?.length ?? 0;
      final shopName = data['shop']?.toString() ?? 'Unknown store';
      final currency = data['currency']?.toString() ?? store.currency;

      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirm Restore'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Restoring will replace all current stock, sales, and settings on this device with the contents of this backup.',
                style: TextStyle(height: 1.4),
              ),
              const SizedBox(height: 16),
              Surface(
                color: linen,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shopName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Currency: $currency',
                      style: TextStyle(fontSize: 12, color: context.stockMuted),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• $productsCount items\n• $movementsCount stock records',
                      style: const TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text(
                '⚠️ This action cannot be undone.',
                style: TextStyle(color: context.stockRust, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: rust, foregroundColor: paper),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Restore everything'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        await store.restoreFullBackup(decoded);
        if (mounted) {
          showMessage(context, 'Backup restored successfully!');
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) showMessage(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasBackup = store.lastBackupAt != null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Backup & Restore'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Eyebrow('Complete store recovery'),
              const SizedBox(height: 10),
              Text(
                'Peace of mind for your business.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Back up everything—products, photos, sales, count drafts, and received records—so you never lose data when switching or resetting phones.',
                style: TextStyle(color: context.stockMuted, height: 1.4),
              ),
              const SizedBox(height: 24),

              // Status Card
              Surface(
                color: hasBackup ? avocado.withAlpha(40) : linen,
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: hasBackup ? avocado : context.stockMuted.withAlpha(50),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        hasBackup ? Icons.cloud_done_outlined : Icons.backup_outlined,
                        color: hasBackup ? context.stockInk : Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasBackup ? 'Last backup completed' : 'No backup on record',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatBackupDate(store.lastBackupAt),
                            style: TextStyle(color: context.stockMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Card: Back up now
              Surface(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.download_rounded, color: context.stockInk, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'Create a full backup',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Includes ${store.products.length} products (with photos), ${store.movements.length} records, ${store.received.length} received batches, held carts, and store settings.',
                      style: TextStyle(color: context.stockMuted, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    Builder(
                      builder: (btnCtx) => Row(
                        children: [
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: working
                                  ? null
                                  : () {
                                      final box = btnCtx.findRenderObject() as RenderBox?;
                                      final origin = box != null
                                          ? box.localToGlobal(Offset.zero) & box.size
                                          : null;
                                      _backupNow(share: true, origin: origin);
                                    },
                              icon: const Icon(Icons.share_outlined, size: 18),
                              label: Text(working ? 'Processing…' : 'Share backup file'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: working ? null : () => _backupNow(share: false),
                              icon: const Icon(Icons.save_alt_outlined, size: 18),
                              label: const Text('Save to device'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Card: Restore backup
              Surface(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.settings_backup_restore_rounded, color: context.stockRust, size: 22),
                        const SizedBox(width: 10),
                        Text(
                          'Restore from backup',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Import a previously saved Stockmix backup file to restore your products, sales history, and store setup on this phone.',
                      style: TextStyle(color: context.stockMuted, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: context.stockRust,
                          side: const BorderSide(color: rust),
                        ),
                        onPressed: working ? null : _restoreBackup,
                        icon: const Icon(Icons.folder_open_outlined, size: 18),
                        label: Text(working ? 'Restoring…' : 'Select backup file to restore'),
                      ),
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
