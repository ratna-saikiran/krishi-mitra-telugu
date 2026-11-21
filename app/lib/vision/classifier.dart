// MobileNetV3-Large, full-integer INT8 PTQ TFLite (int8 weights+activations).
// I/O is float32: input [1,224,224,3] raw RGB 0-255 (rescaling is inside the
// model), output softmax [1,C]. Float I/O keeps the graph XNNPACK-delegable.
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class Prediction {
  final String label;
  final double score;
  Prediction(this.label, this.score);
}

class DiseaseClassifier {
  static const int size = 224;
  late final Interpreter _interp;
  late final List<String> labels;

  Future<void> load() async {
    final opts = InterpreterOptions()..threads = 4;
    _interp = await Interpreter.fromAsset('assets/models/classifier_int8.tflite', options: opts);
    labels = (await rootBundle.loadString('assets/labels.txt'))
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Returns top-k predictions, best first.
  List<Prediction> classify(img.Image image, {int k = 3}) {
    final sq = img.copyResizeCropSquare(image, size: size, interpolation: img.Interpolation.linear);
    final input = Float32List(size * size * 3);
    var j = 0;
    for (final p in sq) {
      input[j++] = p.r.toDouble();
      input[j++] = p.g.toDouble();
      input[j++] = p.b.toDouble();
    }
    final out = [List<double>.filled(labels.length, 0)];
    _interp.run(input.reshape([1, size, size, 3]), out);
    final probs = out[0];
    final idx = List<int>.generate(probs.length, (i) => i)..sort((a, b) => probs[b].compareTo(probs[a]));
    return [for (final i in idx.take(k)) Prediction(labels[i], probs[i])];
  }

  void close() => _interp.close();
}
