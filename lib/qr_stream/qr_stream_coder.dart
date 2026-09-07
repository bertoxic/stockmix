import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

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
/// Safely replaces repetitive JSON keys and fixed enum values with compact tokens,
/// significantly shrinking the payload before ZLib and QR slicing, while preserving
/// user text (such as product names or notes) 100% losslessly.
class DomainDictionaryCompressor {
  static const String magicHeader = 'SMXD1:';

  static const Map<String, String> _forwardKeyMap = {
    'format': '_f',
    'version': '_v',
    'exportedAt': '_ea',
    'currency': '_c',
    'products': '_p',
    'movements': '_m',
    'productId': '_pi',
    'barcode': '_bc',
    'category': '_cg',
    'threshold': '_th',
    'opening': '_op',
    'onHand': '_oh',
    'price': '_pr',
    'cost': '_cs',
    'unit': '_un',
    'photo': '_ph',
    'name': '_nm',
    'kind': '_kd',
    'shop': '_sh',
    'type': '_tp',
    'delta': '_dl',
    'note': '_nt',
    'reference': '_rf',
    'senderName': '_sn',
    'packSize': '_ps',
    'packUnit': '_pu',
    'packPrice': '_pp',
    'day': '_d',
  };

  static final Map<String, String> _reverseKeyMap = {
    for (final entry in _forwardKeyMap.entries) entry.value: entry.key,
  };

  static const Map<String, String> _forwardKindMap = {
    'Stock snapshot': r'$SS',
    'Day record': r'$DR',
  };

  static const Map<String, String> _reverseKindMap = {
    r'$SS': 'Stock snapshot',
    r'$DR': 'Day record',
  };

  static const Map<String, String> _forwardTypeMap = {
    'Sale': r'$SL',
    'Received': r'$RC',
    'Waste': r'$WS',
    'Stock count': r'$SC',
    'Return restock': r'$RR',
    'Opening stock': r'$OS',
  };

  static const Map<String, String> _reverseTypeMap = {
    r'$SL': 'Sale',
    r'$RC': 'Received',
    r'$WS': 'Waste',
    r'$SC': 'Stock count',
    r'$RR': 'Return restock',
    r'$OS': 'Opening stock',
  };

  static dynamic _compressNode(dynamic node, {String? keyName}) {
    if (node is Map) {
      final result = <String, dynamic>{};
      for (final entry in node.entries) {
        final k = entry.key.toString();
        final v = entry.value;
        if ((k == 'photo' || k == '_ph') && v == null) continue;
        final shortenedKey = _forwardKeyMap[k] ?? k;
        result[shortenedKey] = _compressNode(v, keyName: k);
      }
      return result;
    } else if (node is List) {
      return node.map((item) => _compressNode(item, keyName: keyName)).toList();
    } else if (node is String) {
      if (keyName == 'kind' || keyName == '_kd') {
        return _forwardKindMap[node] ?? node;
      }
      if (keyName == 'type' || keyName == '_tp') {
        return _forwardTypeMap[node] ?? node;
      }
      return node;
    }
    return node;
  }

  static dynamic _decompressNode(dynamic node, {String? keyName}) {
    if (node is Map) {
      final result = <String, dynamic>{};
      for (final entry in node.entries) {
        final k = entry.key.toString();
        final v = entry.value;
        final expandedKey = _reverseKeyMap[k] ?? k;
        result[expandedKey] = _decompressNode(v, keyName: expandedKey);
      }
      return result;
    } else if (node is List) {
      return node.map((item) => _decompressNode(item, keyName: keyName)).toList();
    } else if (node is String) {
      if (keyName == 'kind' || keyName == '_kd') {
        return _reverseKindMap[node] ?? node;
      }
      if (keyName == 'type' || keyName == '_tp') {
        return _reverseTypeMap[node] ?? node;
      }
      return node;
    }
    return node;
  }

  static String compressJsonString(String jsonStr) {
    try {
      final dynamic decoded = jsonDecode(jsonStr);
      return compressJsonMap(decoded);
    } catch (_) {
      return jsonStr;
    }
  }

