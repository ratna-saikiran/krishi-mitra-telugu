import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:krishi_mitra/advisory/prompt.dart';
import 'package:krishi_mitra/vision/severity.dart';

void main() {
  test('Dart severity matches Python reference (ml/severity.py)', () {
    final exp = jsonDecode(File('test/fixtures/expected.json').readAsStringSync()) as Map<String, dynamic>;
    exp.forEach((name, want) {
      final im = img.decodeImage(File('test/fixtures/$name').readAsBytesSync())!;
      final r = estimateSeverity(im);
      // Resampling differs slightly between PIL and package:image.
      expect(r.lesionRatio, closeTo((want as num).toDouble(), 0.03), reason: name);
    });
  });

  test('severity levels and high-risk bump', () {
    expect(severityLevel(0.05), 'mild');
    expect(severityLevel(0.15), 'moderate');
    expect(severityLevel(0.40), 'urgent');
    expect(severityLevel(0.05, highRisk: true), 'moderate');
    expect(severityLevel(0.5, healthyClass: true), 'none');
  });

  test('LLM guardrail rejects invented doses and non-Telugu output', () {
    const facts = 'మాంకోజెబ్ 75% WP 2.5 గ్రా/లీటరు';
    expect(validateAdvice('1) ఇది ఆకు ఎండు తెగులు. 2) మాంకోజెబ్ 2.5 గ్రా/లీటరు నీటికి కలిపి ఈ రోజే పిచికారీ చేయండి.', facts), isNotNull);
    expect(validateAdvice('ఇది ఆకు ఎండు తెగులు. మాంకోజెబ్ 10 గ్రా/లీటరు నీటికి కలిపి ఈ రోజే పిచికారీ చేయండి.', facts), isNull);
    expect(validateAdvice('This is early blight. Spray mancozeb 2.5 g per litre of water today please.', facts), isNull);
  });
}
