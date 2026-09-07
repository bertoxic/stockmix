import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../design.dart';
import '../scan_feedback.dart';
import '../stock_store.dart';
import 'qr_stream_coder.dart';
import 'stream_import_review_page.dart';

/// Camera Receiver for animated QR streams.
/// Solves fountain code packets in real-time, displays glowing block progress,
/// verifies full SHA-256 integrity, and transitions to duplicate-safe import.
class QrStreamReceiverPage extends StatefulWidget {
  final StockStore store;

  const QrStreamReceiverPage({super.key, required this.store});

  @override
  State<QrStreamReceiverPage> createState() => _QrStreamReceiverPageState();
}

class _QrStreamReceiverPageState extends State<QrStreamReceiverPage> {
  late final MobileScannerController controller;
  final QrStreamDecoder decoder = QrStreamDecoder();
  bool flashOn = false;
  bool finished = false;
  String? errorMessage;
  String? lastCode;
  DateTime? lastScanTime;

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
      detectionSpeed: DetectionSpeed.unrestricted,
    );
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  final Map<String, DateTime> _recentlySeenCodes = {};

  Uint8List? _decodedBytes(Barcode barcode) {
    final decoded = barcode.rawDecodedBytes;
    if (decoded is DecodedBarcodeBytes) return decoded.bytes;
    if (decoded is DecodedVisionBarcodeBytes) return decoded.bytes;
    return barcode.rawBytes;
  }

  void _finishIfComplete() {
    if (decoder.isComplete && !finished) _handleCompletion();
  }

  void _onDetect(BarcodeCapture capture) {
    if (finished) return;
    final now = DateTime.now();

    // Clean up codes older than 120ms
    _recentlySeenCodes.removeWhere((_, time) => now.difference(time).inMilliseconds > 120);

    for (final barcode in capture.barcodes) {
      final bytes = _decodedBytes(barcode);
      if (bytes != null && StreamFrame.isBinaryFrame(bytes)) {
        final key = StreamFrame.binaryFrameKey(bytes)!;
        if (_recentlySeenCodes.containsKey(key)) continue;
        _recentlySeenCodes[key] = now;

        final beforeResolved = decoder.stats.resolvedBlocks;
        decoder.processRawBytes(bytes);
        final afterResolved = decoder.stats.resolvedBlocks;
        if (mounted) setState(() {});
        if (afterResolved > beforeResolved) HapticFeedback.selectionClick();
        _finishIfComplete();
        if (finished) break;
        continue;
      }

    }
  }

  Future<void> _handleCompletion() async {
    finished = true;

    // Verify SHA-256 integrity and decompress
    final result = decoder.verifyAndDecompress();
    if (!result.isValid) {
      if (mounted) {
        setState(() {
          errorMessage = result.errorMessage ?? 'Integrity verification failed.';
        });
      }
      return;
    }

    if (!mounted) return;

    unawaited(ScanFeedback.success());
    // Show quick celebratory feedback, then push duplicate-safe review
    await Navigator.pushReplacement<bool, void>(
      context,
      MaterialPageRoute(
        builder: (_) => StreamImportReviewPage(
          store: widget.store,
          rawPayload: result.payload!,
          verifiedSha256: result.sha256!,
          transferDuration: result.transferDuration,
        ),
      ),
    );
  }

  Future<void> _toggleFlash() async {
    try {
      await controller.toggleTorch();
      if (mounted) setState(() => flashOn = !flashOn);
    } catch (_) {
      if (mounted) showMessage(context, 'Flash is unavailable on this camera.');
    }
  }

  void _resetScanner() {
    setState(() {
      finished = false;
      errorMessage = null;
      decoder.reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    final stats = decoder.stats;
    final pct = (stats.progress * 100).toInt();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Stream Scanner'),
        actions: [
          if (cameraSupported)
            IconButton(
              tooltip: flashOn ? 'Turn off flash' : 'Turn on flash',
              icon: Icon(flashOn ? Icons.flash_off : Icons.flash_on_outlined),
              onPressed: _toggleFlash,
            ),
          IconButton(
            tooltip: 'Reset stream',
            icon: const Icon(Icons.refresh),
            onPressed: _resetScanner,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top Camera Viewfinder
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: SizedBox(
                height: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (cameraSupported)
                        MobileScanner(
                          controller: controller,
                          onDetect: _onDetect,
                          errorBuilder: (_, err) => Container(
                            color: plum,
                            padding: const EdgeInsets.all(20),
                            child: Center(
                              child: Text(
                                'Camera unavailable. Grant camera permission in settings.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: paper),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          color: plum,
                          child: Center(
                            child: Text(
                              'Camera scanning is not supported on this platform.',
                              style: TextStyle(color: paper),
                            ),
                          ),
                        ),
                      // Target Box
                      Center(
                        child: Container(
                          width: 200,
                          height: 180,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: stats.isComplete ? avocado : Colors.white70,
                              width: 3,
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Live Reconstruction & Progress Area
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                children: [
                  if (errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Surface(
                        color: Colors.red.shade50,
                        child: Row(
                          children: [
                            Icon(Icons.error_outline, color: context.stockRust),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                errorMessage!,
                                style: TextStyle(color: context.stockRust, fontSize: 12),
                              ),
                            ),
                            TextButton(
                              onPressed: _resetScanner,
                              child: const Text('Try again'),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // Progress Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Eyebrow('Reconstruction Progress'),
                          const SizedBox(height: 4),
                          Text(
                            stats.totalBlocks == 0
                                ? 'Aim camera at animated QR'
                                : '${stats.resolvedBlocks} of ${stats.totalBlocks} blocks ($pct%)',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                          ),
                        ],
                        ),
                      ),
                      if (stats.totalBlocks > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: stats.isComplete ? avocado : context.stockLinen,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            stats.isComplete ? 'VERIFIED ✓' : '$pct%',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                          ),
                        ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // Linear Progress Bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: stats.totalBlocks == 0 ? null : stats.progress,
                      minHeight: 10,
                      backgroundColor: cement.withValues(alpha: 0.3),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        stats.isComplete ? Colors.green : plum,
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Visual Block Mosaic Grid
                  if (stats.totalBlocks > 0) ...[
                    const Eyebrow('Fountain Block Mosaic'),
                    const SizedBox(height: 8),
                    Surface(
                      padding: const EdgeInsets.all(12),
                      child: Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: List.generate(stats.totalBlocks, (index) {
                          final resolved = stats.blockStatus[index];
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: resolved ? avocado : cement.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: resolved ? plum.withValues(alpha: 0.3) : Colors.transparent,
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: resolved
                                  ? Icon(Icons.check, size: 12, color: context.stockInk)
                                  : Text(
                                      '${index + 1}',
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: context.stockMuted.withValues(alpha: 0.7),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          );
                        }),
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Telemetry Diagnostics
                  Surface(
                    color: paper,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _metric('Scanned', '${stats.framesCaptured}'),
                        _metric('Useful', '${stats.usefulFrames}'),
                        _metric('Duplicates', '${stats.duplicateFrames}'),
                        _metric('Rejected', '${stats.rejectedFrames}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _metric(String label, String value) => Column(
    children: [
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(fontSize: 10, color: context.stockMuted)),
    ],
  );
}