  static String compressJsonMap(dynamic map) {
    final compressed = _compressNode(map);
    return '$magicHeader${jsonEncode(compressed)}';
  }

  static String decompressJsonString(String compressedStr) {
    if (!compressedStr.startsWith(magicHeader)) {
      return compressedStr;
    }
    final content = compressedStr.substring(magicHeader.length);
    try {
      final dynamic decoded = jsonDecode(content);
      final decompressed = _decompressNode(decoded);
      return jsonEncode(decompressed);
    } catch (_) {
      return content;
    }
  }

  static dynamic decompressToMap(String compressedStr) {
    if (!compressedStr.startsWith(magicHeader)) {
      try {
        return jsonDecode(compressedStr);
      } catch (_) {
        return compressedStr;
      }
    }
    final content = compressedStr.substring(magicHeader.length);
    final dynamic decoded = jsonDecode(content);
    return _decompressNode(decoded);
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
    final dictCompressed = DomainDictionaryCompressor.compressJsonMap(json);
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
  static const int _binaryHeaderLength = 54;
  static const int _legacyBinaryHeaderLength = 30;
  static const List<int> _binaryMagic = [0x53, 0x4d, 0x58, 0x32]; // SMX2

  final String sessionId;
  final int sequence;
  final int totalBlocks;
  final int payloadLength;
  final String fullSha256;
  final int crc32;
  final Uint8List blockData;
  final Set<int> blockIndices;

  const StreamFrame({
    required this.sessionId,
    required this.sequence,
    required this.totalBlocks,
    required this.payloadLength,
    String? fullSha256,
    String? shaPrefix,
    required this.crc32,
    required this.blockData,
    required this.blockIndices,
  }) : fullSha256 = fullSha256 ?? shaPrefix ?? '';

  String get shaPrefix =>
      fullSha256.length >= 16 ? fullSha256.substring(0, 16) : fullSha256;

  /// Compact byte-mode QR payload. Supports full 256-bit SHA-256 (54-byte header)
  /// or legacy 64-bit prefix (30-byte header).
  ///
  /// V2 Layout (54 B): magic(4) | session(4) | sequence(4) | block count(2) |
  /// payload length(4) | full SHA-256(32) | CRC-32(4) | encoded block.
  Uint8List toQrBytes() {
    final isFullSha = fullSha256.length >= 64;
    final headerLength = isFullSha ? _binaryHeaderLength : _legacyBinaryHeaderLength;
    final bytes = Uint8List(headerLength + blockData.length);
    bytes.setRange(0, _binaryMagic.length, _binaryMagic);
    final header = ByteData.sublistView(bytes);
    header.setUint32(4, QrStreamEncoder.sessionToken(sessionId));
    header.setUint32(8, sequence);
    header.setUint16(12, totalBlocks);
    header.setUint32(14, payloadLength);

    if (isFullSha) {
      final normalizedSha = fullSha256.padRight(64, '0').substring(0, 64);
      for (var index = 0; index < 32; index++) {
        header.setUint8(
          18 + index,
          int.parse(normalizedSha.substring(index * 2, index * 2 + 2), radix: 16),
        );
      }
      header.setUint32(50, crc32);
    } else {
      final normalizedPrefix = fullSha256.padRight(16, '0').substring(0, 16);
      for (var index = 0; index < 8; index++) {
        header.setUint8(
          18 + index,
          int.parse(normalizedPrefix.substring(index * 2, index * 2 + 2), radix: 16),
        );
      }
      header.setUint32(26, crc32);
    }

    bytes.setRange(headerLength, bytes.length, blockData);
    return bytes;
  }

  static bool isBinaryFrame(Uint8List raw) =>
      raw.length >= _legacyBinaryHeaderLength &&
      raw[0] == _binaryMagic[0] &&
      raw[1] == _binaryMagic[1] &&
      raw[2] == _binaryMagic[2] &&
      raw[3] == _binaryMagic[3];

  /// A small, stable key for dropping a repeated camera result before the
  /// decoder allocates or performs fountain-code work.
  static String? binaryFrameKey(Uint8List raw) {
    if (!isBinaryFrame(raw)) return null;
    final header = ByteData.sublistView(raw);
    final crcOffset = raw.length >= _binaryHeaderLength ? 50 : 26;
    return 'SMX2:${header.getUint32(4)}:${header.getUint32(8)}:${header.getUint32(crcOffset)}';
  }

  static StreamFrame? parseBytes(Uint8List raw) {
    try {
      if (!isBinaryFrame(raw)) return null;
      final header = ByteData.sublistView(raw);
      final totalBlocks = header.getUint16(12);
      final payloadLength = header.getUint32(14);
      if (totalBlocks == 0 || payloadLength == 0) return null;

      // 1. Check full 256-bit SHA-256 header (54 bytes)
      if (raw.length >= _binaryHeaderLength) {
        final blockData = raw.sublist(_binaryHeaderLength);
        if (blockData.isNotEmpty) {
          final crc32 = header.getUint32(50);
          if (Crc32.compute(blockData) == crc32) {
            final sessionId = header.getUint32(4).toRadixString(16).padLeft(8, '0');
            final fullSha256 = List.generate(
              32,
              (index) => header.getUint8(18 + index).toRadixString(16).padLeft(2, '0'),
            ).join();
            final sequence = header.getUint32(8);
            return StreamFrame(
              sessionId: sessionId,
              sequence: sequence,
              totalBlocks: totalBlocks,
              payloadLength: payloadLength,
              fullSha256: fullSha256,
              crc32: crc32,
              blockData: Uint8List.fromList(blockData),
              blockIndices: QrStreamEncoder.indicesForSeq(
                sessionId,
                sequence,
                totalBlocks,
              ),
            );
          }
        }
      }

      // 2. Fallback check for legacy 64-bit prefix header (30 bytes)
      if (raw.length >= _legacyBinaryHeaderLength) {
        final blockData = raw.sublist(_legacyBinaryHeaderLength);
        if (blockData.isNotEmpty) {
          final crc32 = header.getUint32(26);
          if (Crc32.compute(blockData) == crc32) {
            final sessionId = header.getUint32(4).toRadixString(16).padLeft(8, '0');
            final shaPrefix = List.generate(
              8,
              (index) => header.getUint8(18 + index).toRadixString(16).padLeft(2, '0'),
            ).join();
            final sequence = header.getUint32(8);
            return StreamFrame(
              sessionId: sessionId,
              sequence: sequence,
              totalBlocks: totalBlocks,
              payloadLength: payloadLength,
              fullSha256: shaPrefix,
              crc32: crc32,
              blockData: Uint8List.fromList(blockData),
              blockIndices: QrStreamEncoder.indicesForSeq(
                sessionId,
                sequence,
                totalBlocks,
              ),
            );
          }
        }
      }

      return null;
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

  /// Converts any legacy/custom session label to the 32-bit session token
  /// carried by the byte-mode frame. Generated sessions are already 8 hex
  /// digits, so this is lossless for live transfers.
  static int sessionToken(String sessionId) {
    final parsed = int.tryParse(sessionId, radix: 16);
    if (parsed != null && sessionId.length <= 8) return parsed & 0xFFFFFFFF;
    return Crc32.compute(utf8.encode(sessionId));
  }

  /// Generate pseudo-random or systematic block indices for a given sequence number.
  static Set<int> indicesForSeq(String sessionId, int seq, int k) =>
      _indicesForSeed(sessionToken(sessionId), seq, k);

  static Set<int> _indicesForSeed(int sessionSeed, int seq, int k) {
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
    // Seed = session token ^ (seq * 0x9E3779B9)
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

    return StreamFrame(
      sessionId: payload.sessionId,
      sequence: seq,
      totalBlocks: payload.totalBlocks,
      payloadLength: payload.compressedData.length,
      fullSha256: payload.fullSha256,
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
  String? _expectedFullSha256;
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

  int get resolvedCount => _resolvedCount;
  int get totalBlocks => _totalBlocks;
  double get progress => _totalBlocks == 0 ? 0.0 : (_resolvedCount / _totalBlocks).clamp(0.0, 1.0);
  bool isBlockResolved(int index) =>
      index >= 0 && index < _resolvedBlocks.length && _resolvedBlocks[index] != null;

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

  /// Process a compact byte-mode SMX2 QR frame.
  bool processRawBytes(Uint8List raw) {
    _framesCaptured++;
    final frame = StreamFrame.parseBytes(raw);
    if (frame == null) {
      _rejectedFrames++;
      return false;
    }

    _firstFrameAt ??= DateTime.now();
    if (_currentSessionId == null ||
        (_resolvedCount == 0 && _currentSessionId != frame.sessionId)) {
      _initSession(frame);
    } else if (frame.sessionId != _currentSessionId) {
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
    _expectedFullSha256 = frame.fullSha256;
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
      return VerificationResult.failure(
        'Reconstruction incomplete: $_resolvedCount of $_totalBlocks blocks',
      );
    }

    final job = _DecompressJob(
      reconstructedPayload: _reconstructedPayload!,
      payloadLength: _payloadLength,
      expectedFullSha256: expectedFullSha256 ?? _expectedFullSha256,
      shaPrefix: _shaPrefix,
      transferDuration: transferDuration,
    );

    final result = _verifyAndDecompressWorker(job);
    if (result.isValid && result.sha256 != null) {
      _verifiedSha256 = result.sha256;
    }
    return result;
  }

  /// Finalize and verify the full reconstructed payload on a background worker isolate.
  Future<VerificationResult> verifyAndDecompressAsync({String? expectedFullSha256}) async {
    if (!isComplete || _reconstructedPayload == null) {
      return VerificationResult.failure(
        'Reconstruction incomplete: $_resolvedCount of $_totalBlocks blocks',
      );
    }

    final job = _DecompressJob(
      reconstructedPayload: _reconstructedPayload!,
      payloadLength: _payloadLength,
      expectedFullSha256: expectedFullSha256 ?? _expectedFullSha256,
      shaPrefix: _shaPrefix,
      transferDuration: transferDuration,
    );

    final result = await compute(_verifyAndDecompressWorker, job);
    if (result.isValid && result.sha256 != null) {
      _verifiedSha256 = result.sha256;
    }
    return result;
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
    _expectedFullSha256 = null;
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

class _DecompressJob {
  final Uint8List reconstructedPayload;
  final int payloadLength;
  final String? expectedFullSha256;
  final String? shaPrefix;
  final Duration? transferDuration;

  _DecompressJob({
    required this.reconstructedPayload,
    required this.payloadLength,
    this.expectedFullSha256,
    this.shaPrefix,
    this.transferDuration,
  });
}

VerificationResult _verifyAndDecompressWorker(_DecompressJob job) {
  try {
    final decompressed = Uint8List.fromList(
      ZLibDecoder().decodeBytes(job.reconstructedPayload),
    );

    final fullSha = sha256.convert(decompressed).toString();

    final targetFullSha = job.expectedFullSha256;
    if (targetFullSha != null && targetFullSha.length == 64) {
      if (fullSha.toLowerCase() != targetFullSha.toLowerCase()) {
        return VerificationResult.failure('Full SHA-256 hash mismatch. Data may be corrupted.');
      }
    } else if (job.shaPrefix != null && !fullSha.startsWith(job.shaPrefix!)) {
      return VerificationResult.failure('SHA-256 prefix mismatch. Data may be corrupted.');
    }

    final rawUtf8String = utf8.decode(decompressed);
    final dynamic decoded = DomainDictionaryCompressor.decompressToMap(rawUtf8String);
    if (decoded is! Map<String, dynamic>) {
      return VerificationResult.failure('Decoded payload is not a valid Stockmix bundle.');
    }

    return VerificationResult.success(
      payload: decoded,
      sha256: fullSha,
      rawBytesLength: decompressed.length,
      transferDuration: job.transferDuration,
    );
  } catch (e) {
    return VerificationResult.failure('Decompression or JSON parse error: $e');
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
