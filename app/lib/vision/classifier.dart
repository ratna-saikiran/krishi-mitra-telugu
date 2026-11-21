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
    final sq = img.copyResizeCropSquare(image, size: size, interpolation: img.Interpolation.linear);
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
