import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:stockmix/qr_stream/qr_stream_coder.dart';
import 'package:stockmix/qr_stream/entry_hasher.dart';
import 'package:stockmix/stock_store.dart';

void main() {
  group('CRC32 & Frame Formatting', () {
    test('computes correct IEEE 802.3 CRC32 checksums', () {
      final data = Uint8List.fromList(utf8.encode('123456789'));
      final crc = Crc32.compute(data);
      // Standard CRC-32 of '123456789' is 0xCBF43926
      expect(crc, 0xCBF43926);
    });

    test('roundtrips valid SMX1 frame to and from QR string', () {
      final dummyData = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final crc = Crc32.compute(dummyData);
      final frame = StreamFrame(
        sessionId: 'a1b2c3d4',
        sequence: 2,
        totalBlocks: 5,
        payloadLength: 42,
        shaPrefix: '9f8e7d6c5b4a3210',
        crc32: crc,
        blockData: dummyData,
        blockIndices: {2},
      );

      final qrString = frame.toQrString();
      expect(qrString.startsWith('SMX1:a1b2c3d4:2:5:42:9f8e7d6c5b4a3210:'), isTrue);

      final parsed = StreamFrame.parse(qrString);
      expect(parsed, isNotNull);
      expect(parsed!.sessionId, 'a1b2c3d4');
      expect(parsed.sequence, 2);
      expect(parsed.totalBlocks, 5);
      expect(parsed.payloadLength, 42);
      expect(parsed.blockData, dummyData);
    });

    test('rejects frame with corrupt CRC32 checksum', () {
      final dummyData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final b64 = base64Url.encode(dummyData);
      // Corrupt CRC
      final corruptString = 'SMX1:sess1:0:1:5:sha12345:deadbeef:$b64';
      final parsed = StreamFrame.parse(corruptString);
      expect(parsed, isNull);
    });
  });

  group('Fountain Stream Encoding & Peeling Decoder', () {
    late Map<String, dynamic> sampleBundle;

    setUp(() {
      sampleBundle = {
        'format': 'stockmix',
        'version': 1,
        'id': 'test-bundle-001',
        'kind': 'Stock snapshot',
        'shop': 'Downtown Artisan',
        'currency': 'USD',
        'exportedAt': '2026-09-06T12:00:00.000Z',
        'products': List.generate(
          20,
          (i) => {
            'id': 'prod-$i',
            'name': 'Item $i Specialty Blend',
            'category': 'Pantry',
            'barcode': 'SM00${100 + i}',
            'price': 1200 + i * 50,
            'cost': 600 + i * 25,
            'opening': 15 + i,
            'threshold': 5,
            'unit': 'pcs',
            'onHand': 15 + i,
          },
        ),
        'movements': [
          {
            'id': 'mov-1',
            'productId': 'prod-0',
            'name': 'Item 0 Specialty Blend',
            'type': 'Sale',
            'delta': -2,
            'price': 1200,
            'cost': 600,
            'note': 'Morning sale',
            'reference': 'ref-100',
            'at': '2026-09-06T12:10:00.000Z',
          }
        ],
      };
    });

    test('reconstructs payload with sequential systematic frames', () {
      final prepared = StreamPreparedPayload.fromJson(sampleBundle, blockSize: 150);
      expect(prepared.totalBlocks, greaterThan(3));

      final encoder = QrStreamEncoder(prepared);
      final decoder = QrStreamDecoder();

      for (var i = 0; i < prepared.totalBlocks; i++) {
        final frame = encoder.nextFrame();
        final advanced = decoder.processRawFrame(frame.toQrString());
        expect(advanced, isTrue);
      }

      expect(decoder.isComplete, isTrue);
      final result = decoder.verifyAndDecompress();
      expect(result.isValid, isTrue);
      expect(result.payload!['id'], 'test-bundle-001');
      expect(result.payload!['shop'], 'Downtown Artisan');
      expect((result.payload!['products'] as List).length, 20);
      expect(result.sha256, prepared.fullSha256);
    });

    test('reconstructs payload with out-of-order and duplicate frames', () {
      final prepared = StreamPreparedPayload.fromJson(sampleBundle, blockSize: 120);
      final encoder = QrStreamEncoder(prepared);
      final decoder = QrStreamDecoder();

      final frames = <StreamFrame>[];
      for (var i = 0; i < prepared.totalBlocks * 2; i++) {
        frames.add(encoder.nextFrame());
      }

      // Shuffle frames and add duplicates
      final shuffled = List<StreamFrame>.from(frames)..shuffle();
      shuffled.insert(0, frames.last);
      shuffled.insert(3, frames.first);

      for (final f in shuffled) {
        decoder.processRawFrame(f.toQrString());
        if (decoder.isComplete) break;
      }

      expect(decoder.isComplete, isTrue);
      final result = decoder.verifyAndDecompress();
      expect(result.isValid, isTrue);
      expect(result.payload!['products'].length, 20);
    });

    test('reconstructs when systematic frames are dropped using fountain droplets', () {
      // Slicing into 6 blocks: drop half the systematic frames, but rateless droplets recover them!
      final prepared = StreamPreparedPayload.fromJson(sampleBundle, blockSize: 180);
      final encoder = QrStreamEncoder(prepared);
      final decoder = QrStreamDecoder();

      final allFrames = <StreamFrame>[];
      for (var i = 0; i < prepared.totalBlocks * 4; i++) {
        allFrames.add(encoder.nextFrame());
      }

      // Drop frames 1, 3, 4 (simulating camera missing frames during movement)
      final missingIndices = {1, 3, 4};
      final streamWithMisses = <StreamFrame>[];

      for (final frame in allFrames) {
        if (frame.sequence < prepared.totalBlocks && missingIndices.contains(frame.sequence)) {
          continue; // Missed!
        }
        streamWithMisses.add(frame);
      }

      for (final f in streamWithMisses) {
        decoder.processRawFrame(f.toQrString());
        if (decoder.isComplete) break;
      }

      expect(decoder.isComplete, isTrue);
      final result = decoder.verifyAndDecompress();
      expect(result.isValid, isTrue);
      expect(result.payload!['shop'], 'Downtown Artisan');
    });

    test('detects full SHA-256 hash mismatch if data corrupted', () {
      final prepared = StreamPreparedPayload.fromJson(sampleBundle, blockSize: 150);
      final encoder = QrStreamEncoder(prepared);
      final decoder = QrStreamDecoder();

      for (var i = 0; i < prepared.totalBlocks; i++) {
        decoder.processRawFrame(encoder.nextFrame().toQrString());
      }

      expect(decoder.isComplete, isTrue);
      // Verify with wrong expected SHA-256
      final result = decoder.verifyAndDecompress(expectedFullSha256: '0000000000000000000000000000000000000000000000000000000000000000');
      expect(result.isValid, isFalse);
      expect(result.errorMessage, contains('hash mismatch'));
    });
  });

  group('Duplicate-Safe Entry Hashing & Deduplication', () {
    late StockStore store;

    setUp(() async {
      store = StockStore(persist: (_) async {});
      // Seed store with initial products and a movement
      final p1 = const Product(
        id: 'local-1',
        name: 'Dark Roast Coffee',
        category: 'Pantry',
        barcode: '1234567890123',
        price: 500,
        cost: 250,
        opening: 10,
        threshold: 3,
        unit: 'pcs',
      );
      await store.saveProduct(p1);
    });

    test('generates deterministic canonical product and movement hashes', () {
      const pA = Product(
        id: 'any-id-1',
        name: 'Dark Roast Coffee',
        category: 'Any Category',
        barcode: '1234567890123',
        price: 500,
        cost: 250,
        opening: 5,
        threshold: 3,
        unit: 'pcs',
      );
      const pB = Product(
        id: 'different-id-2',
        name: '  dark roast coffee  ',
        category: 'Other Category',
        barcode: '1234567890123',
        price: 500,
        cost: 250,
        opening: 20,
        threshold: 3,
        unit: 'PCS',
      );

      // Content hashes must match despite different IDs or whitespace/casing differences
      final hashA = EntryHasher.productHash(pA);
      final hashB = EntryHasher.productHash(pB);
      expect(hashA, hashB);
    });

    test('StreamImportAnalysis accurately identifies new vs duplicate items', () {
      final bundle = {
        'id': 'bundle-incoming',
        'kind': 'Stock snapshot',
        'shop': 'Partner Shop',
        'currency': 'USD',
        'exportedAt': '2026-09-06T12:00:00.000Z',
        'products': [
          // 1. Duplicate by barcode
          {
            'id': 'incoming-1',
            'name': 'Dark Roast Coffee',
            'category': 'Pantry',
            'barcode': '1234567890123',
            'price': 500,
            'cost': 250,
            'opening': 10,
            'threshold': 3,
            'unit': 'pcs',
            'onHand': 10,
          },
          // 2. Brand new item
          {
            'id': 'incoming-2',
            'name': 'Matcha Green Tea',
            'category': 'Pantry',
            'barcode': '9998887776665',
            'price': 850,
            'cost': 400,
            'opening': 12,
            'threshold': 4,
            'unit': 'tin',
            'onHand': 12,
          },
        ],
        'movements': [],
      };

      final analysis = StreamImportAnalysis.analyze(bundle, store);
      expect(analysis.totalProducts, 2);
      expect(analysis.newProductsCount, 1);
      expect(analysis.duplicateProductsCount, 1);
      expect(analysis.products[0].isDuplicate, isTrue);
      expect(analysis.products[0].matchReason, contains('1234567890123'));
      expect(analysis.products[1].isDuplicate, isFalse);
    });

    test('importStreamBundle safely skips duplicate products and duplicate movements', () async {
      final bundle = {
        'format': 'stockmix',
        'version': 1,
        'id': 'stream-test-01',
        'kind': 'Stock snapshot',
        'shop': 'Branch Two',
        'currency': 'USD',
        'exportedAt': '2026-09-06T13:00:00.000Z',
        'products': [
          // Duplicate barcode
          {
            'id': 'b2-p1',
            'name': 'Dark Roast Coffee',
            'category': 'Pantry',
            'barcode': '1234567890123',
            'price': 500,
            'cost': 250,
            'opening': 10,
            'threshold': 3,
            'unit': 'pcs',
            'onHand': 50,
          },
          // New product
          {
            'id': 'b2-p2',
            'name': 'Earl Grey Tea',
            'category': 'Pantry',
            'barcode': '5555555555555',
            'price': 650,
            'cost': 300,
            'opening': 8,
            'threshold': 2,
            'unit': 'box',
            'onHand': 8,
          },
        ],
        'movements': [],
      };

      expect(store.products.length, 1);
      await store.importStreamBundle(bundle, addProducts: true);

      // Total products should be 2: original + 1 new. The duplicate barcode was safely skipped!
      expect(store.products.length, 2);
      expect(store.products.any((p) => p.name == 'Earl Grey Tea'), isTrue);

      // Re-importing the identical bundle does not throw or double-record
      await store.importStreamBundle(bundle, addProducts: true);
      expect(store.products.length, 2);
      expect(store.received.length, 1);
    });
  });

  group('Domain Dictionary Pre-Compression & Timing Telemetry', () {
    test('roundtrips JSON through DomainDictionaryCompressor and reduces size', () {
      final originalJson = {
        'format': 'stockmix',
        'version': 1,
        'id': 'snap-123',
        'kind': 'Stock snapshot',
        'shop': 'Artisan Bakery',
        'currency': 'USD',
        'exportedAt': '2026-09-06T14:00:00.000Z',
        'products': [
          {
            'id': 'p1',
            'name': 'Sourdough Loaf',
            'category': 'Bakery',
            'barcode': '1234567890123',
            'price': 600,
            'cost': 200,
            'opening': 10,
            'threshold': 2,
            'unit': 'loaf',
            'photo': null,
            'onHand': 10,
          },
          {
            'id': 'p2',
            'name': 'Croissant',
            'category': 'Bakery',
            'barcode': '9876543210987',
            'price': 350,
            'cost': 120,
            'opening': 25,
            'threshold': 5,
            'unit': 'pcs',
            'photo': null,
            'onHand': 20,
          }
        ],
        'movements': [
          {
            'id': 'm1',
            'productId': 'p1',
            'name': 'Sourdough Loaf',
            'type': 'Sale',
            'delta': -2,
            'price': 600,
            'cost': 200,
            'note': 'Morning rush',
            'reference': 'ref-1',
            'at': '2026-09-06T14:15:00.000Z',
          }
        ],
      };

      final jsonStr = jsonEncode(originalJson);
      final compressed = DomainDictionaryCompressor.compressJsonString(jsonStr);

      // Verify compression reduced length and contains magic header
      expect(compressed.startsWith(DomainDictionaryCompressor.magicHeader), isTrue);
      expect(compressed.length, lessThan(jsonStr.length));

      // Verify exact lossless roundtrip
      final decompressed = DomainDictionaryCompressor.decompressJsonString(compressed);
      final dynamic restored = jsonDecode(decompressed);
      expect(restored['format'], 'stockmix');
      expect(restored['kind'], 'Stock snapshot');
      expect(restored['products'].length, 2);
      expect(restored['movements'].length, 1);
      expect(restored['products'][0]['name'], 'Sourdough Loaf');
      expect(restored['movements'][0]['type'], 'Sale');
    });

    test('backward compatibility: handles non-dictionary raw JSON cleanly', () {
      const raw = '{"format":"stockmix","test":true}';
      final res = DomainDictionaryCompressor.decompressJsonString(raw);
      expect(res, raw);
    });

    test('decoder tracks transferDuration accurately from first frame to completion', () {
      final sample = {
        'format': 'stockmix',
        'version': 1,
        'id': 'bundle-timing-test',
        'kind': 'Day record',
        'shop': 'Quick Stop',
        'currency': 'USD',
        'exportedAt': '2026-09-06T15:00:00.000Z',
        'products': [
          {
            'id': 'tp1',
            'name': 'Sparkling Water',
            'category': 'Drinks',
            'barcode': '1122334455667',
            'price': 200,
            'cost': 80,
            'opening': 24,
            'threshold': 6,
            'unit': 'can',
            'onHand': 24,
          }
        ],
        'movements': [],
      };

      final prepared = StreamPreparedPayload.fromJson(sample, blockSize: 150);
      final encoder = QrStreamEncoder(prepared);
      final decoder = QrStreamDecoder();

      expect(decoder.firstFrameAt, isNull);
      expect(decoder.completedAt, isNull);
      expect(decoder.transferDuration, isNull);

      for (var i = 0; i < prepared.totalBlocks; i++) {
        decoder.processRawFrame(encoder.nextFrame().toQrString());
      }

      expect(decoder.isComplete, isTrue);
      expect(decoder.firstFrameAt, isNotNull);
      expect(decoder.completedAt, isNotNull);
      expect(decoder.transferDuration, isNotNull);

      final result = decoder.verifyAndDecompress();
      expect(result.isValid, isTrue);
      expect(result.transferDuration, isNotNull);
      expect(result.payload!['id'], 'bundle-timing-test');
    });
  });
}
