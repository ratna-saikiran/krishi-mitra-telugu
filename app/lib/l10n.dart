// UI strings in Telugu, English and Hindi. The advisory content itself comes
// from assets/advisory_<lang>.json (built by ml/build_i18n.py).
enum Lang { te, en, hi }

extension LangInfo on Lang {
  String get code => name;
  String get native => const {Lang.te: 'తెలుగు', Lang.en: 'English', Lang.hi: 'हिन्दी'}[this]!;
  String get ttsLocale => const {Lang.te: 'te-IN', Lang.en: 'en-IN', Lang.hi: 'hi-IN'}[this]!;
  String get llmLanguage => const {Lang.te: 'Telugu', Lang.en: 'English', Lang.hi: 'Hindi'}[this]!;

  /// Unicode block the advice must be written in (LLM guardrail).
  bool isScript(int r) => switch (this) {
        Lang.te => r >= 0x0C00 && r <= 0x0C7F,
        Lang.hi => r >= 0x0900 && r <= 0x097F,
        Lang.en => (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A),
      };

  static Lang parse(String? s) => Lang.values.firstWhere((l) => l.name == s, orElse: () => Lang.te);
}

class L {
  final Lang lang;
  const L(this.lang);

  String _t(String te, String en, String hi) => switch (lang) { Lang.te => te, Lang.en => en, Lang.hi => hi };

