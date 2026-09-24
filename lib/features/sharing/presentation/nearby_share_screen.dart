import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:stockmix/core/theme/design.dart';
import 'package:stockmix/features/stock/stock_store.dart';
import '../application/share_controller.dart';
import '../domain/share_session.dart';
import '../domain/transfer_state.dart';
import 'sync_progress_view.dart';

class NearbyShareScreen extends StatefulWidget {
  final Map<String, dynamic> bundle;
  final StockStore? store;
  final ShareSession? session;

  const NearbyShareScreen({
    super.key,
    required this.bundle,
    this.store,
    this.session,
  });

  @override
  State<NearbyShareScreen> createState() => _NearbyShareScreenState();
}

class _NearbyShareScreenState extends State<NearbyShareScreen> {
  late final NearbyShareController _controller;

  @override
  void initState() {
    super.initState();
    _controller = NearbyShareController(
      bundle: widget.bundle,
      store: widget.store,
      session: widget.session,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _controller.start());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        _controller.session.isSync ? 'Sync directly' : 'Send directly',
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final state = _controller.state;
              final isSync = _controller.session.isSync;
              if (isSync) {
                return PopScope(
                  canPop: !_controller.mergingSync,
                  child: SyncProgressView(
                    state: state,
                    pairingCode: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(12),
                      child: QrImageView(
                        data: _controller.session.toQrPayload(),
                        size: 220,
                        backgroundColor: Colors.white,
                      ),
                    ),
                    canMerge: _controller.canMergeReceivedSync,
                    merging: _controller.mergingSync,
                    onMerge: _controller.mergeReceivedSyncNow,
                    onCancel: _controller.cancel,
                    onDone: () => Navigator.pop(context),
                  ),
                );
              }
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Eyebrow(isSync ? 'Two-way sync' : 'Secure nearby transfer'),
                  const SizedBox(height: 10),
                  Text(
                    state.phase == DirectTransferPhase.complete
                        ? 'Done.'
                        : (isSync
                              ? 'Scan to sync both phones.'
                              : 'Let them scan this code.'),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    state.phase == DirectTransferPhase.complete
                        ? (isSync
                              ? 'Both phones exchanged records. Choose when to merge the incoming records.'
                              : 'The other Stockmix device confirmed the record was saved.')
                        : (isSync
                              ? 'On the other phone, tap Join sync and point its camera at this QR code. Both phones will swap and merge records in one step.'
                              : 'On the other device, tap Receive and point its camera at this QR code.'),
                    style: TextStyle(color: context.stockMuted, height: 1.5),
                  ),
                  const SizedBox(height: 24),
                  if (state.phase != DirectTransferPhase.complete)
                    Surface(
                      color: context.stockPaper,
                      child: Center(
                        child: QrImageView(
                          data: _controller.session.toQrPayload(),
                          version: QrVersions.auto,
                          size: 238,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: plum,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: plum,
                          ),
                        ),
                      ),
                    )
                  else
                    _SuccessMark(label: isSync ? 'Synced' : 'Sent'),
                  const SizedBox(height: 24),
                  _TransferStatusCard(state: state),
                  const SizedBox(height: 20),
                  if (!state.isFinished)
                    OutlinedButton.icon(
                      onPressed: _controller.cancel,
                      icon: const Icon(Icons.close),
                      label: const Text('Cancel transfer'),
                    )
                  else if (isSync)
                    Column(
                      children: [
                        if (_controller.canMergeReceivedSync) ...[
                          FilledButton.icon(
                            onPressed: _controller.mergeReceivedSyncNow,
                            icon: const Icon(Icons.call_merge_rounded),
                            label: const Text('Merge now'),
                          ),
                          const SizedBox(height: 10),
                          OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Save for later merge'),
                          ),
                        ] else
                          FilledButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Done'),
                          ),
                      ],
                    )
                  else
                    FilledButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'The pairing code expires in five minutes. The transfer uses nearby Bluetooth and Wi-Fi transports, and the QR-only secret must match before any file is sent.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: context.stockMuted,
                      fontSize: 12,
                      height: 1.55,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );
}

class _TransferStatusCard extends StatelessWidget {
  final DirectTransferState state;
  const _TransferStatusCard({required this.state});

  @override
  Widget build(BuildContext context) {
    final failed = state.phase == DirectTransferPhase.error;
    final complete = state.phase == DirectTransferPhase.complete;
    return Surface(
      color: failed ? context.stockRust.withValues(alpha: .12) : linen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                failed
                    ? Icons.error_outline
                    : complete
                    ? Icons.check_circle_outline
                    : Icons.near_me_outlined,
                color: failed
                    ? context.stockRust
                    : complete
                    ? context.stockPositive
                    : context.stockInk,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  state.message,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          if (state.progress != null) ...[
            const SizedBox(height: 15),
            LinearProgressIndicator(value: state.progress),
          ],
        ],
      ),
    );
  }
}

class _SuccessMark extends StatelessWidget {
  final String label;
  const _SuccessMark({required this.label});

  @override
  Widget build(BuildContext context) => Surface(
    color: avocado,
    child: SizedBox(
      height: 238,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, size: 74, color: plum),
            const SizedBox(height: 12),
            Text(
              '$label ✓',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}
