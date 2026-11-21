// Lesion-area-ratio severity estimator. Line-by-line port of ml/severity.py;
// keep both in sync. Pure Dart, no OpenCV, ~256x256 work image.
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const int kN = 256;
const double kMild = 0.10;
const double kModerate = 0.25;

class SeverityResult {
  final double lesionRatio; // lesion pixels / leaf pixels
  final double leafFraction; // leaf pixels / image pixels
  final String level; // none | mild | moderate | urgent
  final Uint8List overlayPng; // lesions tinted red, for the result screen
  SeverityResult(this.lesionRatio, this.leafFraction, this.level, this.overlayPng);
  bool get leafFound => leafFraction >= 0.05;
}

String severityLevel(double ratio, {bool healthyClass = false, bool highRisk = false}) {
  if (healthyClass) return 'none';
  var lv = ratio < kMild ? 0 : (ratio < kModerate ? 1 : 2);
  if (highRisk) lv = math.min(2, lv + 1);
  return const ['mild', 'moderate', 'urgent'][lv];
}

SeverityResult estimateSeverity(img.Image src, {bool healthyClass = false, bool highRisk = false}) {
  final im = img.copyResize(src, width: kN, height: kN, interpolation: img.Interpolation.linear);
  final h = Float32List(kN * kN), s = Float32List(kN * kN), v = Float32List(kN * kN);
  for (var y = 0; y < kN; y++) {
    for (var x = 0; x < kN; x++) {
      final p = im.getPixel(x, y);
      final r = p.r / 255.0, g = p.g / 255.0, b = p.b / 255.0;
      final mx = math.max(r, math.max(g, b)), mn = math.min(r, math.min(g, b));
      final d = mx - mn;
      double hh = 0;
      if (d > 1e-6) {
        if (mx == r) {
          hh = (60 * ((g - b) / d)) % 360;
        } else if (mx == g) {
          hh = 60 * ((b - r) / d) + 120;
        } else {
          hh = 60 * ((r - g) / d) + 240;
        }
      }
      final i = y * kN + x;
      h[i] = hh;
      s[i] = mx > 0 ? d / mx : 0;
      v[i] = mx;
    }
  }
  final plant = Uint8List(kN * kN);
  for (var i = 0; i < kN * kN; i++) {
    plant[i] = (s[i] > 0.15 && v[i] > 0.12 && h[i] >= 15 && h[i] <= 170) ? 1 : 0;
  }
  final leaf = _fillHoles(_largestComponent(plant));
  var nLeaf = 0, nLesion = 0;
  final lesion = Uint8List(kN * kN);
  for (var i = 0; i < kN * kN; i++) {
    if (leaf[i] == 0) continue;
    nLeaf++;
    final healthy = h[i] >= 65 && h[i] <= 175 && s[i] > 0.10 && v[i] > 0.10;
    if (!healthy) {
      lesion[i] = 1;
      nLesion++;
    }
  }
  final leafFrac = nLeaf / (kN * kN);
  final ratio = leafFrac < 0.05 ? 0.0 : nLesion / nLeaf;

  // Overlay: dim background, tint lesions red.
  final out = img.Image.from(im);
  for (var y = 0; y < kN; y++) {
    for (var x = 0; x < kN; x++) {
      final i = y * kN + x;
      final p = out.getPixel(x, y);
      if (leaf[i] == 0) {
        p..r = p.r * 0.35..g = p.g * 0.35..b = p.b * 0.35;
      } else if (lesion[i] == 1) {
        p..r = 255..g = p.g * 0.3..b = p.b * 0.3;
      }
    }
  }
  return SeverityResult(ratio, leafFrac,
      severityLevel(ratio, healthyClass: healthyClass, highRisk: highRisk),
      Uint8List.fromList(img.encodePng(out)));
}

Uint8List _largestComponent(Uint8List mask) {
  final lab = Int32List(kN * kN);
  var cur = 0, best = 0, bestN = 0;
  final q = Queue<int>();
  for (var start = 0; start < kN * kN; start++) {
    if (mask[start] == 0 || lab[start] != 0) continue;
    cur++;
    lab[start] = cur;
    q.add(start);
    var n = 0;
    while (q.isNotEmpty) {
      final c = q.removeFirst();
      n++;
      final cy = c ~/ kN, cx = c % kN;
      for (final nb in [
        if (cy + 1 < kN) c + kN,
        if (cy > 0) c - kN,
        if (cx + 1 < kN) c + 1,
        if (cx > 0) c - 1,
      ]) {
        if (mask[nb] == 1 && lab[nb] == 0) {
          lab[nb] = cur;
          q.add(nb);
        }
      }
    }
    if (n > bestN) {
      bestN = n;
      best = cur;
    }
  }
  final out = Uint8List(kN * kN);
  for (var i = 0; i < kN * kN; i++) {
    out[i] = (best != 0 && lab[i] == best) ? 1 : 0;
  }
  return out;
}

Uint8List _fillHoles(Uint8List mask) {
  final outside = Uint8List(kN * kN);
  final q = Queue<int>();
  void seed(int i) {
    if (mask[i] == 0 && outside[i] == 0) {
      outside[i] = 1;
      q.add(i);
    }
  }

  for (var i = 0; i < kN; i++) {
    seed(i);
    seed((kN - 1) * kN + i);
    seed(i * kN);
    seed(i * kN + kN - 1);
  }
  while (q.isNotEmpty) {
    final c = q.removeFirst();
    final cy = c ~/ kN, cx = c % kN;
    if (cy + 1 < kN) seed(c + kN);
    if (cy > 0) seed(c - kN);
    if (cx + 1 < kN) seed(c + 1);
    if (cx > 0) seed(c - 1);
  }
  final out = Uint8List(kN * kN);
  for (var i = 0; i < kN * kN; i++) {
    out[i] = outside[i] == 1 ? 0 : 1;
  }
  return out;
}
