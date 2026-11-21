import 'package:flutter_test/flutter_test.dart';
import 'package:krishi_mitra/advisory/advisory_db.dart';
import 'package:krishi_mitra/advisory/prompt.dart';
import 'package:krishi_mitra/vision/severity.dart';

void main() {
  test('spray dose scales to tank sizes', () {
    final sp = Spray({'name_te': 'x', 'name_en': 'x', 'dose_per_l': 2.5, 'unit': 'g', 'kind': 'fungicide', 'form': 'powder'});
    expect(sp.doseFor(15), '37.5 గ్రా');
    expect(sp.doseFor(200), '500 గ్రా');
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
    // Wrong disease name copied from elsewhere is rejected.
    expect(
        validateAdvice('వరి పంటకు ఆలస్య ఆకు ఎండు తెగులు సోకింది. ఈ రోజే మాంకోజెబ్ 2.5 గ్రా/లీటరు పిచికారీ చేయండి.', facts,
            otherNames: ['ఆలస్య ఆకు ఎండు తెగులు', 'అగ్గి తెగులు']),
        isNull);
    // Repeated sentence loop is rejected.
    expect(validateAdvice('1) పంట మార్పిడి మరియు పంట అవశేషాల నాశనం.\n2) పంట మార్పిడి మరియు పంట అవశేషాల నాశనం.\n3) మంచిది చేయండి.', facts), isNull);
    expect(validateAdvice('This is early blight. Spray mancozeb 2.5 g per litre of water today please.', facts), isNull);
  });
}
