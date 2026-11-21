// Sequential pipeline: decode -> classify (TFLite INT8) -> severity (HSV
// lesion ratio) -> retrieve advisory -> Llama 3.2 1B (ExecuTorch). Stages
// never overlap, to keep peak RAM/CPU low on a phone.
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'advisory/advisory_db.dart';
import 'vision/classifier.dart';
import 'vision/severity.dart';

class VisionResult {
  final List<Prediction> top;
  final String? cropKey; // crop the farmer picked (null = automatic)
  final bool unsupportedCrop; // farmer picked "other crop"
  final SeverityResult severity;
  final AdvisoryEntry entry;
  final int decodeMs, classifyMs, severityMs;
  final double inferenceMs; // model invoke only, measured natively
  VisionResult(this.top, this.severity, this.entry, this.decodeMs, this.classifyMs, this.severityMs, this.inferenceMs,
      {this.cropKey, this.unsupportedCrop = false});
  Prediction get best => top.first;
  /// Calibrated on PlantDoc field images: below this the top-1 is often wrong.
  bool get confident => !unsupportedCrop && best.score >= 0.6;
}

class Pipeline {
  final classifier = DiseaseClassifier();
  final db = AdvisoryDb();

  Future<void> init() async {
    await classifier.load();
    await db.load();
  }

  /// [cropKey]: crop chosen by the farmer (restricts the classes), 'other'
  /// for a crop the model does not know, or null for automatic.
  Future<VisionResult> runVision(Uint8List bytes, {String? cropKey}) async {
    final sw = Stopwatch()..start();
    var image = img.decodeImage(bytes)!;
    image = img.bakeOrientation(image);
    // Phone photos are large; downscale once so later stages are cheap.
    if (image.width > 1024 || image.height > 1024) {
      image = image.width >= image.height ? img.copyResize(image, width: 1024) : img.copyResize(image, height: 1024);
    }
    final tDecode = sw.elapsedMilliseconds;
    sw.reset();
    var top = await classifier.classify(image, k: classifier.labels.length);
    if (cropKey != null && cropKey != 'other') {
      // Restrict to the chosen crop and renormalise.
      final allowed = db.crops.firstWhere((c) => c.key == cropKey).labels.toSet();
      final sub = top.where((p) => allowed.contains(p.label)).toList();
      final z = sub.fold<double>(0, (a, p) => a + p.score);
      // A crop with a single (disease) class can't be "renormalised" into
      // certainty: keep its raw probability.
      top = allowed.length > 1 ? [for (final p in sub) Prediction(p.label, p.score / (z == 0 ? 1 : z))] : sub;
    }
    top = top.take(3).toList();
    final tCls = sw.elapsedMilliseconds;
    sw.reset();
    final entry = db.entry(top.first.label);
    final sev = await estimateSeverity(image,
        healthyClass: entry.healthy && cropKey != 'other', highRisk: entry.highRisk && cropKey != 'other');
    final tSev = sw.elapsedMilliseconds;
    return VisionResult(top, sev, entry, tDecode, tCls, tSev, classifier.lastInferenceMs,
        cropKey: cropKey, unsupportedCrop: cropKey == 'other');
  }
}
