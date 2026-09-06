import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../design.dart';
import '../stock_store.dart';
import 'qr_stream_coder.dart';
import 'entry_hasher.dart';

/// Animated QR Stream Sender.
/// Continuously generates rateless fountain-coded QR frames.
class QrStreamSenderPage extends StatefulWidget {
  final StockStore store;
  final Map<String, dynamic> bundle;

  const QrStreamSenderPage({
    super.key,
    required this.store,
    required this.bundle,
  });

  @override
  State<QrStreamSenderPage> createState() => _QrStreamSenderPageState();
}

enum QrDisplayMode {
  single('Single QR', Icons.crop_square_outlined),
  dualStacked('Dual Stacked', Icons.view_agenda_outlined),
  dualSideBySide('Dual Side-by-Side', Icons.view_column_outlined);

  final String label;
  final IconData icon;
  const QrDisplayMode(this.label, this.icon);
}

class _QrStreamSenderPageState extends State<QrStreamSenderPage> {
  late StreamPreparedPayload preparedPayload;
  late QrStreamEncoder encoder;
  StreamFrame? currentFrame;
  StreamFrame? secondFrame;
  Timer? animationTimer;
  int intervalMs = 120;
  bool paused = false;
  bool includePhotos = false;
  QrDisplayMode displayMode = QrDisplayMode.single;

  @override
  void initState() {
    super.initState();
    _rebuildPayload(initial: true);
    _advanceFrame();
    _startTimer();
  }

  void _rebuildPayload({bool initial = false}) {
    // Generate bundle according to photo toggle
    final isDaily = widget.bundle['kind'] == 'Day record';
    final dayStr = widget.bundle['day'] as String?;
    final day = dayStr != null ? DateTime.tryParse(dayStr) : null;
    final bundleData = widget.store.bundle(
      day: isDaily ? (day ?? DateTime.now()) : null,
      includePhotos: includePhotos,
    );

    // Dynamic block size: 240 bytes gives ideal QR density and fewer total frames
    preparedPayload = StreamPreparedPayload.fromJson(
      bundleData,
      blockSize: 240,
    );
    encoder = QrStreamEncoder(preparedPayload);
    if (!initial) {
      _advanceFrame();
    }
  }

  void _togglePhotos(bool value) {
    setState(() {
      includePhotos = value;
      _rebuildPayload();
    });
  }

  void _setDisplayMode(QrDisplayMode mode) {
    setState(() {
      displayMode = mode;
      _advanceFrame();
    });
  }

  void _startTimer() {
    animationTimer?.cancel();
    if (paused) return;
    animationTimer = Timer.periodic(Duration(milliseconds: intervalMs), (_) {
      if (mounted) {
        _advanceFrame();
      }
    });
  }

  void _advanceFrame() {
    setState(() {
      currentFrame = encoder.nextFrame();
      if (displayMode == QrDisplayMode.dualStacked || displayMode == QrDisplayMode.dualSideBySide) {
        secondFrame = encoder.nextFrame();
      } else {
        secondFrame = null;
      }
    });
  }

  void _togglePause() {
    setState(() {
      paused = !paused;
    });
    if (paused) {
      animationTimer?.cancel();
    } else {
      _startTimer();
    }
  }

  void _changeSpeed(int newInterval) {
    setState(() {
      intervalMs = newInterval;
    });
    _startTimer();
  }

