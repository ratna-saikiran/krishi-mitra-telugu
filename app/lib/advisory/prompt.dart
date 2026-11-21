// Builds the Llama 3.2 Instruct prompt. Only structured text goes to the LLM
// (crop, disease, severity, lesion %, retrieved verified snippets): no image,
// which keeps the prompt short and the advice grounded.
import '../l10n.dart';
import 'advisory_db.dart';

String buildPrompt({
  required AdvisoryEntry e,
  required String level,
  required String levelTe,
  required double lesionPct,
  required double confidence,
  required List<String> verifiedSteps,
  Lang lang = Lang.te,
}) {
  final language = lang.llmLanguage;
  final script = lang == Lang.en ? '' : ' script';
  final system = 'You are a friendly agricultural extension officer in India. '
      'Reply ONLY in simple $language$script. Use ONLY the facts given. '
      'Never invent chemical names or doses; copy doses exactly as given. Keep it short.';
  // Fact labels in the farmer's language, so the model copies them in that language.
  final (crop, problem, sev, damaged, seen, cause, steps, prev) = switch (lang) {
    Lang.te => ('పంట', 'సమస్య', 'తీవ్రత', 'ఆకు దెబ్బతిన్న భాగం', 'పురుగు ఫోటోలో కనిపించింది', 'కారణం', 'ధృవీకరించిన చర్యలు', 'నివారణ'),
    Lang.hi => ('फसल', 'समस्या', 'गंभीरता', 'पत्ती का क्षतिग्रस्त भाग', 'फ़ोटो में कीट दिखा', 'कारण', 'सत्यापित कदम', 'रोकथाम'),
    Lang.en => ('Crop', 'Problem', 'Severity', 'damaged leaf area', 'pest seen in the photo', 'Cause', 'Verified steps', 'Prevention'),
  };
  final facts = StringBuffer()
    ..writeln('$crop: ${e.cropTe}${lang == Lang.en ? '' : ' (${e.cropEn})'}')
    ..writeln('$problem: ${e.diseaseTe}${lang == Lang.en ? '' : ' (${e.diseaseEn})'}')
    ..writeln(e.type == 'pest'
        ? '$sev: $levelTe ($level), $seen'
        : '$sev: $levelTe ($level), $damaged ${lesionPct.toStringAsFixed(0)}%')
    ..writeln('$cause: ${e.causeTe}')
    ..writeln('$steps:');
  for (final s in verifiedSteps) {
    facts.writeln('- $s');
  }
  facts.writeln('$prev: ${e.prevention.join(' ')}');
  final task = 'Using the facts above, write advice for the farmer in $language as 4 short bullet points: '
      '1) what the problem is, 2) what to do today, 3) the spray with exact dose (if any), 4) how to prevent it next time.';
  return '<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n$system<|eot_id|>'
      '<|start_header_id|>user<|end_header_id|>\n\n$facts\n$task<|eot_id|>'
      '<|start_header_id|>assistant<|end_header_id|>\n\n';
}

/// Guardrail: accept LLM output only if it is mostly in the farmer's language, not degenerate,
/// every number it mentions appears in the verified facts, and it does not
/// name a crop/disease/pest that is not in the facts ([otherNames] = every
/// problem/crop name in the advisory DB, in the same language). Host tests of Llama 3.2 1B
/// showed it can copy a wrong disease name from an example, which the number
/// check alone would miss.
String? validateAdvice(String out, String facts, {Iterable<String> otherNames = const [], Lang lang = Lang.te}) {
  var text = out.replaceAll(RegExp(r'<\|.*?\|>'), '').replaceAll('\uFFFD', '').trim();
  // Generation that hit the token limit ends mid-sentence: keep whole lines/sentences.
  final cut = text.lastIndexOf(RegExp(r'[.।\n]'));
  if (cut > 0 && cut < text.length - 1) text = text.substring(0, cut + 1).trim();
  if (text.length < 40) return null;
  final letters = text.runes.where((r) => String.fromCharCode(r).trim().isNotEmpty && !_isAsciiPunctOrDigit(r));
  final inScript = letters.where(lang.isScript).length;
  if (letters.isEmpty || inScript / letters.length < 0.6) return null;
  final body = text.replaceAll(RegExp(r'^\s*\d+[\).]', multiLine: true), '');
  for (final m in RegExp(r'\d+(\.\d+)?').allMatches(body)) {
    if (!facts.contains(m.group(0)!)) return null; // hallucinated dose / number
  }
  for (final n in otherNames) {
    if (n.length >= (lang == Lang.en ? 6 : 4) && text.contains(n) && !facts.contains(n)) return null; // wrong crop/disease name
  }
  // Repetition loops (common failure of small models): any sentence twice.
  final seen = <String>{};
  for (final raw in text.split(RegExp(r'[.।\n;]'))) {
    final t = raw.replaceAll(RegExp(r'^[\s\-•*\d\).]+'), '').trim();
    if (t.length < 10) continue;
    if (!seen.add(t)) return null;
  }
  return text;
}

bool _isAsciiPunctOrDigit(int r) => r < 0x80 && !RegExp(r'[A-Za-z]').hasMatch(String.fromCharCode(r));
