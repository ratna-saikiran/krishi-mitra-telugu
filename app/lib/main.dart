// కృషి మిత్ర (Krishi Mitra): fully offline crop disease/pest advisor in Telugu.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';

import 'advisory/advisory_db.dart';
import 'advisory/llm_service.dart';
import 'advisory/prompt.dart';
import 'pipeline.dart';
import 'vision/severity.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const KrishiApp());
}

class KrishiApp extends StatelessWidget {
  const KrishiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'కృషి మిత్ర',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: const Color(0xFF2E7D32), useMaterial3: true),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

const _sevColor = {
  'none': Color(0xFF2E7D32),
  'mild': Color(0xFFF9A825),
  'moderate': Color(0xFFEF6C00),
  'urgent': Color(0xFFC62828),
};

class _HomePageState extends State<HomePage> {
  final _pipeline = Pipeline();
  final _llm = LlmService();
  final _tts = FlutterTts();
  bool _ready = false, _busy = false, _llmAvailable = false, _generating = false;
  Uint8List? _photo;
  VisionResult? _vr;
  String _advice = '';
  String? _adviceSource; // 'llm' | 'template'
  String _llmInfo = '';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _pipeline.init();
    try {
      _llmAvailable = await _llm.available();
    } catch (_) {
      _llmAvailable = false;
    }
    await _tts.setLanguage('te-IN');
    setState(() => _ready = true);
  }

  Future<void> _importModel() async {
    final names = await _llm.importModel();
    final ok = await _llm.available();
    if (!mounted) return;
    setState(() => _llmAvailable = ok);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(ok
            ? 'Llama సిద్ధం: ${names.join(', ')}'
            : 'రెండు ఫైళ్లు ఎంచుకోండి: .pte మోడల్ మరియు tokenizer.model')));
  }

  Future<void> _pick(ImageSource src) async {
    final x = await ImagePicker().pickImage(source: src, maxWidth: 1600, imageQuality: 92);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() {
      _busy = true;
      _photo = bytes;
      _vr = null;
      _advice = '';
      _adviceSource = null;
      _llmInfo = '';
    });
    await Future<void>.delayed(const Duration(milliseconds: 50)); // let spinner paint
    final vr = await _pipeline.runVision(bytes); // stage 1+2 (vision), sequential
    setState(() {
      _vr = vr;
      _busy = false;
    });
    await _advise(vr); // stage 3 (advisory) only after vision is done
  }

  /// Optional correction: farmer picks the crop, same photo is re-analysed.
  Future<void> _correctCrop() async {
    final crops = _pipeline.db.crops.where((c) => c.key != 'Pest').toList();
    final pick = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('సరైన పంటను ఎంచుకోండి', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in crops) ActionChip(label: Text(c.te), onPressed: () => Navigator.pop(ctx, c.key)),
              ActionChip(label: const Text('పురుగు'), onPressed: () => Navigator.pop(ctx, 'Pest')),
              ActionChip(label: const Text('ఇతర పంట (జాబితాలో లేదు)'), onPressed: () => Navigator.pop(ctx, 'other')),
            ]),
          ]),
        ),
      ),
    );
    if (pick == null) return;
    setState(() {
      _busy = true;
      _advice = '';
      _adviceSource = null;
      _llmInfo = '';
    });
    final vr = await _pipeline.runVision(null, forceCrop: pick);
    setState(() {
      _vr = vr;
      _busy = false;
    });
    await _advise(vr);
  }

  Future<void> _advise(VisionResult vr) async {
    final db = _pipeline.db;
    final e = vr.entry;
    final level = vr.severity.level;
    final template = db.templateAdvice(e, level);
    if (vr.unknownCrop) {
      setState(() {
        _advice = [
          'ఈ పంటను / సమస్యను ఖచ్చితంగా గుర్తించలేకపోయాం. ఆకు దెబ్బతిన్న భాగం: ${(vr.severity.lesionRatio * 100).toStringAsFixed(0)}%.',
          ...db.genericSteps(severityLevel(vr.severity.lesionRatio)),
          'దగ్గరలోని రైతు భరోసా కేంద్రంలో ఈ ఫోటో చూపించండి.',
        ].map((s) => '• $s').join('\n');
        _adviceSource = 'template';
      });
      return;
    }
    if (!_llmAvailable || e.healthy || !vr.confident) {
      setState(() {
        _advice = template.map((s) => '• $s').join('\n');
        _adviceSource = 'template';
      });
      return;
    }
    final verified = [...db.genericSteps(level), ...e.stepsFor(level)];
    final prompt = buildPrompt(
        e: e,
        level: level,
        levelTe: db.severityTe(level),
        lesionPct: vr.severity.lesionRatio * 100,
        confidence: vr.best.score,
        verifiedSteps: verified);
    setState(() {
      _generating = true;
      _adviceSource = 'llm';
      _llmInfo = 'Llama 3.2 1B లోడ్ అవుతోంది…';
    });
    try {
      var loadMs = 0;
      if (!_llm.loaded) loadMs = await _llm.load();
      final sw = Stopwatch()..start();
      int? firstTokMs;
      var n = 0;
      final buf = StringBuffer();
      await for (final t in _llm.generate(prompt, seqLen: 1900)) {
        firstTokMs ??= sw.elapsedMilliseconds;
        n++;
        buf.write(t);
        setState(() {
          _advice = buf.toString();
          _llmInfo = 'Llama 3.2 1B (ExecuTorch, INT4) రాస్తోంది…';
        });
      }
      final total = sw.elapsedMilliseconds;
      final ok = validateAdvice(buf.toString(), prompt, otherNames: db.allNamesTe);
      setState(() {
        _generating = false;
        final tps = n / ((total - (firstTokMs ?? 0)) / 1000).clamp(0.001, 1e9);
        _llmInfo = 'LLM: ${loadMs > 0 ? 'load ${loadMs}ms, ' : ''}first token ${firstTokMs ?? 0}ms, '
            '$n tokens, ${tps.toStringAsFixed(1)} tok/s';
        if (ok != null) {
          _advice = ok;
        } else {
          _advice = template.map((s) => '• $s').join('\n');
          _adviceSource = 'template';
          _llmInfo += ' · AI జవాబు ధృవీకరణలో విఫలమైంది, ధృవీకరించిన సలహా చూపుతున్నాం';
        }
      });
    } catch (err) {
      setState(() {
        _generating = false;
        _advice = template.map((s) => '• $s').join('\n');
        _adviceSource = 'template';
        _llmInfo = 'LLM error: $err';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('కృషి మిత్ర · పంట వైద్యుడు'),
        actions: [
          IconButton(
            tooltip: 'Llama మోడల్ దిగుమతి',
            icon: const Icon(Icons.download_for_offline),
            onPressed: _busy || _generating ? null : _importModel,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Chip(
              avatar: const Icon(Icons.wifi_off, size: 16),
              label: Text(_llmAvailable ? 'ఆఫ్‌లైన్ · Llama' : 'ఆఫ్‌లైన్'),
            ),
          ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy || _generating ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera),
                    label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 14), child: Text('ఫోటో తీయండి', style: TextStyle(fontSize: 18))),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _busy || _generating ? null : () => _pick(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('గ్యాలరీ')),
                ),
              ]),
              const SizedBox(height: 8),
              const Text('ఆకు లేదా పురుగును మధ్యలో, దగ్గరగా, వెలుతురులో ఫోటో తీయండి. పంట, వ్యాధి, పురుగు ఆటోమేటిక్‌గా గుర్తిస్తాం.', style: TextStyle(color: Colors.black54)),
              if (_busy) const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator())),
              if (_vr != null) ..._result(_vr!),
            ]),
    );
  }

  List<Widget> _result(VisionResult vr) {
    final db = _pipeline.db;
    final e = vr.entry;
    final sev = vr.severity;
    final color = _sevColor[sev.level]!;
    return [
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(_photo!, height: 160, fit: BoxFit.cover))),
        const SizedBox(width: 8),
        Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.memory(sev.overlayPng, height: 160, fit: BoxFit.cover))),
      ]),
      const SizedBox(height: 4),
      Text(vr.isPest ? 'కుడి: విశ్లేషించిన భాగం' : 'కుడి: ఎరుపు = దెబ్బతిన్న భాగం', style: const TextStyle(fontSize: 12, color: Colors.black54)),
      const SizedBox(height: 12),
      if (vr.unknownCrop || !vr.confident)
        Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(vr.unknownCrop
                ? 'పంటను ఖచ్చితంగా గుర్తించలేకపోయాం. ఒకే ఆకును దగ్గరగా మళ్ళీ ఫోటో తీయండి, లేదా క్రింద "పంట సరిచేయండి" నొక్కండి.'
                : 'ఖచ్చితంగా గుర్తించలేకపోయాం. ఒకే ఆకును దగ్గరగా, నీడ లేకుండా మళ్ళీ ఫోటో తీయండి. క్రింది ఫలితం అంచనా మాత్రమే.'),
          ),
        ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (vr.unknownCrop) ...[
              Text('పంట: గుర్తించలేదు', style: Theme.of(context).textTheme.titleLarge),
              const Text('ఈ పంట మా జాబితాలో లేకపోవచ్చు. దెబ్బతిన్న భాగం మాత్రమే కొలిచాం.'),
            ] else if (vr.isPest) ...[
              Text('పురుగు: ${e.diseaseTe}', style: Theme.of(context).textTheme.titleLarge),
              Text('Pest · ${e.diseaseEn}', style: const TextStyle(color: Colors.black54)),
            ] else ...[
              Text('పంట: ${e.cropTe}${vr.cropCorrected ? ' (మీరు ఎంచుకున్నది)' : ''}', style: Theme.of(context).textTheme.titleLarge),
              Text('సమస్య: ${e.diseaseTe}', style: Theme.of(context).textTheme.titleMedium),
              Text('${e.cropEn} · ${e.diseaseEn} · ${e.type}', style: const TextStyle(color: Colors.black54)),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              Chip(
                backgroundColor: color.withValues(alpha: 0.15),
                side: BorderSide(color: color),
                label: Text('తీవ్రత: ${db.severityTe(sev.level)}', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
              ),
              if (!vr.unknownCrop && !vr.cropCorrected) Chip(label: Text('పంట నమ్మకం ${(vr.cropScore * 100).toStringAsFixed(0)}%')),
              if (!vr.unknownCrop) Chip(label: Text('నమ్మకం ${(vr.best.score * 100).toStringAsFixed(0)}%')),
              if (!vr.isPest && (!e.healthy || vr.unknownCrop)) Chip(label: Text('దెబ్బతిన్న భాగం ${(sev.lesionRatio * 100).toStringAsFixed(0)}%')),
            ]),
            if (!vr.confident && !vr.unknownCrop && vr.top.length > 1)
              Text('ఇతర అవకాశాలు: ${vr.top.skip(1).map((p) => '${db.entry(p.label).diseaseTe} ${(p.score * 100).toStringAsFixed(0)}%').join(', ')}',
                  style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 6),
            if (!vr.unknownCrop && e.symptomsTe.isNotEmpty) Text('లక్షణాలు: ${e.symptomsTe}'),
            if (!vr.unknownCrop && e.symptomsTe.isEmpty && !e.healthy) Text('కారణం: ${e.causeTe}'),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy || _generating ? null : _correctCrop,
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('పంట సరిచేయండి'),
              ),
            ),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(_adviceSource == 'llm' ? Icons.auto_awesome : Icons.verified, color: Colors.green.shade800),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_adviceSource == 'llm' ? 'AI సలహా (Llama 3.2, ఆఫ్‌లైన్)' : 'సలహా (ధృవీకరించిన సమాచారం)',
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                tooltip: 'వినండి',
                onPressed: _advice.isEmpty ? null : () => _tts.speak(_advice.replaceAll('•', '')),
                icon: const Icon(Icons.volume_up),
              ),
            ]),
            if (_generating) const LinearProgressIndicator(),
            const SizedBox(height: 6),
            Text(_advice, style: const TextStyle(fontSize: 16, height: 1.5)),
            if (_llmInfo.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_llmInfo, style: const TextStyle(fontSize: 12, color: Colors.black54))),
          ]),
        ),
      ),
      if (_adviceSource == 'llm' && !_generating)
        ExpansionTile(
          title: const Text('ధృవీకరించిన చర్యలు (మూలం)'),
          children: [
            for (final s in [...db.genericSteps(sev.level), ...e.stepsFor(sev.level)])
              ListTile(dense: true, leading: const Icon(Icons.check, size: 18), title: Text(s)),
          ],
        ),
      if (!vr.unknownCrop && e.spraysFor(sev.level).isNotEmpty) _sprayCard(e.spraysFor(sev.level)),
      if (!vr.unknownCrop) ExpansionTile(
        title: const Text('ఎరువులు, నీటి యాజమాన్యం, కోత తర్వాత'),
        children: [
          ListTile(leading: const Icon(Icons.water_drop), title: Text(e.fertiliserIrrigation)),
          ListTile(leading: const Icon(Icons.inventory_2), title: Text(e.postHarvest)),
        ],
      ),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('⚠ ${db.verifyNote}\nమూలం: ${e.source}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ),
      Text('సమయం: severity (OpenCV) ${sev.nativeMs.toStringAsFixed(0)}ms · decode ${vr.decodeMs}ms · వ్యాధి గుర్తింపు ${vr.classifyMs}ms (model ${vr.inferenceMs.toStringAsFixed(1)}ms, INT8) · తీవ్రత ${vr.severityMs}ms',
          style: const TextStyle(fontSize: 12, color: Colors.black45)),
    ];
  }

  static const _icons = {
    'masks': Icons.masks,
    'science': Icons.science,
    'water_drop': Icons.water_drop,
    'wb_twilight': Icons.wb_twilight,
    'flip': Icons.flip,
    'umbrella': Icons.umbrella,
    'no_food': Icons.no_food,
    'wash': Icons.wash,
    'timer': Icons.timer,
  };

  Widget _sprayCard(List<Spray> sprays) {
    final db = _pipeline.db;
    return Card(
      color: const Color(0xFFF1F8E9),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('మందు & మోతాదు', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final sp in sprays)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade200)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Picture of the product form: powder packet vs liquid bottle.
                Container(
                  width: 64,
                  height: 80,
                  decoration: BoxDecoration(
                      color: sp.liquid ? Colors.blue.shade50 : Colors.orange.shade50, borderRadius: BorderRadius.circular(10)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(sp.liquid ? Icons.local_drink : Icons.inventory_2, size: 34, color: sp.liquid ? Colors.blue : Colors.deepOrange),
                    Text(sp.liquid ? 'ద్రవం' : 'పొడి', style: const TextStyle(fontSize: 12)),
                  ]),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sp.nameTe, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    Text('${sp.nameEn} · ${sp.kind}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                    const SizedBox(height: 4),
                    Text('1 లీటరు నీటికి: ${sp.doseFor(1)}'),
                    for (final t in db.tankSizes) Text('${t.$1}: ${sp.doseFor(t.$2)}', style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
              ]),
            ),
          const Divider(),
          Text('ఎలా పిచికారీ చేయాలి', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          for (final (i, st) in db.howToSpray.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.green.shade100,
                  child: Icon(_icons[st[0]] ?? Icons.check, color: Colors.green.shade900),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text('${i + 1}. ${st[1]}')),
              ]),
            ),
        ]),
      ),
    );
  }
}
