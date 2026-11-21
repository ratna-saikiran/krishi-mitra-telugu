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
  final SeverityResult severity;
  final AdvisoryEntry entry;
  final int decodeMs, classifyMs, severityMs;
  VisionResult(this.top, this.severity, this.entry, this.decodeMs, this.classifyMs, this.severityMs);
  Prediction get best => top.first;
  bool get confident => best.score >= 0.5;
}

class Pipeline {
  final classifier = DiseaseClassifier();
  final db = AdvisoryDb();

  Future<void> init() async {
    await classifier.load();
    await db.load();
  }

  VisionResult runVision(Uint8List bytes) {
    final sw = Stopwatch()..start();
    var image = img.decodeImage(bytes)!;
    image = img.bakeOrientation(image);
    // Phone photos are large; downscale once so later stages are cheap.
    if (image.width > 1024 || image.height > 1024) {
      image = image.width >= image.height ? img.copyResize(image, width: 1024) : img.copyResize(image, height: 1024);
    }
    final tDecode = sw.elapsedMilliseconds;
    sw.reset();
    final top = classifier.classify(image);
    final tCls = sw.elapsedMilliseconds;
    sw.reset();
    final entry = db.entry(top.first.label);
    final sev = estimateSeverity(img.copyResizeCropSquare(image, size: 512),
        healthyClass: entry.healthy, highRisk: entry.highRisk);
    final tSev = sw.elapsedMilliseconds;
    return VisionResult(top, sev, entry, tDecode, tCls, tSev);
  }
}
