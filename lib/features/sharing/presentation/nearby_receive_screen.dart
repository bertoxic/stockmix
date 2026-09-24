import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import 'package:stockmix/core/theme/design.dart';
import 'package:stockmix/features/stock/stock_store.dart';
import '../application/receive_controller.dart';
import '../domain/share_session.dart';
import '../domain/transfer_state.dart';
import 'sync_progress_view.dart';

class NearbyReceiveScreen extends StatefulWidget {
  final StockStore store;

  const NearbyReceiveScreen({super.key, required this.store});

  @override
  State<NearbyReceiveScreen> createState() => _NearbyReceiveScreenState();
}

class _NearbyReceiveScreenState extends State<NearbyReceiveScreen> {
  final MobileScannerController _camera = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  NearbyReceiveController? _controller;
  String? _scanError;
  bool _reading = false;

  @override
  void dispose() {
    _camera.dispose();
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_reading || capture.barcodes.isEmpty) {
      return;
    }
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstOrNull;
    if (raw == null) {
      return;
    }
    final session = ShareSession.tryParseQrPayload(raw);
    if (session == null) {
      if (mounted) {
        setState(() => _scanError = 'That is not a Stockmix transfer code.');
      }
      return;
    }
    if (session.isExpired) {
      if (mounted) {
        setState(
          () => _scanError =
              'This pairing code expired. Ask the sender to make a new one.',
        );
      }
      return;
    }
    _reading = true;
    await _camera.stop();
    if (!mounted) return;
    final name = widget.store.userName.trim().isEmpty
        ? widget.store.shop
        : widget.store.userName.trim();
    final controller = NearbyReceiveController(
      store: widget.store,
      session: session,
      receiverName: name,
    );
    setState(() {
      _scanError = null;
      _controller = controller;
    });
    await controller.start();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null) return _transferView(controller);
    return Scaffold(
      appBar: AppBar(title: const Text('Receive directly')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('Secure nearby transfer'),
              const SizedBox(height: 10),
              Text(
                'Scan the sender’s code.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              Text(
                'Keep both devices close and leave Stockmix open while the record transfers.',
                style: TextStyle(color: context.stockMuted, height: 1.5),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _camera,
                        onDetect: _onDetect,
                        errorBuilder: (_, _) => Container(
                          color: plum,
                          alignment: Alignment.center,
                          padding: const EdgeInsets.all(24),
                          child: const Text(
                            'Camera unavailable. Allow camera access, then try again.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: paper),
                          ),
                        ),
                      ),
                      Center(
                        child: Container(
                          width: 210,
                          height: 210,
                          decoration: BoxDecoration(
                            border: Border.all(color: avocado, width: 3),
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_scanError != null) ...[
                const SizedBox(height: 14),
                Text(_scanError!, style: TextStyle(color: context.stockRust)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _transferView(NearbyReceiveController controller) => Scaffold(
    appBar: AppBar(
      title: Text(
        controller.session.isSync ? 'Sync directly' : 'Receive directly',
      ),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: AnimatedBuilder(
            animation: controller,
            builder: (context, _) {
              final state = controller.state;
              final isSync = controller.session.isSync;
              if (isSync) {
                return PopScope(
                  canPop: !controller.mergingSync,
                  child: SyncProgressView(
                    state: state,
                    canMerge: controller.canMergeReceivedSync,
                    merging: controller.mergingSync,
                    onMerge: controller.mergeReceivedSyncNow,
                    onCancel: controller.cancel,
                    onDone: () => Navigator.pop(context),
                  ),
                );
              }
              final complete = state.phase == DirectTransferPhase.complete;
              final failed = state.phase == DirectTransferPhase.error;
              return Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      complete
                          ? Icons.check_circle_rounded
                          : failed
                          ? Icons.error_outline_rounded
                          : (isSync
                                ? Icons.sync_rounded
                                : Icons.wifi_tethering_outlined),
                      size: 82,
                      color: complete
                          ? context.stockPositive
                          : failed
                          ? context.stockRust
                          : context.stockInk,
                    ),
                    const SizedBox(height: 22),
                    Text(
                      complete
                          ? (isSync ? 'Synced.' : 'Received.')
                          : (isSync ? 'Syncing nearby…' : 'Receiving nearby…'),
                      style: Theme.of(context).textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.message,
                      style: TextStyle(color: context.stockMuted, height: 1.5),
                      textAlign: TextAlign.center,
                    ),
                    if (state.progress != null) ...[
                      const SizedBox(height: 28),
                      LinearProgressIndicator(value: state.progress),
                    ],
                    const SizedBox(height: 30),
                    if (complete && isSync)
                      Column(
                        children: [
                          if (controller.canMergeReceivedSync) ...[
                            FilledButton.icon(
                              onPressed: controller.mergeReceivedSyncNow,
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
                    else if (state.isFinished)
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'),
                      )
                    else
                      OutlinedButton.icon(
                        onPressed: controller.cancel,
                        icon: const Icon(Icons.close),
                        label: Text(isSync ? 'Cancel sync' : 'Cancel receive'),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
