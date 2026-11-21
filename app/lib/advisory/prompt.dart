// Builds the Llama 3.2 Instruct prompt. Only structured text goes to the LLM
// (crop, disease, severity, lesion %, retrieved verified snippets): no image,
// which keeps the prompt short and the advice grounded.
import 'advisory_db.dart';

String buildPrompt({
  required AdvisoryEntry e,
  required String level,
  required String levelTe,
  required double lesionPct,
  required double confidence,
  required List<String> verifiedSteps,
}) {
  const system = 'You are a friendly agricultural extension officer in Andhra Pradesh and Telangana. '
      'Reply ONLY in simple Telugu script. Use ONLY the facts given. '
      'Never invent chemical names or doses; copy doses exactly as given. Keep it short.';
  final facts = StringBuffer()
    ..writeln('పంట: ${e.cropTe} (${e.cropEn})')
    ..writeln('సమస్య: ${e.diseaseTe} (${e.diseaseEn})')
    ..writeln(e.type == 'pest'
        ? 'తీవ్రత: $levelTe ($level), పురుగు ఫోటోలో కనిపించింది'
        : 'తీవ్రత: $levelTe ($level), ఆకు దెబ్బతిన్న భాగం ${lesionPct.toStringAsFixed(0)}%')
    ..writeln('కారణం: ${e.causeTe}')
    ..writeln('ధృవీకరించిన చర్యలు:');
  for (final s in verifiedSteps) {
    facts.writeln('- $s');
  }
  facts.writeln('నివారణ: ${e.prevention.join(' ')}');
  const task = 'Using the facts above, write advice for the farmer in Telugu as 4 short bullet points: '
      '1) what the problem is, 2) what to do today, 3) the spray with exact dose (if any), 4) how to prevent it next time.';
  return '<|begin_of_text|><|start_header_id|>system<|end_header_id|>\n\n$system<|eot_id|>'
      '<|start_header_id|>user<|end_header_id|>\n\n$facts\n$task<|eot_id|>'
      '<|start_header_id|>assistant<|end_header_id|>\n\n';
}

/// Guardrail: accept LLM output only if it is mostly Telugu, not degenerate,
/// and every number it mentions appears in the verified facts.
String? validateAdvice(String out, String facts) {
  final text = out.replaceAll(RegExp(r'<\|.*?\|>'), '').trim();
  if (text.length < 40) return null;
  final letters = text.runes.where((r) => String.fromCharCode(r).trim().isNotEmpty && !_isAsciiPunctOrDigit(r));
  final telugu = letters.where((r) => r >= 0x0C00 && r <= 0x0C7F).length;
  if (letters.isEmpty || telugu / letters.length < 0.6) return null;
  final body = text.replaceAll(RegExp(r'^\s*\d+[\).]', multiLine: true), '');
  for (final m in RegExp(r'\d+(\.\d+)?').allMatches(body)) {
    if (!facts.contains(m.group(0)!)) return null; // hallucinated dose / number
  }
  // Repetition loop check (common failure of small models).
  final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.length > 3 && lines.toSet().length < lines.length / 2) return null;
  return text;
}

bool _isAsciiPunctOrDigit(int r) => r < 0x80 && !RegExp(r'[A-Za-z]').hasMatch(String.fromCharCode(r));
