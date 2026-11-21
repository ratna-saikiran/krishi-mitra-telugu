// Severity: lesion area / leaf area. The pixel work (GrabCut leaf
// segmentation + HSV lesion test) runs natively with OpenCV in
// android/.../SeverityBridge.kt; ml/severity.py is the reference.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

const int kN = 256;
const double kMild = 0.10;
const double kModerate = 0.25;

class SeverityResult {
  final double lesionRatio; // lesion pixels / leaf pixels
  final double leafFraction; // leaf pixels / image pixels
  final String level; // none | mild | moderate | urgent
  final Uint8List overlayPng; // lesions red, background dimmed
  final double nativeMs;
  SeverityResult(this.lesionRatio, this.leafFraction, this.level, this.overlayPng, this.nativeMs);
  bool get leafFound => leafFraction >= 0.05;
}

String severityLevel(double ratio, {bool healthyClass = false, bool highRisk = false}) {
  if (healthyClass) return 'none';
  var lv = ratio < kMild ? 0 : (ratio < kModerate ? 1 : 2);
  if (highRisk) lv = math.min(2, lv + 1);
  return const ['mild', 'moderate', 'urgent'][lv];
}

const _ch = MethodChannel('krishi/severity');

Future<SeverityResult> estimateSeverity(img.Image src, {bool healthyClass = false, bool highRisk = false}) async {
  final sq = img.copyResizeCropSquare(src, size: kN, interpolation: img.Interpolation.average);
  final rgb = Uint8List(kN * kN * 3);
  var j = 0;
  for (final p in sq) {
    rgb[j++] = p.r.toInt();
    rgb[j++] = p.g.toInt();
    rgb[j++] = p.b.toInt();
  }
  final r = Map<String, dynamic>.from(
      (await _ch.invokeMethod<Map<dynamic, dynamic>>('analyze', {'rgb': rgb, 'n': kN}))!);
  if (r['error'] != null) throw Exception(r['error']);
  final ratio = (r['ratio'] as num).toDouble();
  final leafFrac = (r['leafFraction'] as num).toDouble();
  return SeverityResult(ratio, leafFrac, severityLevel(ratio, healthyClass: healthyClass, highRisk: highRisk),
      r['overlay'] as Uint8List, (r['ms'] as num).toDouble());
}
