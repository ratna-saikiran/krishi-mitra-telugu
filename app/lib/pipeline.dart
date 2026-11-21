// Sequential pipeline: decode -> classify crop + disease/pest (TFLite) ->
// severity (OpenCV, native) -> retrieve advisory -> Llama 3.2 1B (ExecuTorch).
// Stages never overlap, to keep peak RAM/CPU low on a phone.
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'advisory/advisory_db.dart';
import 'vision/classifier.dart';
import 'vision/severity.dart';

/// Thresholds, calibrated on held-out field images (see docs/technical_report.md).
const double kCropConfidence = 0.45; // below: "crop not recognised"
const double kDiseaseConfidence = 0.5; // below: show alternatives

class VisionResult {
  final List<Prediction> top; // within the chosen crop, best first
  final String? cropKey; // detected (or farmer-corrected) crop; null = not recognised
  final double cropScore;
  final bool cropCorrected;
  final SeverityResult severity;
  final AdvisoryEntry entry;
  final int decodeMs, classifyMs, severityMs;
  final double inferenceMs; // model invoke only, measured natively
  VisionResult(this.top, this.cropKey, this.cropScore, this.cropCorrected, this.severity, this.entry, this.decodeMs,
      this.classifyMs, this.severityMs, this.inferenceMs);
  Prediction get best => top.first;
  bool get unknownCrop => cropKey == null;
  bool get isPest => cropKey == 'Pest';
  bool get confident => !unknownCrop && best.score >= kDiseaseConfidence;
}

class Pipeline {
  final classifier = DiseaseClassifier();
  final db = AdvisoryDb();
  img.Image? _last; // last photo, kept so the farmer can correct the crop
  List<Prediction>? _lastAll;

  Future<void> init() async {
    await classifier.load();
    await db.load();
  }

  static String cropOf(String label) => label.split('___').first;

  /// Photo -> result. [forceCrop] re-runs the last photo restricted to a crop
  /// the farmer picked ('other' = a crop the model does not know).
  Future<VisionResult> runVision(Uint8List? bytes, {String? forceCrop}) async {
    final sw = Stopwatch()..start();
    var tDecode = 0, tCls = 0;
    if (bytes != null) {
      var image = img.decodeImage(bytes)!;
      image = img.bakeOrientation(image);
      if (image.width > 1024 || image.height > 1024) {
        image = image.width >= image.height ? img.copyResize(image, width: 1024) : img.copyResize(image, height: 1024);
      }
      _last = image;
      tDecode = sw.elapsedMilliseconds;
      sw.reset();
      _lastAll = await classifier.classify(image, k: classifier.labels.length);
      tCls = sw.elapsedMilliseconds;
    }
    final image = _last!;
    final all = _lastAll!;
    sw.reset();

    // Crop = class group with the highest summed probability.
    final cropP = <String, double>{};
    for (final p in all) {
      cropP[cropOf(p.label)] = (cropP[cropOf(p.label)] ?? 0) + p.score;
    }
    String? crop;
    double cropScore;
    if (forceCrop != null) {
      crop = forceCrop == 'other' ? null : forceCrop;
      cropScore = crop == null ? 0 : (cropP[crop] ?? 0);
    } else {
      final bestCrop = cropP.entries.reduce((a, b) => a.value >= b.value ? a : b);
      cropScore = bestCrop.value;
      crop = cropScore >= kCropConfidence ? bestCrop.key : null;
    }
    // Classes within the crop, renormalised (a crop with one class keeps its raw score).
    var top = <Prediction>[];
    if (crop != null) {
      final sub = all.where((p) => cropOf(p.label) == crop).toList();
      final z = sub.fold<double>(0, (a, p) => a + p.score);
      top = sub.length > 1 ? [for (final p in sub) Prediction(p.label, p.score / (z == 0 ? 1 : z))] : sub;
    } else {
      top = all.take(3).toList();
    }
    top = top.take(3).toList();
    final entry = db.entry(top.first.label);
    final pest = crop == 'Pest';
    final sev = await estimateSeverity(image,
        healthyClass: crop != null && entry.healthy, highRisk: crop != null && entry.highRisk);
    final tSev = sw.elapsedMilliseconds;
    // Lesion area means nothing on an insect photo: a detected pest needs
    // action now (urgent for outbreak-prone pests such as hoppers, locusts).
    final sevOut = pest
        ? SeverityResult(0, sev.leafFraction, entry.highRisk ? 'urgent' : 'moderate', sev.overlayPng, sev.nativeMs)
        : sev;
    return VisionResult(top, crop, cropScore, forceCrop != null, sevOut, entry, tDecode, tCls, tSev, classifier.lastInferenceMs);
  }
}
