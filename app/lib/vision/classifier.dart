// MobileNetV3-Large, full-integer INT8 PTQ TFLite (int8 weights+activations,
// float32 I/O so the whole graph is XNNPACK-delegable). Inference runs in
// android/.../VisionBridge.kt on the Arm CPU; here we only crop/resize.
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class Prediction {
  final String label;
  final double score;
  Prediction(this.label, this.score);
}

class DiseaseClassifier {
  static const int size = 224;
  static const _ch = MethodChannel('krishi/vision');
  late final List<String> labels;
  double lastInferenceMs = 0;

  Future<void> load() async {
    await _ch.invokeMethod<int>('load');
    labels = (await rootBundle.loadString('assets/labels.txt'))
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Returns top-k predictions, best first.
  Future<List<Prediction>> classify(img.Image image, {int k = 3}) async {
    final sq = preprocess(image, size);
    final rgb = Uint8List(size * size * 3);
    var j = 0;
    for (final p in sq) {
      rgb[j++] = p.r.toInt();
      rgb[j++] = p.g.toInt();
      rgb[j++] = p.b.toInt();
    }
    final r = Map<String, dynamic>.from((await _ch.invokeMethod<Map<dynamic, dynamic>>('classify', rgb))!);
    lastInferenceMs = (r['ms'] as num).toDouble();
    final probs = List<double>.from(r['probs'] as List);
    final idx = List<int>.generate(probs.length, (i) => i)..sort((a, b) => probs[b].compareTo(probs[a]));
    return [for (final i in idx.take(k)) Prediction(labels[i], probs[i])];
  }

  Future<void> close() => _ch.invokeMethod('close');
}

/// Same geometry as training (ml/prepare_unified.py + train_folder_classifier.py):
/// antialiased downscale so the longest side is 320 (PIL thumbnail), then a
/// bilinear squash of the whole frame to size x size (tf.image.resize, no
/// centre crop). Measured on PlantDoc field photos this lifts disease accuracy
/// from 47.9% to 52.5% and crop accuracy from 57.6% to 67.4% vs the old
/// nearest-neighbour + centre-crop path.
img.Image preprocess(img.Image image, int size) {
  const thumb = 320;
  if (image.width > thumb || image.height > thumb) {
    image = image.width >= image.height
        ? img.copyResize(image, width: thumb, interpolation: img.Interpolation.average)
        : img.copyResize(image, height: thumb, interpolation: img.Interpolation.average);
  }
  return img.copyResize(image, width: size, height: size, interpolation: img.Interpolation.linear);
}
