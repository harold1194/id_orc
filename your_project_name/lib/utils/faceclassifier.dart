import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:image/image.dart'
    as img; // Gagamit ng prefix para hindi mag-conflict sa Flutter Canvas
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceClassifier {
  Interpreter? _interpreter;

  // I-load ang TFLite Model mula sa assets
  Future<void> loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset(
        'assets/model/mobilefacenet.tflite',
      );
      print('TFLite Model loaded successfully.');
    } catch (e) {
      print('Failed to load TFLite model: $e');
    }
  }

  // Pangunahing function para i-crop ang mukha base sa bounding box ng ML Kit
  img.Image? cropFace(File imageFile, Face face) {
    final bytes = imageFile.readAsBytesSync();
    final originalImage = img.decodeImage(bytes);
    if (originalImage == null) return null;

    // Kunin ang coordinates mula sa ML Kit Face bounding box
    int x = face.boundingBox.left.toInt();
    int y = face.boundingBox.top.toInt();
    int w = face.boundingBox.width.toInt();
    int h = face.boundingBox.height.toInt();

    // I-crop ang mukha at i-resize sa 112x112 (ito ang karaniwang input size ng MobileFaceNet)
    final cropped = img.copyCrop(
      originalImage,
      x: x,
      y: y,
      width: w,
      height: h,
    );
    return img.copyResize(cropped, width: 112, height: 112);
  }

  // Kunin ang "Face Embeddings" (Array ng mga numero na naglalarawan sa mukha)
  List<double> getEmbeddings(img.Image croppedFace) {
    if (_interpreter == null) return [];

    // I-convert ang imahe sa Float32List input tensor format [1, 112, 112, 3]
    var input = Float32List(1 * 112 * 112 * 3);
    var buffer = Float32List.view(input.buffer);
    int pixelIndex = 0;

    for (int y = 0; y < 112; y++) {
      for (int x = 0; x < 112; x++) {
        final pixel = croppedFace.getPixel(x, y);
        // I-normalize ang RGB values mula 0-255 papuntang -1 hanggang 1 (depende sa model requirements)
        buffer[pixelIndex++] = (pixel.r - 127.5) / 127.5;
        buffer[pixelIndex++] = (pixel.g - 127.5) / 127.5;
        buffer[pixelIndex++] = (pixel.b - 127.5) / 127.5;
      }
    }

    // Maghanda ng lalagyan ng output (MobileFaceNet ay nagbabalik ng 1x192 array)
    var output = List.filled(1 * 192, 0.0).reshape([1, 192]);

    // Patakbuhin ang AI Model Inference
    _interpreter!.run(input.reshape([1, 112, 112, 3]), output);

    // Ibalik ang patag na listahan ng mga embeddings
    return List<double>.from(output[0]);
  }

  // Math calculation gamit ang Cosine Similarity para makuha ang percentage score
  double compareFaces(List<double> emb1, List<double> emb2) {
    if (emb1.isEmpty || emb2.isEmpty) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < emb1.length; i++) {
      dotProduct += emb1[i] * emb2[i];
      normA += pow(emb1[i], 2);
      normB += pow(emb2[i], 2);
    }

    double similarity = dotProduct / (sqrt(normA) * sqrt(normB));

    // I-convert ang similarity (-1 to 1) sa isang madaling basahing percentage (0% to 100%)
    double percentage = ((similarity + 1) / 2) * 100;
    return percentage;
  }
}
