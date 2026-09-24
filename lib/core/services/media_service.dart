import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

// Native image decoding and ML Kit both run outside Dart's normal exception
// handling.  In particular, a native OCR request can remain pending on a
// small number of Android release builds.  Keep either operation from holding
// the photo picker UI open indefinitely.
const _compressionTimeout = Duration(seconds: 30);
const _textRecognitionTimeout = Duration(seconds: 12);
const _recognizerCloseTimeout = Duration(seconds: 2);

Future<T> _completeWithin<T>(
  Future<T> operation,
  Duration timeout,
  String timeoutMessage,
) => operation.timeout(
  timeout,
  onTimeout: () => throw StateError(timeoutMessage),
);

Future<XFile?> _selectPhoto(ImageSource source) => ImagePicker().pickImage(
  source: source,
  // Preserve enough resolution for label text.  The image is independently
  // compressed below before it is saved with the product.
  maxWidth: 2048,
  maxHeight: 2048,
  imageQuality: 90,
);

Future<Uint8List> _readPhotoBytes(XFile file) async {
  if (await file.length() > 20 * 1024 * 1024) {
    throw const FormatException('Choose a photo smaller than 20 MB.');
  }
  return file.readAsBytes();
}

String compressImage(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException(
      'This image could not be read. Try a JPEG or PNG.',
    );
  }
  var image = img.bakeOrientation(decoded);
  // Keep max dimensions at 800px for crisp mobile display while keeping size ultra compact
  if (image.width > 800 || image.height > 800) {
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 800 : null,
      height: image.height > image.width ? 800 : null,
    );
  }
  var output = img.encodeJpg(image, quality: 70);
  if (output.length > 120000) {
    // If still over 120KB, downscale to 600px with quality 55
    image = img.copyResize(
      image,
      width: image.width >= image.height ? 600 : null,
      height: image.height > image.width ? 600 : null,
    );
    output = img.encodeJpg(image, quality: 55);
  }
  if (output.length > 300000) {
    throw const FormatException('Image is too detailed. Try a smaller photo.');
  }
  return base64Encode(output);
}

Future<String?> pickPhoto(ImageSource source) async {
  final file = await _selectPhoto(source);
  if (file == null) return null;
  final bytes = await _readPhotoBytes(file);
  return _completeWithin(
    compute(compressImage, bytes),
    _compressionTimeout,
    'Photo processing took too long. Try a smaller photo.',
  );
}

class PhotoWithText {
  final String base64Image;

  /// OCR continues after the compressed image is ready, so a slow native
  /// recognizer never blocks attaching the photo.
  final Future<List<String>> extractedText;
  const PhotoWithText({required this.base64Image, required this.extractedText});
}

bool get isTextRecognitionSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

Future<List<String>> extractTextFromImage(String filePath) async {
  if (!isTextRecognitionSupported) return const [];
  final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
  try {
    final inputImage = InputImage.fromFilePath(filePath);
    final recognizedText = await recognizer
        .processImage(inputImage)
        .timeout(_textRecognitionTimeout);

    final scoredLines = <MapEntry<String, double>>[];
    for (final block in recognizedText.blocks) {
      for (final line in block.lines) {
        final text = line.text.trim();
        // Ignore single characters, pure numbers, or barcodes
        if (text.length >= 2 &&
            !RegExp(r'^\d+$').hasMatch(text) &&
            !RegExp(r'^[^\w\s]+$').hasMatch(text)) {
          final clean = text.replaceAll(RegExp(r'\s+'), ' ');
          final height = line.boundingBox.height;
          scoredLines.add(MapEntry(clean, height));
        }
      }
    }

    // Sort by font size descending (prominent title text first)
    scoredLines.sort((a, b) => b.value.compareTo(a.value));

    final results = <String>[];
    for (final entry in scoredLines) {
      if (!results.contains(entry.key)) {
        results.add(entry.key);
      }
    }
    return results;
  } catch (_) {
    // Text suggestions are optional.  A device-specific ML Kit failure must
    // not prevent the selected image from being attached to the product.
    return const [];
  } finally {
    try {
      await recognizer.close().timeout(_recognizerCloseTimeout);
    } catch (_) {
      // Closing a stalled native recognizer is best effort.
    }
  }
}

Future<PhotoWithText?> pickPhotoWithText(ImageSource source) async {
  final file = await _selectPhoto(source);
  if (file == null) return null;

  final bytes = await _readPhotoBytes(file);
  final textFuture = extractTextFromImage(file.path);
  final base64Image = await _completeWithin(
    compute(compressImage, bytes),
    _compressionTimeout,
    'Photo processing took too long. Try a smaller photo.',
  );
  return PhotoWithText(base64Image: base64Image, extractedText: textFuture);
}
