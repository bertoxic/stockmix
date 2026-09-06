import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

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
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1024,
    maxHeight: 1024,
    imageQuality: 75,
  );
  if (file == null) return null;
  if (await file.length() > 20 * 1024 * 1024) {
    throw const FormatException('Choose a photo smaller than 20 MB.');
  }
  return compute(compressImage, await file.readAsBytes());
}

class PhotoWithText {
  final String base64Image;
  final List<String> extractedText;
  const PhotoWithText({
    required this.base64Image,
    required this.extractedText,
  });
}

bool get isTextRecognitionSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

Future<List<String>> extractTextFromImage(String filePath) async {
  if (!isTextRecognitionSupported) return const [];
  try {
    final inputImage = InputImage.fromFilePath(filePath);
    final recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    final RecognizedText recognizedText;
    try {
      recognizedText = await recognizer.processImage(inputImage);
    } finally {
      await recognizer.close();
    }

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
    return const [];
  }
}

Future<PhotoWithText?> pickPhotoWithText(ImageSource source) async {
  final file = await ImagePicker().pickImage(
    source: source,
    maxWidth: 1024,
    maxHeight: 1024,
    imageQuality: 75,
  );
  if (file == null) return null;
  if (await file.length() > 20 * 1024 * 1024) {
    throw const FormatException('Choose a photo smaller than 20 MB.');
  }

  final bytes = await file.readAsBytes();
  final textFuture = extractTextFromImage(file.path);
  final compressFuture = compute(compressImage, bytes);

  final results = await Future.wait([textFuture, compressFuture]);
  return PhotoWithText(
    extractedText: results[0] as List<String>,
    base64Image: results[1] as String,
  );
}