  String get appTitle => _t('కృషి మిత్ర · పంట వైద్యుడు', 'Krishi Mitra · Crop Doctor', 'कृषि मित्र · फसल डॉक्टर');
  String get chooseLanguage => 'భాష ఎంచుకోండి · Choose language · भाषा चुनें';
  String get changeLanguage => _t('భాష మార్చండి', 'Change language', 'भाषा बदलें');
  String get importLlama => _t('Llama మోడల్ దిగుమతి', 'Import Llama model', 'Llama मॉडल लाएँ');
  String llamaReady(String n) => _t('Llama సిద్ధం: $n', 'Llama ready: $n', 'Llama तैयार: $n');
  String get pickTwoFiles => _t('రెండు ఫైళ్లు ఎంచుకోండి: .pte మోడల్ మరియు tokenizer.model',
      'Pick both files: the .pte model and tokenizer.model', 'दोनों फ़ाइलें चुनें: .pte मॉडल और tokenizer.model');
  String get offline => _t('ఆఫ్‌లైన్', 'Offline', 'ऑफ़लाइन');
  String get takePhoto => _t('ఫోటో తీయండి', 'Take photo', 'फ़ोटो लें');
  String get gallery => _t('గ్యాలరీ', 'Gallery', 'गैलरी');
  String get photoHint => _t(
      'ఆకు లేదా పురుగును మధ్యలో, దగ్గరగా, వెలుతురులో ఫోటో తీయండి. పంట, వ్యాధి, పురుగు ఆటోమేటిక్‌గా గుర్తిస్తాం.',
      'Photograph the leaf or insect up close, in the centre, in good light. The crop, disease and pest are detected automatically.',
      'पत्ती या कीट को बीच में, पास से, अच्छी रोशनी में फ़ोटो लें। फसल, रोग और कीट अपने-आप पहचाने जाते हैं।');
  String get pickCrop => _t('సరైన పంటను ఎంచుకోండి', 'Choose the correct crop', 'सही फसल चुनें');
  String get pest => _t('పురుగు', 'Insect pest', 'कीट');
  String get otherCrop => _t('ఇతర పంట (జాబితాలో లేదు)', 'Other crop (not in list)', 'अन्य फसल (सूची में नहीं)');
  String get correctCrop => _t('పంట సరిచేయండి', 'Correct the crop', 'फसल सुधारें');
  String unknownAdvice(String pct) => _t('ఈ పంటను / సమస్యను ఖచ్చితంగా గుర్తించలేకపోయాం. ఆకు దెబ్బతిన్న భాగం: $pct%.',
      'We could not identify this crop / problem with confidence. Damaged leaf area: $pct%.',
      'इस फसल / समस्या की पक्की पहचान नहीं हो सकी। पत्ती का क्षतिग्रस्त भाग: $pct%।');
  String get showAtCentre => _t('దగ్గరలోని రైతు భరోసా కేంద్రంలో ఈ ఫోటో చూపించండి.',
      'Show this photo at your nearest agriculture centre.', 'यह फ़ोटो पास के कृषि सेवा केंद्र में दिखाएँ।');
  String get llamaLoading => _t('Llama 3.2 1B లోడ్ అవుతోంది…', 'Loading Llama 3.2 1B…', 'Llama 3.2 1B लोड हो रहा है…');
  String get llamaWriting =>
      _t('Llama 3.2 1B (ExecuTorch, INT4) రాస్తోంది…', 'Llama 3.2 1B (ExecuTorch, INT4) is writing…', 'Llama 3.2 1B (ExecuTorch, INT4) लिख रहा है…');
  String get llmRejected => _t(' · AI జవాబు ధృవీకరణలో విఫలమైంది, ధృవీకరించిన సలహా చూపుతున్నాం',
      ' · AI answer failed the check, showing verified advice', ' · AI उत्तर जाँच में विफल, सत्यापित सलाह दिखा रहे हैं');
  String get rightAnalysed => _t('కుడి: విశ్లేషించిన భాగం', 'Right: analysed area', 'दाएँ: विश्लेषित भाग');
  String get rightRed => _t('కుడి: ఎరుపు = దెబ్బతిన్న భాగం', 'Right: red = damaged area', 'दाएँ: लाल = क्षतिग्रस्त भाग');
  String get cropUnsure => _t('పంటను ఖచ్చితంగా గుర్తించలేకపోయాం. ఒకే ఆకును దగ్గరగా మళ్ళీ ఫోటో తీయండి, లేదా క్రింద "పంట సరిచేయండి" నొక్కండి.',
      'Could not identify the crop with confidence. Take a close photo of a single leaf again, or tap "Correct the crop" below.',
      'फसल की पक्की पहचान नहीं हो सकी। एक पत्ती की पास से फिर फ़ोटो लें, या नीचे "फसल सुधारें" दबाएँ।');
  String get diseaseUnsure => _t('ఖచ్చితంగా గుర్తించలేకపోయాం. ఒకే ఆకును దగ్గరగా, నీడ లేకుండా మళ్ళీ ఫోటో తీయండి. క్రింది ఫలితం అంచనా మాత్రమే.',
      'Not sure. Take a close photo of a single leaf again, without shadow. The result below is only an estimate.',
      'पक्का नहीं है। एक पत्ती की पास से, बिना छाया के फिर फ़ोटो लें। नीचे का परिणाम केवल अनुमान है।');
  String get cropNotRecognised => _t('పంట: గుర్తించలేదు', 'Crop: not recognised', 'फसल: पहचानी नहीं गई');
  String get cropMaybeMissing => _t('ఈ పంట మా జాబితాలో లేకపోవచ్చు. దెబ్బతిన్న భాగం మాత్రమే కొలిచాం.',
      'This crop may not be in our list. Only the damaged area was measured.', 'यह फसल हमारी सूची में नहीं हो सकती। केवल क्षतिग्रस्त भाग मापा गया।');
  String pestLine(String n) => _t('పురుగు: $n', 'Pest: $n', 'कीट: $n');
  String cropLine(String c, bool corrected) =>
      _t('పంట: $c${corrected ? ' (మీరు ఎంచుకున్నది)' : ''}', 'Crop: $c${corrected ? ' (your choice)' : ''}', 'फसल: $c${corrected ? ' (आपका चुनाव)' : ''}');
  String problemLine(String p) => _t('సమస్య: $p', 'Problem: $p', 'समस्या: $p');
  String severity(String s) => _t('తీవ్రత: $s', 'Severity: $s', 'गंभीरता: $s');
  String cropConfidence(String p) => _t('పంట నమ్మకం $p%', 'Crop confidence $p%', 'फसल विश्वास $p%');
  String confidence(String p) => _t('నమ్మకం $p%', 'Confidence $p%', 'विश्वास $p%');
  String damaged(String p) => _t('దెబ్బతిన్న భాగం $p%', 'Damaged $p%', 'क्षति $p%');
  String get otherPossibilities => _t('ఇతర అవకాశాలు', 'Other possibilities', 'अन्य संभावनाएँ');
  String get symptoms => _t('లక్షణాలు', 'Symptoms', 'लक्षण');
  String get cause => _t('కారణం', 'Cause', 'कारण');
  String get prevention => _t('నివారణ', 'Prevention', 'रोकथाम');
  String get healthyLevel => _t('ఆరోగ్యకరం', 'Healthy', 'स्वस्थ');
  String healthyLeaf(String crop) => _t('మీ $crop ఆకు ఆరోగ్యంగా ఉంది.', 'Your $crop leaf is healthy.', 'आपकी $crop की पत्ती स्वस्थ है।');
  String get aiAdvice => _t('AI సలహా (Llama 3.2, ఆఫ్‌లైన్)', 'AI advice (Llama 3.2, offline)', 'AI सलाह (Llama 3.2, ऑफ़लाइन)');
  String get verifiedAdvice => _t('సలహా (ధృవీకరించిన సమాచారం)', 'Advice (verified information)', 'सलाह (सत्यापित जानकारी)');
  String get listen => _t('వినండి', 'Listen', 'सुनें');
  String get verifiedSteps => _t('ధృవీకరించిన చర్యలు (మూలం)', 'Verified steps (source)', 'सत्यापित कदम (स्रोत)');
  String get fertiliserTitle =>
      _t('ఎరువులు, నీటి యాజమాన్యం, కోత తర్వాత', 'Fertiliser, irrigation, after harvest', 'खाद, सिंचाई, कटाई के बाद');
  String get source => _t('మూలం', 'Source', 'स्रोत');
  String get sprayTitle => _t('మందు & మోతాదు', 'Product & dose', 'दवा और मात्रा');
  String get liquid => _t('ద్రవం', 'Liquid', 'तरल');
  String get powder => _t('పొడి', 'Powder', 'पाउडर');
  String perLitre(String d) => _t('1 లీటరు నీటికి: $d', 'Per 1 litre of water: $d', '1 लीटर पानी में: $d');
  String get howToSpray => _t('ఎలా పిచికారీ చేయాలి', 'How to spray', 'छिड़काव कैसे करें');
  String get gram => _t('గ్రా', 'g', 'ग्राम');
  String get ml => _t('మి.లీ', 'ml', 'मि.ली.');
  String timing(String sev, int dec, int cls, String model, int sevMs) => _t(
      'సమయం: severity (OpenCV) ${sev}ms · decode ${dec}ms · వ్యాధి గుర్తింపు ${cls}ms (model ${model}ms, INT8) · తీవ్రత ${sevMs}ms',
      'Time: severity (OpenCV) ${sev}ms · decode ${dec}ms · detection ${cls}ms (model ${model}ms, INT8) · severity ${sevMs}ms',
      'समय: severity (OpenCV) ${sev}ms · decode ${dec}ms · पहचान ${cls}ms (model ${model}ms, INT8) · गंभीरता ${sevMs}ms');
}
