import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

/// IEEE 802.3 32-bit Cyclic Redundancy Check for per-frame validation.
class Crc32 {
  static final List<int> _table = () {
    final table = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var k = 0; k < 8; k++) {
        c = (c & 1 != 0) ? (0xEDB88320 ^ (c >>> 1)) : (c >>> 1);
      }
      table[i] = c;
    }
    return table;
  }();

  static int compute(List<int> bytes) {
    var crc = 0xFFFFFFFF;
    for (final b in bytes) {
      crc = _table[(crc ^ b) & 0xFF] ^ (crc >>> 8);
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  static String hex(List<int> bytes) =>
      compute(bytes).toRadixString(16).padLeft(8, '0');
}

/// Deterministic 32-bit PRNG for generating Luby Transform droplet degrees and indices.
class DropletPrng {
  int state;
  DropletPrng(int seed) : state = (seed & 0xFFFFFFFF) == 0 ? 0x12345678 : (seed & 0xFFFFFFFF);

  int nextUint32() {
    state ^= (state << 13) & 0xFFFFFFFF;
    state ^= (state >>> 17);
    state ^= (state << 5) & 0xFFFFFFFF;
    return state & 0xFFFFFFFF;
  }

  double nextDouble() => (nextUint32() & 0x7FFFFFFF) / 0x7FFFFFFF;

  int nextInt(int max) {
    if (max <= 1) return 0;
    return nextUint32() % max;
  }
}

/// Domain Dictionary Compressor for Stockmix JSON payloads.
/// Replaces repetitive JSON keys and constant tokens with compact tokens,
/// significantly shrinking the payload before ZLib and QR slicing.
class DomainDictionaryCompressor {
  static const String magicHeader = 'SMXD1:';

  static const List<MapEntry<String, String>> _keyDictionary = [
    MapEntry('"format":', '"_f":'),
    MapEntry('"version":', '"_v":'),
    MapEntry('"exportedAt":', '"_ea":'),
    MapEntry('"currency":', '"_c":'),
    MapEntry('"products":', '"_p":'),
    MapEntry('"movements":', '"_m":'),
    MapEntry('"productId":', '"_pi":'),
    MapEntry('"barcode":', '"_bc":'),
    MapEntry('"category":', '"_cg":'),
    MapEntry('"threshold":', '"_th":'),
    MapEntry('"opening":', '"_op":'),
    MapEntry('"onHand":', '"_oh":'),
    MapEntry('"price":', '"_pr":'),
    MapEntry('"cost":', '"_cs":'),
    MapEntry('"unit":', '"_un":'),
    MapEntry('"photo":', '"_ph":'),
    MapEntry('"name":', '"_nm":'),
    MapEntry('"kind":', '"_kd":'),
    MapEntry('"shop":', '"_sh":'),
    MapEntry('"type":', '"_tp":'),
    MapEntry('"delta":', '"_dl":'),
    MapEntry('"note":', '"_nt":'),
    MapEntry('"reference":', '"_rf":'),
    MapEntry('"Stock snapshot"', r'"$SS"'),
    MapEntry('"Day record"', r'"$DR"'),
    MapEntry('"Sale"', r'"$SL"'),
    MapEntry('"Received"', r'"$RC"'),
    MapEntry('"Waste"', r'"$WS"'),
    MapEntry('"Stock count"', r'"$SC"'),
    MapEntry('"Return restock"', r'"$RR"'),
    MapEntry('"Opening stock"', r'"$OS"'),
  ];

  static const String _nullPhotoPattern = '"_ph":null,';
  static const String _emptyPhotoPattern = '"photo":null,';

  static String compressJsonString(String jsonStr) {
    var result = jsonStr;
    // Strip null photo fields to save space
    result = result.replaceAll(_emptyPhotoPattern, '');
    for (final entry in _keyDictionary) {
      result = result.replaceAll(entry.key, entry.value);
    }
    result = result.replaceAll(_nullPhotoPattern, '');
    return '$magicHeader$result';
  }

  static String decompressJsonString(String compressedStr) {
    if (!compressedStr.startsWith(magicHeader)) {
      return compressedStr; // Standard uncompressed JSON
    }
    var result = compressedStr.substring(magicHeader.length);
    for (final entry in _keyDictionary) {
      result = result.replaceAll(entry.value, entry.key);
    }
    return result;
  }
}

/// Prepared payload ready for fountain slicing.
class StreamPreparedPayload {
  final String sessionId;
  final Uint8List compressedData;
  final int uncompressedLength;
  final String fullSha256;
  final int blockSize;
  final int totalBlocks;

  StreamPreparedPayload({
    required this.sessionId,
    required this.compressedData,
    required this.uncompressedLength,
    required this.fullSha256,
    required this.blockSize,
    required this.totalBlocks,
  });

  factory StreamPreparedPayload.fromBytes(
    Uint8List rawBytes, {
    String? sessionId,
    int blockSize = 200,
  }) {
    final session = sessionId ?? _generateSessionId();
    final fullSha256 = sha256.convert(rawBytes).toString();
    // Compress with ZLib / Deflate
    final compressed = Uint8List.fromList(ZLibEncoder().encode(rawBytes));
    final totalBlocks = (compressed.length + blockSize - 1) ~/ blockSize;

    return StreamPreparedPayload(
      sessionId: session,
      compressedData: compressed,
      uncompressedLength: rawBytes.length,
      fullSha256: fullSha256,
      blockSize: blockSize,
      totalBlocks: totalBlocks == 0 ? 1 : totalBlocks,
    );
  }

  factory StreamPreparedPayload.fromJson(
    Map<String, dynamic> json, {
    String? sessionId,
    int blockSize = 200,
  }) {
    final rawJson = jsonEncode(json);
    // Apply domain dictionary pre-compression
    final dictCompressed = DomainDictionaryCompressor.compressJsonString(rawJson);
    final raw = Uint8List.fromList(utf8.encode(dictCompressed));
    return StreamPreparedPayload.fromBytes(
      raw,
      sessionId: sessionId,
      blockSize: blockSize,
    );
  }

  static String _generateSessionId() {
    final rand = DateTime.now().microsecondsSinceEpoch.toRadixString(16);
    return rand.length >= 8 ? rand.substring(rand.length - 8) : rand.padLeft(8, '0');
  }
}

/// A single QR stream frame.
class StreamFrame {
  final String sessionId;
  final int sequence;
  final int totalBlocks;
  final int payloadLength;
  final String shaPrefix;
  final int crc32;
  final Uint8List blockData;
  final Set<int> blockIndices;

  const StreamFrame({
    required this.sessionId,
    required this.sequence,
    required this.totalBlocks,
    required this.payloadLength,
    required this.shaPrefix,
    required this.crc32,
    required this.blockData,
    required this.blockIndices,
  });

  /// Format: `SMX1:<sessionId>:<seq>:<k>:<len>:<shaPrefix>:<crc32Hex>:<b64Data>`
  String toQrString() {
    final b64 = base64Url.encode(blockData);
    final crcHex = crc32.toRadixString(16).padLeft(8, '0');
    return 'SMX1:$sessionId:$sequence:$totalBlocks:$payloadLength:$shaPrefix:$crcHex:$b64';
  }

  static StreamFrame? parse(String raw) {
    try {
      final trimmed = raw.trim();
      if (!trimmed.startsWith('SMX1:')) return null;
      final parts = trimmed.split(':');
      if (parts.length != 8) return null;

      final sessionId = parts[1];
      final seq = int.tryParse(parts[2]);
      final totalBlocks = int.tryParse(parts[3]);
      final payloadLength = int.tryParse(parts[4]);
      final shaPrefix = parts[5];
      final crcExpected = int.tryParse(parts[6], radix: 16);
      if (seq == null || totalBlocks == null || payloadLength == null || crcExpected == null) {
        return null;
      }

      final blockData = base64Url.decode(parts[7]);
      final actualCrc = Crc32.compute(blockData);
      if (actualCrc != crcExpected) {
        // CRC check failed!
        return null;
      }

      final indices = QrStreamEncoder.indicesForSeq(sessionId, seq, totalBlocks);

      return StreamFrame(
        sessionId: sessionId,
        sequence: seq,
        totalBlocks: totalBlocks,
        payloadLength: payloadLength,
        shaPrefix: shaPrefix,
        crc32: crcExpected,
        blockData: blockData,
        blockIndices: indices,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Fountain / Systematic QR Stream Encoder.
class QrStreamEncoder {
  final StreamPreparedPayload payload;
  final List<Uint8List> _sourceBlocks = [];
  int _sequence = 0;

  QrStreamEncoder(this.payload) {
    _splitSourceBlocks();
  }

  void _splitSourceBlocks() {
    final data = payload.compressedData;
    final k = payload.totalBlocks;
    final bSize = payload.blockSize;

    for (var i = 0; i < k; i++) {
      final start = i * bSize;
      final end = (start + bSize < data.length) ? (start + bSize) : data.length;
      final block = Uint8List(bSize);
      if (start < data.length) {
        block.setRange(0, end - start, data.sublist(start, end));
      }
      _sourceBlocks.add(block);
    }
  }

  int get currentSequence => _sequence;
  int get totalBlocks => payload.totalBlocks;
  int get blockSize => payload.blockSize;

  /// Generate pseudo-random or systematic block indices for a given sequence number.
  static Set<int> indicesForSeq(String sessionId, int seq, int k) {
    if (k <= 1) return {0};
    // Phase 1: Systematic burst (seq < k)
    if (seq < k) {
      return {seq};
    }

    // Phase 2: Systematic round 2 with sliding neighborhood pairs (seq in [k, 2k))
    // If the camera locked focus late or missed only 1 frame, adjacent XOR pairs
    // like (B_i XOR B_{i+1}) resolve the missing frame immediately in 1 step!
    if (seq < 2 * k) {
      final base = (seq - k) % k;
      final neighbor = (base + 1) % k;
      return {base, neighbor};
    }

    // Phase 3: Rateless Luby Transform droplet phase with robust degree distribution
    // Seed = hash(sessionId) ^ (seq * 0x9E3779B9)
    final sessionSeed = sessionId.hashCode;
    final seed = (sessionSeed ^ (seq * 0x9E3779B9)) & 0xFFFFFFFF;
    final prng = DropletPrng(seed);

    // Optimized Soliton-like degree selection:
    // Degree 2 is most frequent (45%) to peel single unknowns rapidly,
    // followed by Degree 3 (25%), Degree 1 (10%), Degree 4 (10%), and higher.
    final roll = prng.nextDouble();
    int degree;
    if (roll < 0.10) {
      degree = 1;
    } else if (roll < 0.55) {
      degree = 2;
    } else if (roll < 0.80) {
      degree = 3;
    } else if (roll < 0.90) {
      degree = 4.clamp(2, k);
    } else {
      degree = (5 + prng.nextInt(3)).clamp(2, k);
    }

    degree = degree.clamp(1, k);
    final indices = <int>{};
    while (indices.length < degree) {
      indices.add(prng.nextInt(k));
    }
    return indices;
  }

  /// Generate the next animated stream frame.
  StreamFrame nextFrame() {
    final seq = _sequence++;
    final indices = indicesForSeq(payload.sessionId, seq, payload.totalBlocks);
    final bSize = payload.blockSize;
    final dropletData = Uint8List(bSize);

    for (final idx in indices) {
      final source = _sourceBlocks[idx];
      for (var i = 0; i < bSize; i++) {
        dropletData[i] ^= source[i];
      }
    }

    final crc = Crc32.compute(dropletData);
    final shaPrefix = payload.fullSha256.substring(0, 16);

    return StreamFrame(
      sessionId: payload.sessionId,
      sequence: seq,
      totalBlocks: payload.totalBlocks,
      payloadLength: payload.compressedData.length,
      shaPrefix: shaPrefix,
      crc32: crc,
      blockData: dropletData,
      blockIndices: indices,
    );
  }

  void reset() {
    _sequence = 0;
  }
}

/// Linear equation for peeling / Gaussian elimination in the fountain decoder.
class _DropletEquation {
  Set<int> indices;
  Uint8List data;
  _DropletEquation(this.indices, this.data);
}

/// Decoder state and metrics.
class DecoderStats {
  final double progress;
  final int resolvedBlocks;
  final int totalBlocks;
  final int framesCaptured;
  final int usefulFrames;
  final int duplicateFrames;
  final int rejectedFrames;
  final List<bool> blockStatus;
  final bool isComplete;
  final String? sessionId;

  const DecoderStats({
    required this.progress,
    required this.resolvedBlocks,
    required this.totalBlocks,
    required this.framesCaptured,
    required this.usefulFrames,
    required this.duplicateFrames,
    required this.rejectedFrames,
    required this.blockStatus,
    required this.isComplete,
    this.sessionId,
  });
}

/// Fountain / Belief-Propagation Peeling Decoder for QR Streams.
class QrStreamDecoder {
  String? _currentSessionId;
  int _totalBlocks = 0;
  int _payloadLength = 0;
  String? _shaPrefix;
  int _blockSize = 0;

  DateTime? _firstFrameAt;
  DateTime? _completedAt;

  List<Uint8List?> _resolvedBlocks = [];
  int _resolvedCount = 0;
  final List<_DropletEquation> _equations = [];

  int _framesCaptured = 0;
  int _usefulFrames = 0;
  int _duplicateFrames = 0;
  int _rejectedFrames = 0;

  Uint8List? _reconstructedPayload;
  String? _verifiedSha256;

  bool get isComplete => _totalBlocks > 0 && _resolvedCount == _totalBlocks;
  Uint8List? get reconstructedPayload => _reconstructedPayload;
  String? get verifiedSha256 => _verifiedSha256;
  String? get sessionId => _currentSessionId;
  int get blockSize => _blockSize;
  int get payloadLength => _payloadLength;
  DateTime? get firstFrameAt => _firstFrameAt;
  DateTime? get completedAt => _completedAt;

  Duration? get transferDuration {
    if (_firstFrameAt == null) return null;
    final end = _completedAt ?? DateTime.now();
    return end.difference(_firstFrameAt!);
  }

  DecoderStats get stats {
    final prog = _totalBlocks == 0 ? 0.0 : (_resolvedCount / _totalBlocks).clamp(0.0, 1.0);
    final status = List<bool>.generate(
      _totalBlocks,
      (i) => i < _resolvedBlocks.length && _resolvedBlocks[i] != null,
    );

    return DecoderStats(
      progress: prog,
      resolvedBlocks: _resolvedCount,
      totalBlocks: _totalBlocks,
      framesCaptured: _framesCaptured,
      usefulFrames: _usefulFrames,
      duplicateFrames: _duplicateFrames,
      rejectedFrames: _rejectedFrames,
      blockStatus: status,
      isComplete: isComplete,
      sessionId: _currentSessionId,
    );
  }

  /// Process an incoming QR frame string. Returns true if this frame advanced the reconstruction.
  bool processRawFrame(String raw) {
    _framesCaptured++;
    final frame = StreamFrame.parse(raw);
    if (frame == null) {
      _rejectedFrames++;
      return false;
    }

    _firstFrameAt ??= DateTime.now();

    // Initialize or switch session if appropriate
    if (_currentSessionId == null || (_resolvedCount == 0 && _currentSessionId != frame.sessionId)) {
      _initSession(frame);
    } else if (frame.sessionId != _currentSessionId) {
      // Different session while one is already in progress
      _rejectedFrames++;
      return false;
    }

    if (isComplete) {
      _duplicateFrames++;
      return false;
    }

    return _processFrame(frame);
  }

  void _initSession(StreamFrame frame) {
    _currentSessionId = frame.sessionId;
    _totalBlocks = frame.totalBlocks;
    _payloadLength = frame.payloadLength;
    _shaPrefix = frame.shaPrefix;
    _blockSize = frame.blockData.length;
    _resolvedBlocks = List<Uint8List?>.filled(_totalBlocks, null);
    _resolvedCount = 0;
    _equations.clear();
    _reconstructedPayload = null;
    _verifiedSha256 = null;
    _firstFrameAt = DateTime.now();
    _completedAt = null;
  }

  bool _processFrame(StreamFrame frame) {
    final remainingIndices = Set<int>.from(frame.blockIndices);
    final currentData = Uint8List.fromList(frame.blockData);

    // 1. Substitute already-resolved blocks
    for (final idx in frame.blockIndices) {
      if (idx < _resolvedBlocks.length && _resolvedBlocks[idx] != null) {
        _xorInPlace(currentData, _resolvedBlocks[idx]!);
        remainingIndices.remove(idx);
      }
    }

    // 2. If all indices cancelled out, frame is redundant
    if (remainingIndices.isEmpty) {
      _duplicateFrames++;
      return false;
    }

    // 3. If single remaining index, we just solved a source block!
    if (remainingIndices.length == 1) {
      _usefulFrames++;
      _resolveBlock(remainingIndices.first, currentData);
      _peel();
      _checkCompletion();
      return true;
    }

    // 4. Multiple unknown blocks: try Gaussian reduction against existing equations
    for (final eq in _equations) {
      // If subset or shares overlap, reduce
      if (eq.indices.contains(remainingIndices.first)) {
        for (final idx in eq.indices) {
          if (remainingIndices.contains(idx)) {
            remainingIndices.remove(idx);
          } else {
            remainingIndices.add(idx);
          }
        }
        _xorInPlace(currentData, eq.data);
        if (remainingIndices.isEmpty) {
          _duplicateFrames++;
          return false;
        }
      }
    }

    if (remainingIndices.length == 1) {
      _usefulFrames++;
      _resolveBlock(remainingIndices.first, currentData);
      _peel();
      _checkCompletion();
      return true;
    }

    // Still unresolved, store in equations pool
    _equations.add(_DropletEquation(remainingIndices, currentData));
    _usefulFrames++;
    return true;
  }

  void _resolveBlock(int idx, Uint8List data) {
    if (idx < 0 || idx >= _totalBlocks) return;
    if (_resolvedBlocks[idx] != null) return;
    _resolvedBlocks[idx] = data;
    _resolvedCount++;
  }

  /// Peeling step: iteratively reduce all equations with newly resolved blocks
  void _peel() {
    var changed = true;
    while (changed) {
      changed = false;
      for (var i = _equations.length - 1; i >= 0; i--) {
        final eq = _equations[i];
        final toRemove = <int>[];
        for (final idx in eq.indices) {
          if (_resolvedBlocks[idx] != null) {
            _xorInPlace(eq.data, _resolvedBlocks[idx]!);
            toRemove.add(idx);
          }
        }
        for (final idx in toRemove) {
          eq.indices.remove(idx);
        }

        if (eq.indices.isEmpty) {
          _equations.removeAt(i);
        } else if (eq.indices.length == 1) {
          final solvedIdx = eq.indices.first;
          final solvedData = eq.data;
          _equations.removeAt(i);
          _resolveBlock(solvedIdx, solvedData);
          changed = true;
          break; // restart scan
        }
      }
    }
  }

  void _checkCompletion() {
    if (_resolvedCount == _totalBlocks && _reconstructedPayload == null) {
      _completedAt = DateTime.now();
      // Concatenate all blocks
      final fullBytes = BytesBuilder(copy: false);
      for (var i = 0; i < _totalBlocks; i++) {
        fullBytes.add(_resolvedBlocks[i]!);
      }
      final allBytes = fullBytes.takeBytes();
      // Slice to actual payloadLength
      final finalBytes = (_payloadLength > 0 && _payloadLength <= allBytes.length)
          ? allBytes.sublist(0, _payloadLength)
          : allBytes;

      _reconstructedPayload = finalBytes;
    }
  }

  /// Finalize and verify the full reconstructed payload.
  /// Decompresses the data and returns the decoded UTF-8 string or JSON.
  VerificationResult verifyAndDecompress({String? expectedFullSha256}) {
    if (!isComplete || _reconstructedPayload == null) {
      return VerificationResult.failure('Reconstruction incomplete: $_resolvedCount of $_totalBlocks blocks');
    }

    try {
      // Decompress ZLib
      final decompressed = Uint8List.fromList(
        ZLibDecoder().decodeBytes(_reconstructedPayload!),
      );

      final fullSha = sha256.convert(decompressed).toString();
      _verifiedSha256 = fullSha;

      if (_shaPrefix != null && !fullSha.startsWith(_shaPrefix!)) {
        return VerificationResult.failure('SHA-256 prefix mismatch. Data may be corrupted.');
      }

      if (expectedFullSha256 != null && expectedFullSha256 != fullSha) {
        return VerificationResult.failure('Full SHA-256 hash mismatch.');
      }

      final rawUtf8String = utf8.decode(decompressed);
      // Transparently decompress domain dictionary if used
      final jsonString = DomainDictionaryCompressor.decompressJsonString(rawUtf8String);
      final dynamic decoded = jsonDecode(jsonString);
      if (decoded is! Map<String, dynamic>) {
        return VerificationResult.failure('Decoded payload is not a valid Stockmix bundle.');
      }

      return VerificationResult.success(
        payload: decoded,
        sha256: fullSha,
        rawBytesLength: decompressed.length,
        transferDuration: transferDuration,
      );
    } catch (e) {
      return VerificationResult.failure('Decompression or JSON parse error: $e');
    }
  }

  static void _xorInPlace(Uint8List a, Uint8List b) {
    final len = a.length < b.length ? a.length : b.length;
    // 64-bit word XOR for fast decoding on mobile CPUs
    final words = len >> 3;
    if (words > 0 &&
        (a.offsetInBytes & 7) == 0 &&
        (b.offsetInBytes & 7) == 0) {
      final a64 = a.buffer.asUint64List(a.offsetInBytes, words);
      final b64 = b.buffer.asUint64List(b.offsetInBytes, words);
      for (var i = 0; i < words; i++) {
        a64[i] ^= b64[i];
      }
      final remainderStart = words << 3;
      for (var i = remainderStart; i < len; i++) {
        a[i] ^= b[i];
      }
    } else {
      for (var i = 0; i < len; i++) {
        a[i] ^= b[i];
      }
    }
  }

  void reset() {
    _currentSessionId = null;
    _totalBlocks = 0;
    _payloadLength = 0;
    _shaPrefix = null;
    _blockSize = 0;
    _resolvedBlocks.clear();
    _resolvedCount = 0;
    _equations.clear();
    _framesCaptured = 0;
    _usefulFrames = 0;
    _duplicateFrames = 0;
    _rejectedFrames = 0;
    _reconstructedPayload = null;
    _verifiedSha256 = null;
    _firstFrameAt = null;
    _completedAt = null;
  }
}

/// Verification outcome.
class VerificationResult {
  final bool isValid;
  final String? errorMessage;
  final Map<String, dynamic>? payload;
  final String? sha256;
  final int? rawBytesLength;
  final Duration? transferDuration;

  const VerificationResult({
    required this.isValid,
    this.errorMessage,
    this.payload,
    this.sha256,
    this.rawBytesLength,
    this.transferDuration,
  });

  factory VerificationResult.success({
    required Map<String, dynamic> payload,
    required String sha256,
    required int rawBytesLength,
    Duration? transferDuration,
  }) => VerificationResult(
    isValid: true,
    payload: payload,
    sha256: sha256,
    rawBytesLength: rawBytesLength,
    transferDuration: transferDuration,
  );

  factory VerificationResult.failure(String message) => VerificationResult(
    isValid: false,
    errorMessage: message,
  );
}