  @override
  void dispose() {
    animationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = currentFrame;
    final totalBlocks = preparedPayload.totalBlocks;
    final isDroplet = frame != null && frame.sequence >= totalBlocks;
    final seqDisplay = frame != null ? frame.sequence + 1 : 0;
    final qrData = frame?.toQrString() ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Streaming Entries'),
        actions: [
          IconButton(
            tooltip: paused ? 'Resume stream' : 'Pause stream',
            icon: Icon(paused ? Icons.play_arrow : Icons.pause),
            onPressed: _togglePause,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            children: [
              const Center(child: Eyebrow('Offline Fountain QR Transfer')),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  'Scan continuously to receive',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 16),

              // Animated QR Screen Display
              if (displayMode == QrDisplayMode.dualStacked && secondFrame != null) ...[
                Center(
                  child: Container(
                    width: 320,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 160,
                          child: qrData.isNotEmpty
                              ? QrImageView(
                                  data: qrData,
                                  version: QrVersions.auto,
                                  gapless: true,
                                  padding: const EdgeInsets.all(4),
                                  errorCorrectionLevel: QrErrorCorrectLevel.L,
                                )
                              : const Center(child: CircularProgressIndicator()),
                        ),
                        Text(
                          'Stream A (Seq #${frame!.sequence + 1})',
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: muted),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                          child: Divider(height: 1, thickness: 0.5, color: cement),
                        ),
                        SizedBox(
                          height: 160,
                          child: QrImageView(
                            data: secondFrame!.toQrString(),
                            version: QrVersions.auto,
                            gapless: true,
                            padding: const EdgeInsets.all(4),
                            errorCorrectionLevel: QrErrorCorrectLevel.L,
                          ),
                        ),
                        Text(
                          'Stream B (Seq #${secondFrame!.sequence + 1})',
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: muted),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else if (displayMode == QrDisplayMode.dualSideBySide && secondFrame != null) ...[
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 155,
                              height: 155,
                              child: qrData.isNotEmpty
                                  ? QrImageView(
                                      data: qrData,
                                      version: QrVersions.auto,
                                      gapless: true,
                                      padding: const EdgeInsets.all(4),
                                      errorCorrectionLevel: QrErrorCorrectLevel.L,
                                    )
                                  : const Center(child: CircularProgressIndicator()),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Stream A (#${frame!.sequence + 1})',
                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: muted),
                            ),
                          ],
                        ),
                        Container(
                          width: 1,
                          height: 140,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          color: cement,
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 155,
                              height: 155,
                              child: QrImageView(
                                data: secondFrame!.toQrString(),
                                version: QrVersions.auto,
                                gapless: true,
                                padding: const EdgeInsets.all(4),
                                errorCorrectionLevel: QrErrorCorrectLevel.L,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Stream B (#${secondFrame!.sequence + 1})',
                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: muted),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Center(
                  child: Container(
                    width: 300,
                    height: 300,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: qrData.isNotEmpty
                        ? QrImageView(
                            data: qrData,
                            version: QrVersions.auto,
                            gapless: true,
                            padding: const EdgeInsets.all(6),
                            errorCorrectionLevel: QrErrorCorrectLevel.L,
                          )
                        : const Center(child: CircularProgressIndicator()),
                  ),
                ),
              ],

              const SizedBox(height: 18),

              // Telemetry & Frame Counter
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: linen,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: paused ? rust : avocado,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isDroplet
                            ? 'Fountain Droplet #$seqDisplay ($totalBlocks source blocks)'
                            : 'Block $seqDisplay of $totalBlocks',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Transfer Metadata Card
              Surface(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Payload size', style: TextStyle(fontSize: 12, color: muted)),
                        Text(
                          '${(preparedPayload.uncompressedLength / 1024).toStringAsFixed(1)} KB (${preparedPayload.compressedData.length} bytes compressed)',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const Divider(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Session ID', style: TextStyle(fontSize: 12, color: muted)),
                        Text(
                          preparedPayload.sessionId,
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    const Divider(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Integrity Hash', style: TextStyle(fontSize: 12, color: muted)),
                        Text(
                          EntryHasher.shortHash(preparedPayload.fullSha256),
                          style: const TextStyle(fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Photos in Stream Toggle Card
              Surface(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const Icon(Icons.photo_library_outlined, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Include photos in QR stream',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            includePhotos
                                ? 'Photos included (${preparedPayload.totalBlocks} blocks). May take longer to scan.'
                                : 'Off for maximum speed (${preparedPayload.totalBlocks} blocks). Fast and light.',
                            style: const TextStyle(fontSize: 11, color: muted),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: includePhotos,
                      onChanged: _togglePhotos,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Multi-QR Parallel Layout Selector Card
              Surface(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.dashboard_customize_outlined, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Parallel QR Layout',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Emit multiple blocks simultaneously to multiply camera ingestion speed.',
                      style: TextStyle(fontSize: 11, color: muted),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: QrDisplayMode.values.map((mode) {
                        final isSelected = displayMode == mode;
                        return ChoiceChip(
                          avatar: Icon(mode.icon, size: 16, color: isSelected ? Colors.white : plum),
                          label: Text(
                            mode.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.normal,
                            ),
                          ),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) _setDisplayMode(mode);
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Speed Controller
              const Center(child: Eyebrow('Animation Speed')),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _speedChip('Lightning · 80ms', 80),
                  _speedChip('Fast · 120ms', 120),
                  _speedChip('Standard · 200ms', 200),
                  _speedChip('Relaxed · 320ms', 320),
                ],
              ),

              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Finish Streaming'),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _speedChip(String label, int ms) {
    final selected = intervalMs == ms;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.normal)),
      selected: selected,
      onSelected: (val) {
        if (val) _changeSpeed(ms);
      },
    );
  }
}
